import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/generators/intro.dart';
import 'package:glyph/features/device/setup/setup_controller.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/onboarding/onboarding_flow.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/discovery.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/device/fake_wled.dart';
import '../../features/device/setup/setup_rig.dart';
import '../../wled/fixtures.dart';

void main() {
  late FakeWled wled;
  late Catalog catalog;

  setUp(() {
    wled = FakeWled();
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
  });

  Future<(DeviceStore, PlaybackController)> pump(
    WidgetTester tester, {
    required VoidCallback onDone,
    SetupServices services = const SetupServices(),
  }) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final devices = DeviceStore(clientFactory: wled.client);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    final creations = CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph'));
    await tester.pumpWidget(
      AppScope(
        playback: playback,
        devices: devices,
        catalog: catalog,
        creations: creations,
        child: MaterialApp(
          theme: buildTheme(),
          home: OnboardingFlow(onDone: onDone, services: services),
        ),
      ),
    );
    await settle(tester);
    return (devices, playback);
  }

  testWidgets('welcome → just looking around finishes without a device', (tester) async {
    var done = 0;
    final (devices, playback) = await pump(tester, onDone: () => done++);
    await settle(tester, 1800); // the wordmark sweep
    expect(find.text('Your device, alive.'), findsOneWidget);
    expect(find.text('Find my device'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Just looking around'));
    await settle(tester);
    expect(done, 1);
    expect(await OnboardingFlow.isDone(), isTrue);
    expect(devices.saved, isEmpty);
    playback.pause();
  });

  Future<SetupRig> pumpRig(
    WidgetTester tester, {
    required VoidCallback onDone,
    required SetupServices services,
  }) async {
    final rig = await SetupRig.create(tester, entry: SetupEntry.newDevice, services: services);
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        playback: rig.playback,
        devices: rig.devices,
        catalog: rig.catalog,
        creations: rig.creations,
        child: MaterialApp(
          theme: buildTheme(),
          home: OnboardingFlow(onDone: onDone, services: services, controllerBuilder: (_) => rig.controller),
        ),
      ),
    );
    await settle(tester);
    return rig;
  }

  testWidgets('find → connect → ready → first vibe', (tester) async {
    var done = 0;
    final services = SetupServices(
      discover: () => Stream.value(const DiscoveredDevice(name: 'Desk matrix', host: deviceHost, mac: '48e729a39308')),
      scan: () => const Stream.empty(),
    );
    final rig = await pumpRig(tester, onDone: () => done++, services: services);
    await tester.tap(find.text('Find my device'));
    await settle(tester);
    expect(find.text('Is your device on your Wi-Fi?'), findsOneWidget);
    await tester.tap(find.text('Yes, it\'s on my Wi-Fi'));
    await settle(tester);
    expect(find.text('Looking for your device'), findsOneWidget);
    expect(find.text('Desk matrix'), findsOneWidget);
    expect(find.text(deviceHost), findsOneWidget);

    // It is already set up: check it, then the intro plays on it.
    await tester.tap(find.text('Desk matrix'));
    await settle(tester, 1200);
    expect(rig.devices.isConnected, isTrue);
    expect(find.text('Does it match?'), findsOneWidget);
    await tester.tap(find.text('It matches'));
    await settle(tester, 1000);
    expect(find.text('Your device is ready.'), findsOneWidget);
    expect(rig.playback.generator, isA<GlyphIntro>());
    expect(rig.playback.generator!.name, 'Glyph intro');
    await tester.tap(find.text('Done'));
    await settle(tester, 700);

    expect(find.text('Pick a first vibe'), findsOneWidget);
    expect(find.text('It plays on your device straight away.'), findsOneWidget);
    expect(find.text('Calm'), findsOneWidget);
    expect(find.text('Party'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Calm'));
    await settle(tester);
    expect(done, 1);
    expect(await OnboardingFlow.isDone(), isTrue);
    expect(rig.playback.item?.category, 'Chill');
    rig.playback.pause();
  });

  testWidgets('can\'t see it → typed address connects', (tester) async {
    final probed = <String>[];
    final services = SetupServices(
      discover: () => const Stream.empty(),
      scan: () => const Stream.empty(),
      probe: (host) {
        probed.add(host);
        return probeHost(
          host,
          client: MockClient((r) async => r.url.host == '192.168.29.6'
              ? http.Response(infoEsp32V16, 200)
              : http.Response('nope', 404)),
        );
      },
    );
    final rig = await pumpRig(tester, onDone: () {}, services: services);
    await tester.tap(find.text('Find my device'));
    await settle(tester);
    await tester.tap(find.text('Yes, it\'s on my Wi-Fi'));
    await settle(tester);

    // After a few quiet seconds the help opens up by itself.
    await settle(tester, 6400);
    expect(find.text('Type its address'), findsOneWidget);
    expect(find.textContaining('same Wi-Fi'), findsWidgets);
    await tester.tap(find.text('Type its address'));
    await settle(tester);

    // A wrong address explains itself; the right one connects.
    await tester.enterText(find.byType(TextField), '10.0.0.9');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await settle(tester);
    expect(find.textContaining('Nothing answered at 10.0.0.9'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '192.168.29.6');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await settle(tester, 1200);
    expect(probed, ['10.0.0.9', '192.168.29.6']);
    expect(rig.devices.selected?.host, '192.168.29.6');
    expect(find.text('Does it match?'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Back goes to the first question again, and ends the picture.
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('Is your device on your Wi-Fi?'), findsOneWidget);
    expect(rig.sender.closed, isTrue);
    rig.playback.pause();
  });
}

/// Fixed-duration pumps: previews and the radar tick forever.
Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 8));
  }
}
