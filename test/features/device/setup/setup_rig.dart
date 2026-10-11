import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/device/setup/setup_controller.dart';
import 'package:glyph/features/device/setup/setup_store.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/onboarding/search_step.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/setup/setup_wizard.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/ddp.dart';
import 'package:glyph/wled/panel_setup.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_setup_device.dart';
import 'fake_setup_wifi.dart';

const deviceHost = '192.168.1.50';

class FakeSender extends DdpSender {
  FakeSender(super.host);
  final sent = <Uint8List>[];
  bool opened = false, closed = false;

  @override
  bool get isOpen => opened && !closed;

  @override
  Future<void> open() async => opened = true;

  @override
  void send(Uint8List rgb) => sent.add(Uint8List.fromList(rgb));

  @override
  void close() => closed = true;

  /// LED indices lit in the most recent buffer.
  List<int> get lit {
    final b = sent.last;
    return [
      for (var i = 0; i < b.length ~/ 3; i++)
        if (b[i * 3] != 0 || b[i * 3 + 1] != 0 || b[i * 3 + 2] != 0) i,
    ];
  }
}

/// The device's own setup network (4.3.2.1): info, a Wi-Fi scan and writes.
class FakeApDevice {
  FakeApDevice({this.mac = '48e729a39308', this.name = 'WLED-AP-9308'});

  final String mac, name;
  int netCalls = 0;

  /// False: the phone isn't on the setup network yet, so requests fail.
  bool reachable = true;
  final writes = <(String, Object?)>[];
  var networks = <Map<String, Object>>[
    {'ssid': 'Home', 'rssi': -48, 'bssid': 'aa', 'channel': 6, 'enc': 3},
    {'ssid': 'Neighbour', 'rssi': -80, 'bssid': 'bb', 'channel': 1, 'enc': 3},
    {'ssid': 'Cafe', 'rssi': -66, 'bssid': 'cc', 'channel': 11, 'enc': 0},
  ];

  WledClient client(String host) =>
      WledClient(host, delay: (_) async {}, client: MockClient(_handle));

  Future<http.Response> _handle(http.Request r) async {
    final path = r.url.path;
    if (!reachable) throw http.ClientException('unreachable');
    if (r.method == 'GET') {
      if (path == '/json/info') {
        return http.Response(
          jsonEncode({'ver': '16.0.1', 'name': name, 'mac': mac, 'brand': 'WLED', 'arch': 'esp32', 'leds': {'count': 64}, 'fxcount': 1, 'ip': '4.3.2.1'}),
          200,
        );
      }
      if (path == '/json/net') {
        return http.Response(jsonEncode({'networks': netCalls++ == 0 ? [] : networks}), 200);
      }
      return http.Response('nope', 404);
    }
    writes.add(('POST $path', jsonDecode(r.body)));
    return http.Response('{"success":true}', 200);
  }
}

/// A WLED setup wizard on fakes: one device on the home network, one setup
/// network, the phone's Wi-Fi, a fake DDP socket and a store of backups.
class SetupRig {
  SetupRig._({
    required this.device,
    required this.ap,
    required this.devices,
    required this.playback,
    required this.wifi,
    required this.store,
    required this.controller,
    required this.senders,
    required this.catalog,
    required this.creations,
  });

  final FakeSetupDevice device;
  final FakeApDevice ap;
  final DeviceStore devices;
  final PlaybackController playback;
  final FakeSetupWifi wifi;
  final SetupStore store;
  final SetupController controller;
  final List<FakeSender> senders;
  final Catalog catalog;
  final CreationsStore creations;

  FakeSender get sender => senders.last;

  /// Writes to the device that change its configuration (not live streaming).
  List<(String, Object?)> get configWrites => [
    for (final w in device.writes)
      if (w.$1 == 'POST /json/cfg' || w.$1 == 'POST /settings/2D') w,
  ];

  static Future<SetupRig> create(
    WidgetTester tester, {
    FakeSetupDevice? device,
    Map<String, FakeSetupDevice> otherDevices = const {},
    FakeApDevice? ap,
    FakeSetupWifi? wifi,
    SetupEntry entry = SetupEntry.existing,
    SetupServices? services,
    SetupStore? store,
    Duration findTimeout = const Duration(seconds: 5),
    Future<void> Function(Duration)? delay,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({...prefs});
    final dev = device ?? FakeSetupDevice(width: 8, height: 8, ledCount: 64);
    final apDev = ap ?? FakeApDevice();
    WledClient factory(String h) => h == '4.3.2.1' ? apDev.client(h) : (otherDevices[h] ?? dev).client(h);
    final devices = DeviceStore(clientFactory: factory);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    final senders = <FakeSender>[];
    final theWifi = wifi ?? FakeSetupWifi();
    final theStore = store ?? SetupStore(delay: (_) async {});
    if (entry == SetupEntry.existing) await devices.addAndSelect(deviceHost, 'Desk');
    final controller = SetupController(
      devices: devices,
      playback: playback,
      wifi: theWifi,
      store: theStore,
      entry: entry,
      services: services ?? SetupServices(discover: () => const Stream.empty(), scan: () => const Stream.empty()),
      clientFactory: factory,
      senderFactory: (h) {
        final s = FakeSender(h);
        senders.add(s);
        return s;
      },
      delay: delay ?? (_) async {},
      findTimeout: findTimeout,
      findScanAfter: const Duration(milliseconds: 200),
      findRescanGap: const Duration(milliseconds: 200),
      guidedPoll: const Duration(milliseconds: 500),
    );
    return SetupRig._(
      device: dev,
      ap: apDev,
      devices: devices,
      playback: playback,
      wifi: theWifi,
      store: theStore,
      controller: controller,
      senders: senders,
      catalog: Catalog.parse(File('assets/catalog/starter.json').readAsStringSync()),
      creations: CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph')),
    );
  }

  /// Hosts the wizard on [controller] in a 360×740 phone.
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(360, 740),
    double textScale = 1,
    bool reduceMotion = false,
    VoidCallback? onExit,
    VoidCallback? onDone,
    SetupServices? services,
    bool onePanel = true,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        playback: playback,
        devices: devices,
        catalog: catalog,
        creations: creations,
        child: MaterialApp(
          theme: buildTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SafeArea(
              child: SetupWizard(
                entry: controller.entry,
                services: services ?? controller.services,
                controllerBuilder: (_) => controller,
                onExit: onExit ?? () {},
                onDone: onDone ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    // Most tests are about a single panel: a strip first asks "one or
    // several?", so answer it. Pass `onePanel: false` to see that question.
    if (onePanel) await chooseOnePanel(tester);
  }
}

/// Answers "Is your display one panel or several?" with One panel, when it
/// is showing (waits a moment for a device that is still being read).
Future<void> chooseOnePanel(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    if (find.text('Is your display one panel or several?').evaluate().isNotEmpty) {
      await tester.tap(find.text('One panel'));
      await settle(tester, 400);
      return;
    }
    await settle(tester, 200);
  }
}

/// Fixed-duration pumps: previews and spinners tick forever.
Future<void> settle(WidgetTester tester, [int ms = 500]) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 8));
  }
}

/// Which LED a device with [truth] wiring lights, as a logical corner.
StartCorner cornerOfIndex(PanelWiring truth, int index, int w, int h) {
  final (x, y) = truth.positionOf(index, w, h);
  return StartCorner.of(bottom: y == h - 1, right: x == w - 1);
}
