// Screenshot harness for the setup wizard: renders every screen to a PNG.
//   GLYPH_SCREENSHOTS=1 flutter test test/ui/setup/wizard_screenshots_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/generators/intro.dart';
import 'package:glyph/features/device/setup/setup_controller.dart';
import 'package:glyph/ui/onboarding/search_step.dart';
import 'package:glyph/ui/setup/setup_wizard.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/discovery.dart';

import '../../features/device/setup/fake_setup_device.dart';
import '../../features/device/setup/fake_setup_wifi.dart';
import '../../features/device/setup/setup_rig.dart';

const _outDir =
    '/private/tmp/claude-501/-Users-Spandan-github-com-spandan-kumar-glyph/5789bd4a-1507-44ca-bb25-23079b71986a/scratchpad/wizard/shots';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = File(p).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = Platform.environment['GLYPH_SCREENSHOTS'] == null;

  setUpAll(() async {
    if (skip) return;
    Directory(_outDir).createSync(recursive: true);
    await _loadFont('Bricolage', ['assets/fonts/BricolageGrotesque.ttf']);
    await _loadFont('DMMono', ['assets/fonts/DMMono-Regular.ttf', 'assets/fonts/DMMono-Medium.ttf']);
    final home = Platform.environment['HOME'];
    await _loadFont('MaterialIcons', [
      '$home/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  final key = GlobalKey();

  /// Like SetupRig.pump, at 412×915 @2.6 and inside a RepaintBoundary.
  Future<void> pump(
    WidgetTester tester,
    SetupRig rig, {
    Size size = const Size(412, 915),
    double textScale = 1,
    VoidCallback? onDone,
  }) async {
    tester.view.physicalSize = size * 2.6;
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AppScope(
          playback: rig.playback,
          devices: rig.devices,
          catalog: rig.catalog,
          creations: rig.creations,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: SafeArea(
                child: SetupWizard(
                  entry: rig.controller.entry,
                  services: rig.controller.services,
                  controllerBuilder: (_) => rig.controller,
                  onExit: () {},
                  onDone: onDone ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.6);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 500}) async {
    await tester.tap(find.text(text).first);
    await settle(tester, ms);
  }

  Future<void> tapLabel(WidgetTester tester, String label, {int ms = 500}) async {
    await tester.tap(find.bySemanticsLabel(label));
    await settle(tester, ms);
  }

  SetupServices found({String name = 'Desk', String mac = '48e729a39308'}) => SetupServices(
    discover: () => Stream.value(DiscoveredDevice(name: name, host: deviceHost, mac: mac)),
    scan: () => const Stream.empty(),
  );

  FakeSetupDevice plain({int w = 8, int h = 8, int leds = 64}) =>
      FakeSetupDevice(width: w, height: h, ledCount: leds, matrix: false);

  Future<SetupRig> joinRig(WidgetTester t, {FakeSetupWifi? wifi, FakeApDevice? ap, String? mac, Duration? timeout}) {
    return SetupRig.create(
      t,
      entry: SetupEntry.newDevice,
      device: plain(),
      wifi: wifi,
      ap: ap,
      findTimeout: timeout ?? const Duration(seconds: 5),
      services: found(name: 'WLED-AP-9308', mac: mac ?? '48:E7:29:A3:93:08'),
    );
  }

  FakeApDevice fiveNetworks() => FakeApDevice()
    ..networks = [
      {'ssid': 'Home', 'rssi': -45, 'bssid': 'aa', 'channel': 6, 'enc': 3},
      {'ssid': 'Studio 5', 'rssi': -58, 'bssid': 'bb', 'channel': 1, 'enc': 3},
      {'ssid': 'Cafe', 'rssi': -66, 'bssid': 'cc', 'channel': 11, 'enc': 0},
      {'ssid': 'Neighbour', 'rssi': -78, 'bssid': 'dd', 'channel': 3, 'enc': 3},
      {'ssid': 'Garage', 'rssi': -88, 'bssid': 'ee', 'channel': 9, 'enc': 3},
    ];

  Future<void> toPicker(WidgetTester t, SetupRig rig) async {
    await pump(t, rig);
    await tapText(t, 'No, it\'s new');
  }

  // Wiring journey for [w]×[h] from the size screen.
  Future<void> toWiring(WidgetTester t, SetupRig rig, String sizeLabel) async {
    await pump(t, rig);
    await settle(t, 600);
    await t.tap(find.bySemanticsLabel(sizeLabel));
    await settle(t, 300);
    await tapText(t, 'Next');
    await settle(t, 500);
  }

  Future<void> wiringResult(WidgetTester t, SetupRig rig) async {
    await tapLabel(t, 'Top left corner');
    await settle(t, 1000);
    await tapLabel(t, 'Across');
    await settle(t, 300);
    await tapLabel(t, 'On the right');
  }

  Future<SetupRig> toReview(WidgetTester t, {FakeSetupDevice? device}) async {
    final rig = await SetupRig.create(t, device: device ?? plain());
    await toWiring(t, rig, '16 by 16');
    await wiringResult(t, rig);
    await tapText(t, 'Looks right');
    return rig;
  }

  void t(String name, Future<void> Function(WidgetTester) body) {
    testWidgets('shot $name', (tester) async {
      await body(tester);
      expect(tester.takeException(), isNull);
    }, skip: skip);
  }

  t('01_connect', (tester) async {
    final rig = await SetupRig.create(tester, entry: SetupEntry.newDevice);
    await pump(tester, rig);
    await shot(tester, '01_connect_choice');
    rig.playback.pause();
  });

  t('02_join', (tester) async {
    final rig = await joinRig(tester);
    await toPicker(tester, rig);
    await shot(tester, '02_join_assisted');
    rig.playback.pause();
  });

  t('03_join_guided', (tester) async {
    final rig = await joinRig(tester, wifi: FakeSetupWifi(assisted: false));
    await toPicker(tester, rig);
    await shot(tester, '03_join_guided');
    await settle(tester, 1200); // let the poll move on so no timers pend
    rig.playback.pause();
  });

  t('04_05_wifi', (tester) async {
    final rig = await joinRig(tester, ap: fiveNetworks());
    await toPicker(tester, rig);
    await tapText(tester, 'Connect', ms: 800);
    await shot(tester, '04_wifi_list');
    await tapText(tester, 'Home');
    await tester.enterText(find.byType(TextField).last, 'hunter22');
    await settle(tester, 200);
    await shot(tester, '05_wifi_selected_password');
    rig.playback.pause();
  });

  Future<SetupRig> toJoining(WidgetTester tester) async {
    final rig = await joinRig(tester, ap: fiveNetworks(), timeout: const Duration(seconds: 3));
    rig.controller.setupMac = 'ffffffffffff';
    await toPicker(tester, rig);
    await tapText(tester, 'Connect', ms: 800);
    rig.controller.setupMac = 'ffffffffffff';
    await tapText(tester, 'Home');
    await tester.enterText(find.byType(TextField).last, 'hunter22');
    await settle(tester, 100);
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await settle(tester, 800);
    return rig;
  }

  t('06_joining', (tester) async {
    final rig = await toJoining(tester);
    await shot(tester, '06_joining_searching');
    rig.playback.pause();
  });

  t('07_joining_failure', (tester) async {
    final rig = await toJoining(tester);
    await settle(tester, 3500);
    await shot(tester, '07_joining_failure');
    rig.playback.pause();
  });

  t('08_pin', (tester) async {
    final rig = await SetupRig.create(
      tester,
      device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false, pin: '1234'),
    );
    await pump(tester, rig);
    await settle(tester, 600);
    await shot(tester, '08_pin');
    rig.playback.pause();
  });

  t('09_unsupported', (tester) async {
    final d = FakeSetupDevice(width: 8, height: 8, ledCount: 64);
    (((d.cfg['hw'] as Map)['led'] as Map)['ins'] as List).add({'len': 8, 'type': 22});
    final rig = await SetupRig.create(tester, device: d);
    await pump(tester, rig);
    await settle(tester, 600);
    await shot(tester, '09_unsupported_multiple_outputs');
    rig.playback.pause();
  });

  t('10_size', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(leds: 256));
    await pump(tester, rig);
    await settle(tester, 600);
    await tester.tap(find.bySemanticsLabel('16 by 16'));
    await settle(tester, 300);
    await shot(tester, '10_size_16x16');
    rig.playback.pause();
  });

  t('11_size_mismatch', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(leds: 150));
    await pump(tester, rig);
    await settle(tester, 600);
    await tester.tap(find.bySemanticsLabel('16 by 16'));
    await settle(tester, 300);
    await shot(tester, '11_size_mismatch_note');
    rig.playback.pause();
  });

  t('12_size_other', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(leds: 256));
    await pump(tester, rig);
    await settle(tester, 600);
    await tester.tap(find.bySemanticsLabel('16 by 16'));
    await settle(tester, 300);
    await tapText(tester, 'Other size');
    await shot(tester, '12_size_other_open');
    rig.playback.pause();
  });

  t('13_wiring_q1', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(leds: 256));
    await toWiring(tester, rig, '16 by 16');
    await shot(tester, '13_wiring_q1');
    rig.playback.pause();
  });

  t('14_16_wiring_32x8', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(w: 32, h: 8, leds: 256));
    await toWiring(tester, rig, '32 by 8');
    await tapLabel(tester, 'Top left corner');
    await settle(tester, 1000);
    await shot(tester, '14_wiring_q2_32x8');
    await tapLabel(tester, 'Across');
    await settle(tester, 300);
    await shot(tester, '15_wiring_q3_32x8');
    await tapLabel(tester, 'On the right');
    await shot(tester, '16_wiring_result_32x8');
    await tapText(tester, 'Choose it myself');
    await shot(tester, '17_manual_picker');
    rig.playback.pause();
  });

  t('30_size_grid', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(w: 32, h: 8, leds: 256));
    await pump(tester, rig);
    await settle(tester, 600);
    await tester.tap(find.bySemanticsLabel('32 by 8'));
    await settle(tester, 300);
    await shot(tester, '30_size_grid');
    rig.playback.pause();
  });

  t('31_q2_q3_zoomed', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(w: 32, h: 8, leds: 256));
    await toWiring(tester, rig, '32 by 8');
    await tapLabel(tester, 'Top left corner');
    await settle(tester, 1000);
    await shot(tester, '31_q2_32x8');
    await tapLabel(tester, 'Across');
    await settle(tester, 300);
    await shot(tester, '32_q3_32x8');
    rig.playback.pause();
  });

  t('33_q3_8x32', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(w: 8, h: 32, leds: 256));
    await toWiring(tester, rig, '8 by 32');
    await tapLabel(tester, 'Top left corner');
    await settle(tester, 1000);
    await tapLabel(tester, 'Down');
    await settle(tester, 300);
    await shot(tester, '33_q3_8x32');
    rig.playback.pause();
  });

  t('34_result_straight', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(leds: 256));
    await toWiring(tester, rig, '16 by 16');
    await tapLabel(tester, 'Top left corner');
    await settle(tester, 1000);
    await tapLabel(tester, 'Across');
    await settle(tester, 300);
    await tapLabel(tester, 'On the left');
    await shot(tester, '34_result_straight_16x16');
    rig.playback.pause();
  });

  t('18_review', (tester) async {
    final rig = await toReview(tester);
    await shot(tester, '18_review');
    await tapText(tester, 'Power limit');
    await tapText(tester, '5 A');
    await shot(tester, '19_power_sheet');
    rig.playback.pause();
  });

  t('20_applying', (tester) async {
    final gate = Completer<void>();
    final dev = plain();
    final rig = await SetupRig.create(tester, device: dev, delay: (_) => gate.future);
    await toWiring(tester, rig, '16 by 16');
    await wiringResult(tester, rig);
    await tapText(tester, 'Looks right');
    await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
    await settle(tester, 600);
    await shot(tester, '20_applying');
    gate.complete();
    await settle(tester, 1500);
    rig.playback.pause();
  });

  t('21_apply_failure', (tester) async {
    final rig = await toReview(tester);
    rig.device.ignoreLayout = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
    await settle(tester, 1500);
    await shot(tester, '21_apply_failure');
    rig.playback.pause();
  });

  t('22_look_and_close_sheet', (tester) async {
    final rig = await toReview(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
    await settle(tester, 1500);
    await shot(tester, '22_look');
    await tester.tap(find.byTooltip('Close'));
    await settle(tester, 500);
    await shot(tester, '23_close_sheet');
    rig.playback.pause();
  });

  t('24_done_new', (tester) async {
    final rig = await SetupRig.create(tester, entry: SetupEntry.newDevice, services: found());
    await pump(tester, rig);
    await tapText(tester, 'Yes, it\'s on my Wi-Fi');
    await tapText(tester, 'Desk', ms: 1200);
    await tapText(tester, 'It matches', ms: 900);
    await shot(tester, '24_done_new_device');
    rig.playback.pause();
  });

  t('25_done_existing', (tester) async {
    final rig = await SetupRig.create(tester);
    rig.playback.playGenerator(GlyphIntro());
    await pump(tester, rig);
    await settle(tester, 800);
    await tapText(tester, 'It matches', ms: 900);
    await shot(tester, '25_done_existing');
    rig.playback.pause();
  });

  // --- Several panels ---------------------------------------------------------

  /// A 4x2 grid of 16x16 panels on a device with 2048 LEDs, at the grid screen.
  Future<SetupRig> toGridScreen(WidgetTester t) async {
    final rig = await SetupRig.create(t, device: plain(leds: 2048));
    await pump(t, rig);
    await settle(t, 600);
    await tapText(t, 'Several panels');
    return rig;
  }

  /// Through the order questions of a snake of 4x2 panels, to [stopAt].
  Future<SetupRig> toOrder(WidgetTester t, {int stopAt = 3}) async {
    final rig = await toGridScreen(t);
    await tapText(t, 'Next', ms: 900);
    if (stopAt == 1) return rig;
    await tapLabel(t, 'Panel in row 1, column 1');
    if (stopAt == 2) return rig;
    await tapLabel(t, 'Panel in row 1, column 2');
    if (stopAt == 3) return rig;
    await tapLabel(t, 'On the right');
    return rig;
  }

  t('40_panels_choice', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(leds: 2048));
    await pump(tester, rig);
    await settle(tester, 600);
    await shot(tester, '40_panels_choice');
    rig.playback.pause();
  });

  t('41_grid_layout', (tester) async {
    final rig = await toGridScreen(tester);
    await shot(tester, '41_grid_layout');
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await settle(tester, 300);
    await shot(tester, '41b_grid_layout_scrolled');
    rig.playback.pause();
  });

  t('42_grid_other_and_limit', (tester) async {
    final rig = await toGridScreen(tester);
    rig.controller.setGrid(4, 5, click: false);
    await tapText(tester, 'Other size');
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await settle(tester, 300);
    await shot(tester, '42_grid_limit_over');
    rig.playback.pause();
  });

  t('43_order_q1', (tester) async {
    final rig = await toOrder(tester, stopAt: 1);
    await shot(tester, '43_order_q1');
    rig.playback.pause();
  });

  t('44_order_q2', (tester) async {
    final rig = await toOrder(tester, stopAt: 2);
    await shot(tester, '44_order_q2');
    rig.playback.pause();
  });

  t('45_order_q3', (tester) async {
    final rig = await toOrder(tester, stopAt: 3);
    await shot(tester, '45_order_q3');
    rig.playback.pause();
  });

  t('46_order_result', (tester) async {
    final rig = await toOrder(tester, stopAt: 4);
    await shot(tester, '46_order_result');
    await tapText(tester, 'Choose it myself');
    await shot(tester, '46b_order_manual');
    rig.playback.pause();
  });

  Future<SetupRig> toOrientation(WidgetTester t) async {
    final rig = await toOrder(t, stopAt: 4);
    await tapText(t, 'Looks right');
    await tapLabel(t, 'Top left corner');
    await settle(t, 1000);
    await tapLabel(t, 'Across');
    await tapLabel(t, 'On the left');
    await tapText(t, 'Looks right');
    return rig;
  }

  t('47_orientation', (tester) async {
    final rig = await toOrientation(tester);
    await shot(tester, '47_orientation_none');
    await tapLabel(tester, 'Panel 6');
    await tapLabel(tester, 'Panel 7');
    await shot(tester, '47b_orientation_marked');
    rig.playback.pause();
  });

  t('48_review_grid', (tester) async {
    final rig = await toOrientation(tester);
    await tapLabel(tester, 'Panel 6');
    await tapLabel(tester, 'Panel 7');
    await tapText(tester, 'Done');
    await shot(tester, '48_review_grid_4x2');
    rig.playback.pause();
  });

  t('49_wiring_in_panel', (tester) async {
    final rig = await toOrder(tester, stopAt: 4);
    await tapText(tester, 'Looks right');
    await shot(tester, '49_wiring_q1_in_panel');
    rig.playback.pause();
  });

  t('26_scale_connect', (tester) async {
    final rig = await SetupRig.create(tester, entry: SetupEntry.newDevice);
    await pump(tester, rig, size: const Size(360, 640), textScale: 1.6);
    await shot(tester, '26_scale1.6_connect');
    rig.playback.pause();
  });

  t('27_scale_size', (tester) async {
    final rig = await SetupRig.create(tester, device: plain());
    await pump(tester, rig, size: const Size(360, 640), textScale: 1.6);
    await settle(tester, 600);
    rig.controller.setSize(17, 9, click: false);
    await settle(tester, 300);
    await shot(tester, '27_scale1.6_size');
    rig.playback.pause();
  });

  t('28_scale_wiring', (tester) async {
    final rig = await SetupRig.create(tester, device: plain(w: 32, h: 8, leds: 256));
    await pump(tester, rig, size: const Size(360, 640), textScale: 1.6);
    await settle(tester, 600);
    rig.controller.sizeNext();
    await settle(tester, 600);
    await shot(tester, '28_scale1.6_wiring_q1');
    rig.playback.pause();
  });
}
