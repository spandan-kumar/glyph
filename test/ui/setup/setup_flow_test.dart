import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/generators/intro.dart';
import 'package:glyph/features/device/setup/setup_controller.dart';
import 'package:glyph/features/device/setup/setup_store.dart';
import 'package:glyph/ui/onboarding/search_step.dart';
import 'package:glyph/ui/setup/check_screens.dart';
import 'package:glyph/wled/discovery.dart';
import 'package:glyph/wled/layout.dart';
import 'package:glyph/wled/panel_setup.dart';

import '../../features/device/setup/fake_setup_device.dart';
import '../../features/device/setup/setup_rig.dart';

/// Remembers how many configuration writes had happened when a backup was
/// saved.
class SpyStore extends SetupStore {
  SpyStore(this.configWrites) : super(delay: (_) async {});

  final List<(String, Object?)> Function() configWrites;
  final savedAt = <List<(String, Object?)>>[];

  @override
  Future<void> save(SetupSnapshot snapshot) {
    savedAt.add(configWrites());
    return super.save(snapshot);
  }
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final haptics = <String>[];
  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
        return null;
      },
    );
  });

  Future<void> tapText(WidgetTester tester, String text, {int ms = 500}) async {
    await tester.tap(find.text(text).first);
    await settle(tester, ms);
  }

  Future<void> tapLabel(WidgetTester tester, String label, {int ms = 500}) async {
    await tester.tap(find.bySemanticsLabel(label));
    await settle(tester, ms);
  }

  /// Plays the person: reads what the "device" shows from what was sent to
  /// it (physical LED indices of a display wired as [truth]) and answers.
  Future<void> answerWiring(WidgetTester tester, SetupRig rig, PanelWiring truth, int w, int h) async {
    // Q1: LED 0 is lit; which corner of the panel is it in?
    expect(find.text('Which corner lit up?'), findsOneWidget);
    expect(rig.sender.lit, [0]);
    final corner = cornerOfIndex(truth, 0, w, h);
    await tapLabel(tester, '${_cap(corner.label)} corner');

    // Q2: the chase moves along the first run.
    expect(find.text('Which way is it moving?'), findsOneWidget);
    await settle(tester, 1000);
    final seen = {for (final b in rig.sender.sent) ...List.generate(b.length ~/ 3, (i) => i).where((i) => b[i * 3] != 0)};
    expect(seen.length, greaterThan(1));
    final (x0, y0) = truth.positionOf(0, w, h);
    final (x1, y1) = truth.positionOf(1, w, h);
    expect(seen, containsAll([0, 1]));
    final alongWidth = y1 == y0 && x1 != x0;
    await tapLabel(tester, alongWidth ? 'Across' : (corner.isBottom ? 'Up' : 'Down'));

    // Q3: the light jumps to the first LED of the second run.
    expect(find.text('Where did the light jump to?'), findsOneWidget);
    final run = alongWidth ? w : h;
    expect(rig.sender.lit, [run]);
    final (jx, jy) = truth.positionOf(run, w, h);
    final far = alongWidth ? jx != x0 : jy != y0;
    final nearLabel = alongWidth
        ? (corner.isRight ? 'On the right' : 'On the left')
        : (corner.isBottom ? 'At the bottom' : 'At the top');
    final farLabel = alongWidth
        ? (corner.isRight ? 'On the left' : 'On the right')
        : (corner.isBottom ? 'At the top' : 'At the bottom');
    await tapLabel(tester, far ? farLabel : nearLabel);
    expect(find.text('Here\'s how it\'s wired'), findsOneWidget);
  }

  group('check', () {
    testWidgets('a settings PIN is asked for, a wrong one explained, the right one unlocks', (tester) async {
      final rig = await SetupRig.create(
        tester,
        device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false, pin: '1234'),
      );
      await rig.pump(tester);
      await settle(tester, 600);
      expect(find.text('This device has a settings PIN'), findsOneWidget);
      expect(rig.configWrites, isNotEmpty, reason: 'the lock probe was refused');
      await tester.enterText(find.byType(TextField), '0000');
      await tapText(tester, 'Unlock', ms: 600);
      expect(find.text('That PIN didn\'t work. Try again.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1234');
      await tapText(tester, 'Unlock', ms: 900);
      expect(find.text('How big is your display?'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('an unreachable device says so and can try again', (tester) async {
      final device = FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false);
      final rig = await SetupRig.create(tester, device: device);
      device.offline = true;
      await rig.pump(tester);
      await settle(tester, 800);
      expect(find.text('Can\'t reach it right now'), findsOneWidget);
      expect(find.text('Check it\'s plugged in and on the same Wi-Fi as your phone.'), findsOneWidget);
      device.offline = false;
      await tapText(tester, 'Try again', ms: 800);
      expect(find.text('How big is your display?'), findsOneWidget);
      rig.playback.pause();
    });

    for (final (label, tweak, text) in <(String, void Function(FakeSetupDevice), String)>[
      ('several outputs', (d) => ((d.cfg['hw'] as Map)['led'] as Map)['ins'].add({'len': 8, 'type': 22}), 'It uses more than one LED output.'),
      ('an unsupported output', (d) => (((d.cfg['hw'] as Map)['led'] as Map)['ins'] as List).first['type'] = 80, 'Its LEDs aren\'t a type Glyph can set up.'),
      ('a live offset', (d) => ((d.cfg['if'] as Map)['live'] as Map)['offset'] = 5, 'It has a live offset set in its settings.'),
    ]) {
      testWidgets('unsupported: $label', (tester) async {
        final device = FakeSetupDevice(width: 8, height: 8, ledCount: 64);
        tweak(device);
        final rig = await SetupRig.create(tester, device: device);
        await rig.pump(tester);
        await settle(tester, 600);
        expect(find.text('Glyph can\'t set up this display yet'), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        expect(find.text('You can still turn pictures the right way round.'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Fix orientation'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Done'), findsOneWidget);
        // The existing guided fix stays reachable.
        await tapText(tester, 'Fix orientation', ms: 700);
        expect(find.text('Which way is the arrow pointing on your device?'), findsOneWidget);
        await tester.tap(find.byTooltip('Back').last);
        await settle(tester, 700);
        expect(find.text('Glyph can\'t set up this display yet'), findsOneWidget);
        await tapText(tester, 'Done', ms: 600);
        expect(rig.device.clockSets, isNotEmpty, reason: 'even unsupported devices get the time');
        rig.playback.pause();
      });
    }

    testWidgets('multiple panels are named', (tester) async {
      final panels = FakeSetupDevice(width: 8, height: 8, ledCount: 64);
      (panels.cfg['hw'] as Map)['led']['matrix']['panels'].add({'b': false, 'r': false, 'v': false, 's': false, 'x': 8, 'y': 0, 'w': 8, 'h': 8});
      final rig = await SetupRig.create(tester, device: panels);
      await rig.pump(tester);
      await settle(tester, 600);
      expect(find.text('It\'s made of several panels.'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('a custom map is named', (tester) async {
      final rig = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, customMap: true));
      await rig.pump(tester);
      await settle(tester, 600);
      expect(find.text('It uses a custom LED map.'), findsOneWidget);
      rig.playback.pause();
    });

    test('every reason has plain words', () {
      for (final r in SetupSupport.values.where((r) => r != SetupSupport.supported)) {
        expect(unsupportedReason(r), isNotEmpty);
        expect(unsupportedReason(r), isNot(contains('matrix')));
      }
      expect(unsupportedReason(SetupSupport.noTwoD), 'Its firmware has no 2D support.');
    });
  });

  group('fast path', () {
    testWidgets('already set up: Look, then Done, then the session is gone', (tester) async {
      var done = 0;
      final rig = await SetupRig.create(tester);
      rig.playback.playGenerator(GlyphIntro());
      await rig.pump(tester, onDone: () => done++);
      await settle(tester, 800);
      expect(find.text('Does it match?'), findsOneWidget);
      expect(find.text('The arrow points up and the orange block sits in the top left corner.'), findsOneWidget);
      expect(find.text('It matches'), findsOneWidget);
      expect(find.text('It doesn\'t match'), findsOneWidget);
      expect(find.text('Undo setup'), findsNothing, reason: 'nothing was changed');
      expect(rig.sender.opened, isTrue);
      expect(rig.sender.sent, isNotEmpty);
      expect(rig.playback.isPlaying, isFalse, reason: 'paused while the test picture shows');
      expect(rig.configWrites, hasLength(1), reason: 'only the lock check, which changes nothing');

      await tapText(tester, 'It matches', ms: 900);
      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      expect(find.text('Your device is ready.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'only new devices are named');
      expect(rig.sender.closed, isTrue);
      expect(
        rig.device.writes.where((w) => w.$1 == 'POST /json/state' && (w.$2 as Map)['live'] == false),
        isNotEmpty,
      );
      expect(rig.playback.isPlaying, isTrue, reason: 'previous playback is back');
      expect(rig.configWrites, hasLength(1));
      await tapText(tester, 'Done');
      expect(done, 1);
      expect(rig.device.clockSets, isNotEmpty, reason: 'setup sets the device clock');
      expect(rig.device.ntpWrites.single['en'], isTrue, reason: 'and turns internet time on');
      expect(tester.takeException(), isNull);
      rig.playback.pause();
    });

    testWidgets('new device: Done names it and plays the intro', (tester) async {
      var done = 0;
      final rig = await SetupRig.create(
        tester,
        entry: SetupEntry.newDevice,
        services: SetupServices(
          discover: () => Stream.value(const DiscoveredDevice(name: 'Desk', host: deviceHost, mac: '48e729a39308')),
          scan: () => const Stream.empty(),
        ),
      );
      await rig.pump(tester, onDone: () => done++);
      await tapText(tester, 'Yes, it\'s on my Wi-Fi');
      await tapText(tester, 'Desk', ms: 1200);
      expect(find.text('Does it match?'), findsOneWidget);
      await tapText(tester, 'It matches', ms: 900);
      expect(find.text('Your device is ready.'), findsOneWidget);
      expect(find.text('That\'s Glyph saying hi.'), findsOneWidget);
      expect(rig.playback.generator, isA<GlyphIntro>());
      await tester.enterText(find.byType(TextField), 'Lamp');
      await tapText(tester, 'Done', ms: 600);
      expect(done, 1);
      final rename = rig.device.writes.where((w) => w.$1 == 'POST /json/cfg' && (w.$2 as Map).containsKey('id'));
      expect((rename.single.$2 as Map)['id'], {'name': 'Lamp'});
      rig.playback.pause();
    });

    testWidgets('a saved app layout is made identity when it matches', (tester) async {
      final rig = await SetupRig.create(tester);
      await rig.devices.updateLayout(const MatrixLayout(flipX: true));
      await rig.pump(tester);
      await settle(tester, 800);
      await tapText(tester, 'It matches', ms: 900);
      expect(rig.devices.selected!.layout, MatrixLayout.identity);
      rig.playback.pause();
    });
  });

  group('size', () {
    testWidgets('preselects from the device and explains a mismatch', (tester) async {
      final rig = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false));
      await rig.pump(tester);
      await settle(tester, 600);
      expect(find.text('How big is your display?'), findsOneWidget);
      expect(find.text('Count the lights across and down.'), findsOneWidget);
      expect(rig.controller.draftWidth, 8);
      expect(rig.controller.draftHeight, 8);
      expect(find.text('Your device is set for 64 LEDs.'), findsOneWidget);
      expect(find.textContaining('Glyph will set it to'), findsNothing);
      for (final t in ['8×8', '16×16', '32×8', '8×32', '32×32', '16×32', 'Other size']) {
        expect(find.text(t.toUpperCase()).evaluate().isNotEmpty || find.text(t).evaluate().isNotEmpty, isTrue, reason: t);
      }

      await tester.tap(find.bySemanticsLabel('16 by 16'));
      await settle(tester, 300);
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(find.text('Glyph will set it to 256 LEDs.'), findsOneWidget);

      await tapText(tester, 'Other size');
      expect(find.text('Across'.toUpperCase()), findsOneWidget);
      expect(find.text('Down'.toUpperCase()), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('more across'));
      await settle(tester, 200);
      expect(rig.controller.draftWidth, 17);
      expect(find.text('Glyph will set it to 272 LEDs.'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('no match: nothing preselected, Next waits', (tester) async {
      final odd = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 70, matrix: false));
      await odd.pump(tester);
      await settle(tester, 600);
      expect(odd.controller.hasSize, isFalse);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNull);
      odd.playback.pause();
    });

    testWidgets('a square count is a square', (tester) async {
      final rig = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 100, matrix: false));
      await rig.pump(tester);
      await settle(tester, 600);
      expect(rig.controller.draftWidth, 10);
      expect(rig.controller.draftHeight, 10);
      rig.playback.pause();
    });
  });

  group('wiring', () {
    final truths = <(PanelWiring, int, int)>[
      (const PanelWiring(corner: StartCorner.bottomRight, vertical: true, zigzag: true), 8, 8),
      (const PanelWiring(corner: StartCorner.topRight, zigzag: true), 8, 8),
      (const PanelWiring(corner: StartCorner.bottomLeft, vertical: true), 8, 8),
      (const PanelWiring(zigzag: true), 8, 8),
      (const PanelWiring(corner: StartCorner.bottomLeft, zigzag: true), 32, 8),
      (const PanelWiring(corner: StartCorner.topRight, vertical: true), 32, 8),
    ];
    for (final (truth, w, h) in truths) {
      testWidgets('the three answers find ${truth.describe()} on ${w}x$h', (tester) async {
        final rig = await SetupRig.create(
          tester,
          device: FakeSetupDevice(width: w, height: h, ledCount: w * h, matrix: false),
        );
        await rig.pump(tester);
        await settle(tester, 600);
        await tester.tap(find.bySemanticsLabel('$w by $h'));
        await settle(tester, 300);
        expect(rig.controller.draftWidth, w);
        expect(rig.controller.draftHeight, h);
        haptics.clear();
        await tapText(tester, 'Next');
        await settle(tester, 500);
        await answerWiring(tester, rig, truth, w, h);
        expect(rig.controller.draftWiring, truth);
        expect(find.text(truth.describe()), findsOneWidget);
        expect(find.text('Looks right'), findsOneWidget);
        expect(find.text('Test again'), findsOneWidget);
        expect(find.text('Choose it myself'), findsOneWidget);
        expect(rig.sender.closed, isTrue, reason: 'the test ends on the result');
        expect(haptics.where((h) => h == 'HapticFeedbackType.selectionClick'), hasLength(3));
        expect(tester.takeException(), isNull);
        rig.playback.pause();
      });
    }

    testWidgets('the corner targets are labelled buttons', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false));
      await rig.pump(tester);
      await settle(tester, 600);
      await tapText(tester, 'Next');
      await settle(tester, 500);
      for (final c in ['Top left corner', 'Top right corner', 'Bottom left corner', 'Bottom right corner']) {
        final data = tester.getSemantics(find.bySemanticsLabel(c)).getSemanticsData();
        expect(data.label, c);
        expect(data.flagsCollection.isButton, isTrue, reason: c);
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: c);
        final box = tester.getSize(find.bySemanticsLabel(c));
        expect(box.width, greaterThanOrEqualTo(48));
        expect(box.height, greaterThanOrEqualTo(48));
      }
      expect(find.bySemanticsLabel(RegExp('Display diagram, 8 by 8 lights')), findsOneWidget);
      handle.dispose();
      rig.playback.pause();
    });

    testWidgets('result, then the manual picker with a live diagram', (tester) async {
      final rig = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false));
      await rig.pump(tester);
      await settle(tester, 600);
      await tapText(tester, 'Next');
      await settle(tester, 500);
      await answerWiring(tester, rig, const PanelWiring(), 8, 8);
      await tapText(tester, 'Choose it myself');
      expect(find.text('How is it wired?'), findsOneWidget);
      final list = find.byType(Scrollable).first;
      Future<void> reveal(Finder f) async {
        await tester.scrollUntilVisible(f, 120, scrollable: list);
        await settle(tester, 100);
      }

      await reveal(find.text('STARTS AT'));
      await reveal(find.text('Bottom right'));
      await tapText(tester, 'Bottom right');
      await reveal(find.text('RUNS ALONG'));
      await reveal(find.text('Columns'));
      await tapText(tester, 'Columns');
      await reveal(find.text('Zig-zag'));
      await tester.tap(find.text('Zig-zag'));
      await settle(tester, 300);
      const want = PanelWiring(corner: StartCorner.bottomRight, vertical: true, zigzag: true);
      expect(rig.controller.draftWiring, want);
      await tester.scrollUntilVisible(find.text('Use this'), -120, scrollable: list);
      await tapText(tester, 'Use this');
      expect(find.text('Ready to set it up'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('reduced motion: the chase shows all its lights at once and holds', (tester) async {
      final rig = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false));
      await rig.pump(tester, reduceMotion: true);
      await settle(tester, 600);
      await tapText(tester, 'Next');
      await settle(tester, 500);
      await tapLabel(tester, 'Top left corner');
      expect(find.text('Which way is it moving?'), findsOneWidget);
      expect(rig.sender.lit, [0, 1, 2, 3, 4]);
      final count = rig.sender.sent.length;
      await settle(tester, 1000);
      expect(rig.sender.lit, [0, 1, 2, 3, 4]);
      // Only the keep-alive resend, never a different picture.
      expect(rig.sender.sent.skip(count).every((b) => b.length == rig.sender.sent.first.length), isTrue);
      expect({for (final b in rig.sender.sent.skip(count - 1)) b.toString()}, hasLength(1));
      rig.playback.pause();
    });

    testWidgets('Test again restarts at the first question', (tester) async {
      final rig = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false));
      await rig.pump(tester);
      await settle(tester, 600);
      await tapText(tester, 'Next');
      await settle(tester, 500);
      await answerWiring(tester, rig, const PanelWiring(), 8, 8);
      await tapText(tester, 'Test again');
      await settle(tester, 500);
      expect(find.text('Which corner lit up?'), findsOneWidget);
      expect(rig.sender.closed, isFalse);
      expect(rig.sender.lit, [0]);
      rig.playback.pause();
    });

    testWidgets('Nothing lit up: help, then try again; more LEDs offered when short', (tester) async {
      final rig = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 8, matrix: false));
      await rig.pump(tester);
      await settle(tester, 600);
      expect(rig.controller.hasSize, isFalse);
      rig.controller.setSize(8, 8);
      await settle(tester, 200);
      await tapText(tester, 'Next');
      await settle(tester, 500);
      await tapText(tester, 'Nothing lit up');
      expect(find.text('Nothing lit up?'), findsOneWidget);
      expect(find.text('Check it\'s plugged in and switched on in Glyph.'), findsOneWidget);
      expect(find.textContaining('LED preferences'), findsOneWidget);
      expect(find.text('Your device is set for 8 LEDs.'), findsOneWidget);
      expect(find.text('Set it to 64 LEDs now'), findsOneWidget);
      final before = rig.senders.length;
      await tapText(tester, 'Try again');
      expect(rig.senders.length, before + 1, reason: 'the test starts again');
      await tapText(tester, 'Nothing lit up');
      await tapText(tester, 'Set it to 64 LEDs now', ms: 800);
      expect(rig.device.length, 64);
      expect(rig.controller.wrote, isTrue);
      rig.playback.pause();
    });

    testWidgets('a matrix device: the map is off for the test and back on after', (tester) async {
      final rig = await SetupRig.create(tester);
      await rig.pump(tester);
      await settle(tester, 800);
      await tapText(tester, 'It doesn\'t match');
      expect(find.text('How big is your display?'), findsOneWidget, reason: 'nothing was set up by Glyph yet');
      await tapText(tester, 'Next');
      await settle(tester, 600);
      expect(find.text('Which corner lit up?'), findsOneWidget);
      expect(rig.device.rlmValue, 0);
      expect(rig.sender.lit, [0]);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester, 600);
      expect(find.text('How big is your display?'), findsOneWidget);
      expect(rig.device.rlmValue, 1);
      expect(rig.sender.closed, isTrue);
      expect(
        rig.device.writes.map((w) => (w.$2 is Map && (w.$2 as Map)['if'] != null) ? ((w.$2 as Map)['if'] as Map)['live']['rlm'] : null).whereType<bool>(),
        [true, false, true],
      );
      // (the first is the harmless lock check)
      // Leaving without a change forgets the backup.
      expect(await rig.store.has(rig.device.mac), isTrue);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester, 600);
      expect(await rig.store.has(rig.device.mac), isFalse);
      rig.playback.pause();
    });

    testWidgets('backgrounding ends the test; coming back starts it again', (tester) async {
      final rig = await SetupRig.create(tester);
      await rig.pump(tester);
      await settle(tester, 800);
      await tapText(tester, 'It doesn\'t match');
      await tapText(tester, 'Next');
      await settle(tester, 600);
      expect(rig.device.rlmValue, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester, 500);
      expect(rig.sender.closed, isTrue);
      expect(rig.device.rlmValue, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester, 600);
      expect(rig.senders.length, 3, reason: 'Look, the test, the test again');
      expect(rig.sender.closed, isFalse);
      expect(rig.device.rlmValue, 0);
      // Closing leaves it clean.
      await tester.tap(find.byTooltip('Close'));
      await settle(tester, 600);
      expect(rig.device.rlmValue, 1);
      expect(rig.sender.closed, isTrue);
      rig.playback.pause();
    });

    testWidgets('disposing mid-test puts everything back', (tester) async {
      final rig = await SetupRig.create(tester);
      await rig.pump(tester);
      await settle(tester, 800);
      await tapText(tester, 'It doesn\'t match');
      await tapText(tester, 'Next');
      await settle(tester, 600);
      expect(rig.device.rlmValue, 0);
      await tester.pumpWidget(const SizedBox());
      await settle(tester, 300);
      expect(rig.device.rlmValue, 1);
      expect(rig.sender.closed, isTrue);
      rig.playback.pause();
    });
  });

  group('apply', () {
    Future<SetupRig> toReview(
      WidgetTester tester, {
      SetupStore? store,
      FakeSetupDevice? device,
      VoidCallback? onExit,
      Future<void> Function(Duration)? delay,
    }) async {
      final dev = device ?? FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false);
      final rig = await SetupRig.create(tester, device: dev, store: store, delay: delay);
      await rig.pump(tester, onExit: onExit);
      await settle(tester, 600);
      await tester.tap(find.bySemanticsLabel('16 by 16'));
      await settle(tester, 300);
      await tapText(tester, 'Next');
      await settle(tester, 500);
      await answerWiring(tester, rig, const PanelWiring(corner: StartCorner.bottomRight, vertical: true, zigzag: true), 16, 16);
      await tapText(tester, 'Looks right');
      return rig;
    }

    testWidgets('review, power limit, then the exact writes in order', (tester) async {
      final device = FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false);
      ((device.cfg['hw'] as Map)['led'] as Map)['maxpwr'] = 0;
      final spy = SpyStore(
        () => [for (final w in device.writes) if (w.$1 == 'POST /json/cfg' || w.$1 == 'POST /settings/2D') w],
      );
      final rig = await toReview(tester, store: spy, device: device);
      expect(find.text('Ready to set it up'), findsOneWidget);
      expect(find.text('Takes a few seconds. You can undo it.'), findsOneWidget);
      expect(find.text('16×16'), findsOneWidget);
      expect(find.text('Starts bottom right, columns, zig-zag'), findsOneWidget);
      expect(find.text('64'), findsOneWidget);
      expect(find.text('256'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_sharp), findsOneWidget);
      expect(find.text('No limit'), findsOneWidget);
      expect(find.text('Optional'), findsOneWidget);

      await tapText(tester, 'Power limit');
      expect(find.text('What powers it?'), findsOneWidget);
      expect(find.text('Pick the amps on its power supply.'), findsOneWidget);
      await tapText(tester, '2 A');
      expect(find.text('Brightness limit 1700 mA (now no limit)'), findsOneWidget);
      await tapText(tester, '5 A');
      expect(find.text('Brightness limit 4250 mA (now no limit)'), findsOneWidget);
      haptics.clear();
      await tapText(tester, 'Use this limit');
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      expect(find.text('4250 mA'), findsOneWidget);

      haptics.clear();
      rig.device.writes.clear();
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);

      // The exact configuration writes, in order.
      final entry = Map<String, dynamic>.from(((rig.device.cfg['hw'] as Map)['led']['ins'] as List).first as Map);
      expect(entry['len'], 256);
      expect(rig.configWrites.map((w) => w.$1).toList(), ['POST /json/cfg', 'POST /settings/2D', 'POST /json/cfg']);
      final ledWrite = rig.configWrites[0].$2 as Map;
      expect(((ledWrite['hw'] as Map)['led'] as Map)['ins'], [entry]);
      expect(rig.configWrites[1].$2, {
        'SOMP': '1', 'MPC': '1', 'P0B': '1', 'P0R': '1', 'P0V': '1', 'P0S': 'on',
        'P0X': '0', 'P0Y': '0', 'P0W': '16', 'P0H': '16',
      });
      expect(rig.configWrites[2].$2, {
        'hw': {'led': {'maxpwr': 4250}},
      });
      // The backup was saved before the first change: all that had happened
      // was the lock check, a write of the realtime-map flag with its own value.
      expect(spy.savedAt, hasLength(1));
      expect(spy.savedAt.single.map((w) => w.$2), [
        {'if': {'live': {'rlm': true}}},
      ]);
      final snap = (await rig.store.load(rig.device.mac))!;
      expect(snap.ledCount, 64);
      expect(snap.isMatrix, isFalse);
      expect(snap.currentLimitMa, 0);

      expect(rig.device.panel!['w'], 16);
      expect(rig.device.panel!['v'], true);
      expect(rig.device.limit, 4250);
      expect(rig.device.rlmValue, 1);
      expect(haptics, contains('HapticFeedbackType.lightImpact'));
      expect(haptics.last, 'HapticFeedbackType.mediumImpact');
      expect(find.text('Does it match?'), findsOneWidget);
      expect(find.text('Undo setup'), findsOneWidget);
      expect(tester.takeException(), isNull);
      rig.playback.pause();
    });

    testWidgets('a stricter current limit is kept', (tester) async {
      final rig = await toReview(tester);
      await tapText(tester, 'Power limit');
      await tapText(tester, '2 A');
      expect(find.text('Brightness limit 1000 mA (now 1000 mA)'), findsOneWidget);
      expect(find.text('Your current limit is lower, so Glyph keeps it.'), findsOneWidget);
      await tapText(tester, 'Leave as it is');
      expect(find.text('1000 mA'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('the applying screen lists what it is doing', (tester) async {
      final gate = Completer<void>();
      final rig = await toReview(tester, delay: (_) => gate.future);
      final seen = <String>[];
      rig.controller.addListener(() {
        if (rig.controller.step == SetupStep.applying) seen.add(rig.controller.applyPhase.name);
      });
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 600); // waiting for the LED count to settle
      expect(find.text('Setting up your device'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing, reason: 'no way out while it writes');
      expect(find.byTooltip('Close'), findsNothing);
      gate.complete();
      expect(find.text('Saving a backup'), findsOneWidget);
      expect(find.text('Setting the LEDs'), findsOneWidget);
      expect(find.text('Setting the size and wiring'), findsOneWidget);
      expect(find.text('Checking it worked'), findsOneWidget);
      await settle(tester, 1500);
      expect(seen, containsAll(['backup', 'leds', 'layout', 'verify']));
      rig.playback.pause();
    });

    testWidgets('a device that keeps its old layout: everything is rolled back', (tester) async {
      final rig = await toReview(tester);
      rig.device.ignoreLayout = true;
      rig.device.writes.clear();
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      expect(find.text('Couldn\'t finish setting it up'), findsOneWidget);
      expect(find.text('Glyph put everything back.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Done'), findsOneWidget);
      // The LED count was written, then put back; nothing else changed.
      final lens = [
        for (final w in rig.configWrites)
          if (w.$2 is Map && (w.$2 as Map)['hw'] != null) (((((w.$2 as Map)['hw'] as Map)['led'] as Map)['ins'] as List).first as Map)['len'],
      ];
      expect(lens, [256, 64]);
      expect(rig.device.length, 64);
      expect(rig.device.panel, isNull);
      expect(rig.controller.wrote, isFalse);
      expect(await rig.store.has(rig.device.mac), isFalse, reason: 'the backup is no longer needed');
      expect(haptics.contains('HapticFeedbackType.mediumImpact'), isFalse, reason: 'failure is quiet');
      // Try again works once the device behaves.
      rig.device.ignoreLayout = false;
      await tapText(tester, 'Try again', ms: 1500);
      expect(find.text('Does it match?'), findsOneWidget);
      expect(rig.device.panel!['w'], 16);
      rig.playback.pause();
    });

    testWidgets('apply brings back what was playing (WLED resets segment 0)', (tester) async {
      final dev = FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false, playingFx: 53, playingName: 'the-starry-night.gif');
      final rig = await toReview(tester, device: dev);
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      expect(find.text('Does it match?'), findsOneWidget);
      expect(dev.fx, 53);
      expect(dev.seg0['n'], 'the-starry-night.gif');
      expect(dev.seg0['start'], 0, reason: 'geometry is not written back');
      rig.playback.pause();
    });

    testWidgets('a preset that was playing is applied again after apply', (tester) async {
      final dev = FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false, playingFx: 53);
      dev.presets[7] = 53;
      dev.state['ps'] = 7;
      final rig = await toReview(tester, device: dev);
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      expect(dev.state['ps'], 7);
      expect(dev.fx, 53);
      rig.playback.pause();
    });

    testWidgets('a rolled back apply brings playback back too', (tester) async {
      final dev = FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false, playingFx: 53);
      final rig = await toReview(tester, device: dev);
      dev.ignoreLayout = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      expect(find.text('Glyph put everything back.'), findsOneWidget);
      expect(dev.fx, 53);
      rig.playback.pause();
    });

    testWidgets('Look: undo brings playback back', (tester) async {
      final dev = FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false, playingFx: 53);
      final rig = await toReview(tester, device: dev);
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      await tapText(tester, 'Undo setup', ms: 1500);
      expect(dev.panel, isNull);
      expect(dev.fx, 53);
      expect(await rig.store.has(dev.mac), isFalse);
      rig.playback.pause();
    });

    testWidgets('review shows the limit the device already has', (tester) async {
      final rig = await toReview(tester);
      expect(find.text('1000 mA'), findsOneWidget);
      await tapText(tester, 'Power limit');
      await tapText(tester, '2 A');
      await tapText(tester, 'Use this limit');
      expect(find.text('1000 mA'), findsOneWidget, reason: 'the stricter current limit stays');
      rig.playback.pause();
    });

    testWidgets('Look: it doesn\'t match goes back to the wiring test', (tester) async {
      final rig = await toReview(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      expect(find.text('Does it match?'), findsOneWidget);
      await tapText(tester, 'It doesn\'t match', ms: 700);
      expect(find.text('Which corner lit up?'), findsOneWidget);
      expect(find.text('Let\'s test the wiring again.'), findsOneWidget);
      expect(rig.device.rlmValue, 0, reason: 'raw LED order for the test');
      expect(rig.device.panel!['w'], 16, reason: 'what was set stays until it is replaced');
      rig.playback.pause();
    });

    testWidgets('Look: Undo setup puts the device back and starts again', (tester) async {
      final rig = await toReview(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      haptics.clear();
      await tapText(tester, 'Undo setup', ms: 1500);
      expect(rig.device.length, 64);
      expect(rig.device.panel, isNull);
      expect(find.text('Put back the previous setup.'), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
      expect(find.text('How big is your display?'), findsOneWidget);
      expect(await rig.store.has(rig.device.mac), isFalse);
      rig.playback.pause();
    });

    testWidgets('Close after a write asks to keep it; Keep leaves it', (tester) async {
      var exits = 0;
      final rig = await toReview(tester, onExit: () => exits++);
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester, 500);
      expect(find.text('Keep the new setup?'), findsOneWidget);
      expect(exits, 0);
      await tapText(tester, 'Keep it', ms: 700);
      expect(exits, 1);
      expect(rig.device.panel!['w'], 16);
      expect(await rig.store.has(rig.device.mac), isTrue, reason: 'Undo display setup stays available');
      expect(rig.sender.closed, isTrue);
      rig.playback.pause();
    });

    testWidgets('Close after a write: Undo it restores the device', (tester) async {
      var exits = 0;
      final rig = await toReview(tester, onExit: () => exits++);
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester, 500);
      await tapText(tester, 'Undo it', ms: 1200);
      expect(exits, 1);
      expect(rig.device.length, 64);
      expect(rig.device.panel, isNull);
      expect(await rig.store.has(rig.device.mac), isFalse);
      expect(rig.sender.closed, isTrue);
      rig.playback.pause();
    });

    testWidgets('Android back after a write asks too; dismissing the sheet stays', (tester) async {
      var exits = 0;
      final rig = await toReview(tester, onExit: () => exits++);
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      await tester.tap(find.byTooltip('Back')); // Look → Review
      await settle(tester, 700);
      expect(find.text('Ready to set it up'), findsOneWidget);
      expect(rig.sender.closed, isTrue, reason: 'leaving Look ends its picture');
      await tester.tap(find.byTooltip('Close'));
      await settle(tester, 500);
      expect(find.text('Keep the new setup?'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester, 500);
      expect(find.text('Keep the new setup?'), findsNothing);
      expect(exits, 0);
      expect(find.text('Ready to set it up'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('Close with nothing written leaves at once', (tester) async {
      var exits = 0;
      final rig = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false));
      await rig.pump(tester, onExit: () => exits++);
      await settle(tester, 600);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester, 600);
      expect(exits, 1);
      expect(find.text('Keep the new setup?'), findsNothing);
      rig.playback.pause();
    });
  });

  group('look and feel', () {
    for (final (name, build) in <(String, Future<SetupRig> Function(WidgetTester))>[
      (
        'connect',
        (t) async {
          final rig = await SetupRig.create(t, entry: SetupEntry.newDevice);
          await rig.pump(t, size: const Size(360, 640), textScale: 1.6);
          return rig;
        },
      ),
      (
        'size',
        (t) async {
          final rig = await SetupRig.create(t, device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false));
          await rig.pump(t, size: const Size(360, 640), textScale: 1.6);
          await settle(t, 600);
          rig.controller.setSize(17, 9, click: false);
          await settle(t, 300);
          return rig;
        },
      ),
      (
        'first wiring question',
        (t) async {
          final rig = await SetupRig.create(t, device: FakeSetupDevice(width: 32, height: 8, ledCount: 256, matrix: false));
          await rig.pump(t, size: const Size(360, 640), textScale: 1.6);
          await settle(t, 600);
          rig.controller.sizeNext();
          await settle(t, 600);
          return rig;
        },
      ),
      (
        'review',
        (t) async {
          final rig = await SetupRig.create(t, device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false));
          await rig.pump(t, size: const Size(360, 640), textScale: 1.6);
          await settle(t, 600);
          rig.controller
            ..draftWiring = const PanelWiring(corner: StartCorner.bottomRight, vertical: true, zigzag: true)
            ..looksRight();
          await settle(t, 600);
          return rig;
        },
      ),
    ]) {
      testWidgets('$name fits at 1.6x text on 360×640', (tester) async {
        final rig = await build(tester);
        expect(tester.takeException(), isNull);
        // The primary action stays reachable at the bottom.
        final primaries = find.byType(FilledButton);
        if (primaries.evaluate().isNotEmpty) {
          expect(tester.getBottomLeft(primaries.first).dy, lessThanOrEqualTo(640));
        }
        rig.playback.pause();
      });
    }

    testWidgets('every control is at least 48px and words stay plain', (tester) async {
      final rig = await SetupRig.create(tester, device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false));
      await rig.pump(tester);
      await settle(tester, 600);
      for (final b in tester.widgetList(find.byType(InkWell)).toList().asMap().keys) {
        final size = tester.getSize(find.byType(InkWell).at(b));
        if (size.height < 48) {
          // Diagram-free screens: tiles and rows only.
          fail('InkWell $b is ${size.height}px tall');
        }
      }
      for (final word in ['matrix', 'preset', 'segment', 'DDP', '—']) {
        expect(find.textContaining(word, findRichText: true), findsNothing, reason: word);
      }
      rig.playback.pause();
    });
  });
}
