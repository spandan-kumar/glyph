import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/device/setup/setup_controller.dart';
import 'package:glyph/wled/panel_grid.dart';
import 'package:glyph/wled/panel_setup.dart';

import '../../features/device/setup/fake_setup_device.dart';
import '../../features/device/setup/setup_rig.dart';

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

/// The label of a panel on the order questions.
String where(int cx, int cy) => 'Panel in row ${cy + 1}, column ${cx + 1}';

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

  /// Plays the person on the panel order questions: reads which panel the
  /// device lit from the buffers it was sent (physical LED order, panels
  /// chained as [truth]) and taps it.
  Future<void> answerOrder(WidgetTester tester, SetupRig rig, PanelGrid truth) async {
    final pl = truth.panelLeds;
    List<int> lit() => rig.sender.lit;
    int panelOf(List<int> l) => l.first ~/ pl;
    final lights = [for (var i = 0; i < 4 && i < pl; i++) i];

    // Q1: the first four LEDs of the first panel.
    expect(find.text('Which panel lit up?'), findsOneWidget);
    expect(lit(), lights);
    final (x0, y0) = truth.cellOf(panelOf(lit()));
    await tapLabel(tester, where(x0, y0));

    // Q2: the first four LEDs of the next panel, unless there is only one way.
    if (truth.cols > 1 && truth.rows > 1) {
      expect(find.text('Which panel is next?'), findsOneWidget);
      expect(lit(), [for (final i in lights) pl + i]);
      final (x1, y1) = truth.cellOf(panelOf(lit()));
      await tapLabel(tester, where(x1, y1));
      expect(find.text('Which panel is next?'), findsNothing, reason: 'tapping the panel answers');
    }

    // Q3: the first panel of the second run.
    final across = !truth.chain.vertical;
    final runs = across ? truth.rows : truth.cols;
    if (runs > 1) {
      expect(find.text('Where did it jump to?'), findsOneWidget);
      final run = truth.firstRunPanels;
      expect(lit(), [for (final i in lights) run * pl + i]);
      final (jx, jy) = truth.cellOf(panelOf(lit()));
      final corner = truth.chain.corner;
      final far = across ? jx != x0 : jy != y0;
      final nearLabel = across
          ? (corner.isRight ? 'On the right' : 'On the left')
          : (corner.isBottom ? 'At the bottom' : 'At the top');
      final farLabel = across
          ? (corner.isRight ? 'On the left' : 'On the right')
          : (corner.isBottom ? 'At the top' : 'At the bottom');
      await tapLabel(tester, far ? farLabel : nearLabel);
    }
    expect(find.text('Here\'s the panel order'), findsOneWidget);
    expect(rig.controller.draftChain, normalizeChain(truth.chain, truth.cols, truth.rows));
    expect(find.text(describeChainOf(truth.chain, truth.cols, truth.rows)), findsOneWidget);
  }

  /// The three LED questions inside the first panel, as the existing wizard.
  Future<void> answerWiring(
    WidgetTester tester,
    SetupRig rig,
    PanelWiring truth,
    int w,
    int h, {
    String result = 'Here\'s how the first panel is wired',
  }) async {
    expect(find.text('Which corner lit up?'), findsOneWidget);
    expect(rig.sender.lit, [0]);
    final (cx, cy) = truth.positionOf(0, w, h);
    final corner = StartCorner.of(bottom: cy == h - 1, right: cx == w - 1);
    await tapLabel(tester, '${_cap(corner.label)} corner');
    expect(find.text('Which way is it moving?'), findsOneWidget);
    final (x0, y0) = truth.positionOf(0, w, h);
    final (x1, y1) = truth.positionOf(1, w, h);
    final alongWidth = y1 == y0 && x1 != x0;
    await tapLabel(tester, alongWidth ? 'Across' : (corner.isBottom ? 'Up' : 'Down'));
    expect(find.text('Where did the light jump to?'), findsOneWidget);
    final run = alongWidth ? w : h;
    final (jx, jy) = truth.positionOf(run, w, h);
    final far = alongWidth ? jx != x0 : jy != y0;
    final nearLabel = alongWidth
        ? (corner.isRight ? 'On the right' : 'On the left')
        : (corner.isBottom ? 'At the bottom' : 'At the top');
    final farLabel = alongWidth
        ? (corner.isRight ? 'On the left' : 'On the right')
        : (corner.isBottom ? 'At the top' : 'At the bottom');
    await tapLabel(tester, far ? farLabel : nearLabel);
    expect(find.text(result), findsOneWidget);
  }

  /// Marks every panel whose first light isn't where the first panel's is.
  Future<void> answerOrientation(WidgetTester tester, SetupRig rig, PanelGrid truth) async {
    expect(find.text('Are any panels upside down?'), findsOneWidget);
    final pl = truth.panelLeds;
    expect(rig.sender.lit, [for (var k = 0; k < truth.panelCount; k++) k * pl]);
    final (w, h) = (truth.panelW, truth.panelH);
    StartCorner firstCorner(int k) {
      final (x, y) = truth.wiring[k].positionOf(0, w, h);
      return StartCorner.of(bottom: y == h - 1, right: x == w - 1);
    }

    for (var k = 1; k < truth.panelCount; k++) {
      if (firstCorner(k) != firstCorner(0)) await tapLabel(tester, 'Panel ${k + 1}');
    }
  }

  const tall = Size(360, 1100);

  Future<SetupRig> startGrid(WidgetTester tester, PanelGrid truth, {int? leds, FakeSetupDevice? device}) async {
    final rig = await SetupRig.create(
      tester,
      device: device ?? FakeSetupDevice(width: 8, height: 8, ledCount: leds ?? truth.ledCount, matrix: false),
    );
    await rig.pump(tester, onePanel: false, size: tall);
    await settle(tester, 600);
    if (device == null) {
      expect(find.text('Is your display one panel or several?'), findsOneWidget);
      await tapText(tester, 'Several panels');
    }
    if (device != null) {
      // Already set up: Look first.
      await tapText(tester, 'It doesn\'t match');
    }
    expect(find.text('How are the panels laid out?'), findsOneWidget);
    return rig;
  }

  /// Sets the size on the grid screen and goes on to the order questions.
  Future<void> layOut(WidgetTester tester, SetupRig rig, PanelGrid truth) async {
    final c = rig.controller;
    c.setSize(truth.panelW, truth.panelH, click: false);
    c.setGrid(truth.cols, truth.rows, click: false);
    await settle(tester, 300);
    await tapText(tester, 'Next', ms: 900);
  }

  PanelGrid grid(
    int cols,
    int rows,
    PanelWiring chain,
    PanelWiring base, {
    Set<int> turned = const {},
    int w = 8,
    int h = 8,
  }) => PanelGrid(
    cols: cols,
    rows: rows,
    panelW: w,
    panelH: h,
    chain: normalizeChain(chain, cols, rows),
    wiring: [for (var k = 0; k < cols * rows; k++) turned.contains(k) ? base.turnedUpsideDown : base],
  );

  final journeys = <(String, PanelGrid)>[
    ('2x1 horizontal, straight', grid(2, 1, const PanelWiring(), const PanelWiring())),
    (
      '2x2 snake with alternating upside-down panels',
      grid(
        2,
        2,
        const PanelWiring(zigzag: true),
        const PanelWiring(corner: StartCorner.bottomLeft, zigzag: true),
        turned: {1, 3},
      ),
    ),
    ('1x3 vertical chain', grid(1, 3, const PanelWiring(vertical: true), const PanelWiring(zigzag: true))),
    (
      '4x2 of 8x8 starting bottom right',
      grid(
        4,
        2,
        const PanelWiring(corner: StartCorner.bottomRight, zigzag: true),
        const PanelWiring(corner: StartCorner.topRight, vertical: true, zigzag: true),
        turned: {2, 3, 6},
      ),
    ),
    (
      '2x3 vertical straight chain, 16x8 panels',
      grid(
        2,
        3,
        const PanelWiring(corner: StartCorner.topRight, vertical: true),
        const PanelWiring(),
        turned: {5},
        w: 16,
        h: 8,
      ),
    ),
  ];

  for (final (name, truth) in journeys) {
    testWidgets('journey: $name is found, reviewed, applied and verified', (tester) async {
      final rig = await startGrid(tester, truth);
      final c = rig.controller;
      await layOut(tester, rig, truth);
      expect(rig.sender.sent, isNotEmpty);

      await answerOrder(tester, rig, truth);
      await tapText(tester, 'Looks right');
      await answerWiring(tester, rig, truth.wiring[0], truth.panelW, truth.panelH);
      await tapText(tester, 'Looks right');
      await answerOrientation(tester, rig, truth);
      haptics.clear();
      await tapText(tester, 'Done');
      expect(haptics, contains('HapticFeedbackType.lightImpact'));
      expect(rig.device.rlmValue, 1, reason: 'the map is back on after the tests');
      expect(rig.sender.closed, isTrue);

      expect(find.text('Ready to set it up'), findsOneWidget);
      expect(find.text(truth.describeSize()), findsOneWidget);
      expect(c.draftGrid, truth, reason: 'the wizard drew the grid the device is wired as');
      if (truth.panelCount > 1) {
        expect(find.text('Panel order'), findsOneWidget);
        expect(find.text(truth.describeChain()), findsOneWidget);
        expect(find.textContaining(truth.sameWiring ? 'Same in every panel' : 'Varies by panel'), findsOneWidget);
        expect(
          find.textContaining('At full white this could draw up to ${formatAmps(fullWhiteAmps(truth.ledCount))} A'),
          findsOneWidget,
        );
        expect(find.text('Power each panel from the supply directly, not through the next panel.'), findsOneWidget);
      }

      rig.device.writes.clear();
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);

      // The whole layout is written in one form, and read back.
      final forms = [
        for (final w in rig.device.writes)
          if (w.$1 == 'POST /settings/2D') w.$2 as Map,
      ];
      expect(forms, hasLength(1));
      expect(forms.single['MPC'], '${truth.panelCount}');
      expect(forms.single, panelForm(DisplaySetup.grid(truth)));
      expect(rig.device.panels, truth.panels());
      expect(rig.device.rlmValue, 1);
      expect(rig.device.length, truth.ledCount);
      expect(find.text('Does it match?'), findsOneWidget);
      expect(await rig.store.has(rig.device.mac), isTrue);

      // And the display really is the one the answers described.
      final read = (await rig.device.client('x').setupState());
      expect(read.grid, truth);
      expect(read.support, SetupSupport.supported);
      expect(tester.takeException(), isNull);
      rig.playback.pause();
    });
  }

  group('the first questions', () {
    testWidgets('one panel goes to the usual size screen, several to the grid', (tester) async {
      final rig = await SetupRig.create(
        tester,
        device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false),
      );
      await rig.pump(tester, onePanel: false, size: tall);
      await settle(tester, 600);
      expect(find.text('Is your display one panel or several?'), findsOneWidget);
      expect(find.text('Several means separate panels joined into one big display.'), findsOneWidget);
      haptics.clear();
      await tapText(tester, 'One panel');
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(find.text('How big is your display?'), findsOneWidget);
      // Back returns to the question; the link switches to the grid.
      await tester.tap(find.byTooltip('Back'));
      await settle(tester, 600);
      expect(find.text('Is your display one panel or several?'), findsOneWidget);
      await tapText(tester, 'Several panels');
      expect(find.text('How are the panels laid out?'), findsOneWidget);
      await tapText(tester, 'It\'s one panel');
      expect(find.text('How big is your display?'), findsOneWidget);
      await tapText(tester, 'It\'s made of several panels');
      expect(find.text('How are the panels laid out?'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('the grid guesses from the LEDs the device has, and counts', (tester) async {
      final rig = await SetupRig.create(
        tester,
        device: FakeSetupDevice(width: 8, height: 8, ledCount: 2048, matrix: false),
      );
      await rig.pump(tester, onePanel: false, size: tall);
      await settle(tester, 600);
      await tapText(tester, 'Several panels');
      final c = rig.controller;
      expect((c.draftCols, c.draftRows, c.draftWidth, c.draftHeight), (4, 2, 16, 16));
      expect(find.text('4 × 2 panels of 16×16 is 2048 LEDs, 64×32 in all.'), findsOneWidget);
      expect(find.text('Your device is set for 2048 LEDs.'), findsOneWidget);
      expect(find.textContaining('Glyph will set it to'), findsNothing);
      expect(
        find.bySemanticsLabel('Display diagram, 4 by 2 panels of 16 by 16 lights, 64 by 32 in all'),
        findsOneWidget,
      );

      // The steppers.
      haptics.clear();
      await tester.tap(find.bySemanticsLabel('more panels across'));
      await settle(tester, 200);
      expect(c.draftCols, 5);
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      await tester.tap(find.bySemanticsLabel('fewer panels down'));
      await settle(tester, 200);
      expect(c.draftRows, 1);
      expect(find.text('Glyph will set it to 1280 LEDs.'), findsOneWidget);

      // Presets and Other.
      await tester.tap(find.bySemanticsLabel('32 by 8'));
      await settle(tester, 200);
      expect((c.draftWidth, c.draftHeight), (32, 8));
      await tapText(tester, 'Other size');
      expect(find.text('LIGHTS ACROSS'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('more lights across'));
      await settle(tester, 200);
      expect(c.draftWidth, 33);
      rig.playback.pause();
    });

    testWidgets('layouts WLED can not drive are blocked in plain words', (tester) async {
      final rig = await SetupRig.create(
        tester,
        device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false),
      );
      await rig.pump(tester, onePanel: false, size: tall);
      await settle(tester, 600);
      await tapText(tester, 'Several panels');
      final c = rig.controller;
      c.setSize(16, 16, click: false);
      c.setGrid(4, 5, click: false); // 20 panels: WLED builds at most 18
      await settle(tester, 300);
      expect(find.text('That\'s more than this device can drive.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNull);
      c.setGrid(3, 6, click: false);
      await settle(tester, 300);
      expect(find.text('That\'s more than this device can drive.'), findsNothing);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNotNull);
      c.setGrid(1, 1, click: false);
      await settle(tester, 300);
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await settle(tester, 300);
      expect(find.textContaining('Add at least two panels'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNull);
      rig.playback.pause();
    });
  });

  group('the panel order test', () {
    final truth = grid(2, 2, const PanelWiring(zigzag: true), const PanelWiring());

    testWidgets('only the corner panels can start the chain, and the diagram does not give the answer', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await startGrid(tester, truth);
      await layOut(tester, rig, truth);
      expect(find.text('Which panel lit up?'), findsOneWidget);
      // A 3x3 grid has a middle panel that is not a start.
      rig.controller.setGrid(3, 3, click: false);
      await settle(tester, 300);
      rig.controller.pickFirstPanel((1, 1));
      expect(rig.controller.step, SetupStep.orderQ1, reason: 'the middle panel is not a start');
      for (final cell in [(0, 0), (2, 0), (0, 2), (2, 2)]) {
        expect(find.bySemanticsLabel(where(cell.$1, cell.$2)), findsOneWidget);
      }
      expect(find.bySemanticsLabel(where(1, 1)), findsNothing);
      final box = tester.getSize(find.bySemanticsLabel(where(0, 0)));
      expect(box.width, greaterThanOrEqualTo(48));
      expect(box.height, greaterThanOrEqualTo(48));
      handle.dispose();
      rig.playback.pause();
    });

    testWidgets('Q2 can be answered with Across or Down; Back and Test again work', (tester) async {
      final rig = await startGrid(tester, truth);
      await layOut(tester, rig, truth);
      haptics.clear();
      await tapLabel(tester, where(0, 0));
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(find.text('Which panel is next?'), findsOneWidget);
      expect(rig.sender.lit, [8 * 8, 8 * 8 + 1, 8 * 8 + 2, 8 * 8 + 3]);
      await tapText(tester, 'Across');
      expect(find.text('Where did it jump to?'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester, 500);
      expect(find.text('Which panel is next?'), findsOneWidget);
      await tapText(tester, 'Down');
      await tapText(tester, 'At the top'); // straight on, down the columns
      expect(find.text('Here\'s the panel order'), findsOneWidget);
      expect(rig.controller.draftChain, const PanelWiring(vertical: true));
      await tapText(tester, 'Test again');
      expect(find.text('Which panel lit up?'), findsOneWidget);
      expect(rig.controller.draftChain, isNull);
      rig.playback.pause();
    });

    testWidgets('the manual picker starts from the common layout and edits the chain', (tester) async {
      final rig = await startGrid(tester, truth);
      await layOut(tester, rig, truth);
      await answerOrder(tester, rig, truth);
      await tapText(tester, 'Choose it myself');
      expect(find.text('How are the panels chained?'), findsOneWidget);
      final list = find.byType(Scrollable).first;
      Future<void> reveal(Finder f) async {
        await tester.scrollUntilVisible(f, 120, scrollable: list);
        await settle(tester, 100);
      }

      await reveal(find.text('Bottom right'));
      await tapText(tester, 'Bottom right');
      await reveal(find.text('Down'));
      await tapText(tester, 'Down');
      await reveal(find.text('Snake'));
      await tester.tap(find.text('Snake'));
      await settle(tester, 300);
      expect(rig.controller.draftChain, const PanelWiring(corner: StartCorner.bottomRight, vertical: true));
      await tester.scrollUntilVisible(find.text('Use this'), -120, scrollable: list);
      await tapText(tester, 'Use this');
      expect(find.text('Which corner lit up?'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('manual order with no tests starts at top left, across, snake', (tester) async {
      final rig = await startGrid(tester, truth);
      await layOut(tester, rig, truth);
      await answerOrder(
        tester,
        rig,
        grid(2, 2, const PanelWiring(corner: StartCorner.bottomRight), const PanelWiring()),
      );
      rig.controller.draftChain = null;
      rig.controller.chooseManualOrder();
      await settle(tester, 500);
      expect(rig.controller.draftChain, const PanelWiring(zigzag: true));
      rig.playback.pause();
    });

    testWidgets('fewer LEDs than panels: the lights can not show yet, and can be added', (tester) async {
      final rig = await startGrid(tester, truth, leds: 64);
      await layOut(tester, rig, truth);
      await tapLabel(tester, where(0, 0));
      expect(rig.controller.testNeedsMoreLeds, isTrue);
      expect(find.textContaining('so these lights can\'t show yet'), findsOneWidget);
      await tapText(tester, 'Set it to 256 LEDs now', ms: 800);
      expect(rig.device.length, 256);
      expect(rig.controller.testNeedsMoreLeds, isFalse);
      expect(rig.sender.lit, [8 * 8, 8 * 8 + 1, 8 * 8 + 2, 8 * 8 + 3]);
      rig.playback.pause();
    });

    testWidgets('leaving a test puts the realtime map back from every new step', (tester) async {
      final rig = await startGrid(tester, truth);
      await layOut(tester, rig, truth);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester, 600);
      expect(rig.device.rlmValue, 1);
      expect(rig.sender.closed, isTrue);
      rig.playback.pause();
    });

    testWidgets('going to the background ends the test and resuming restarts it', (tester) async {
      final rig = await startGrid(tester, truth);
      await layOut(tester, rig, truth);
      expect(rig.controller.testRunning, isTrue);
      rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await settle(tester, 600);
      expect(rig.controller.testRunning, isFalse);
      expect(rig.device.rlmValue, 1);
      rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle(tester, 800);
      expect(rig.controller.testRunning, isTrue);
      expect(rig.sender.lit, [0, 1, 2, 3]);
      await rig.controller.cleanUp();
      rig.playback.pause();
    });
  });

  group('upside-down panels', () {
    final truth = grid(2, 2, const PanelWiring(zigzag: true), const PanelWiring(), turned: {2});

    Future<SetupRig> toOrientation(WidgetTester tester) async {
      final rig = await startGrid(tester, truth);
      await layOut(tester, rig, truth);
      await answerOrder(tester, rig, truth);
      await tapText(tester, 'Looks right');
      await answerWiring(tester, rig, truth.wiring[0], 8, 8);
      await tapText(tester, 'Looks right');
      return rig;
    }

    testWidgets('taps toggle a mark; the first panel is the reference; Done goes on', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await toOrientation(tester);
      final c = rig.controller;
      expect(find.text('Are any panels upside down?'), findsOneWidget);
      expect(
        find.text('Each panel\'s first light should sit in the same corner. Tap any panel where it doesn\'t.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Panel 1'), findsNothing, reason: 'the first panel defines the wiring');
      expect(c.flippedCells, isEmpty, reason: 'default: none marked');
      haptics.clear();
      await tapLabel(tester, 'Panel 3');
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(c.flippedCells, {truth.cellOf(2)});
      expect(find.bySemanticsLabel('Panel 3, marked upside down'), findsOneWidget);
      await tapLabel(tester, 'Panel 3, marked upside down');
      expect(c.flippedCells, isEmpty);
      await tapLabel(tester, 'Panel 3');
      expect(c.draftGrid, truth);
      expect(find.text('Panels turned sideways?'), findsOneWidget);
      await tapText(tester, 'Panels turned sideways?');
      expect(find.textContaining('quarter turn isn\'t supported yet'), findsOneWidget);
      await tapText(tester, 'OK');
      await tapText(tester, 'Done');
      expect(find.text('Ready to set it up'), findsOneWidget);
      expect(find.text('Varies by panel.', findRichText: true), findsNothing);
      expect(find.textContaining('Varies by panel'), findsOneWidget);
      // Back from Review returns here.
      await tester.tap(find.byTooltip('Back'));
      await settle(tester, 600);
      expect(find.text('Are any panels upside down?'), findsOneWidget);
      handle.dispose();
      rig.playback.pause();
    });

    testWidgets('the first panel is never marked', (tester) async {
      final rig = await toOrientation(tester);
      rig.controller.toggleFlipped(truth.cellOf(0));
      expect(rig.controller.flippedCells, isEmpty);
      rig.playback.pause();
    });
  });

  group('apply and undo', () {
    final truth = grid(2, 1, const PanelWiring(), const PanelWiring(corner: StartCorner.topRight), turned: {1});

    Future<SetupRig> toReview(WidgetTester tester, {FakeSetupDevice? device}) async {
      final rig = await startGrid(tester, truth, device: device);
      await layOut(tester, rig, truth);
      await answerOrder(tester, rig, truth);
      await tapText(tester, 'Looks right');
      await answerWiring(tester, rig, truth.wiring[0], 8, 8);
      await tapText(tester, 'Looks right');
      await answerOrientation(tester, rig, truth);
      await tapText(tester, 'Done');
      return rig;
    }

    testWidgets('a device that keeps its old layout is rolled back, panels and all', (tester) async {
      final device = FakeSetupDevice(
        width: 8,
        height: 8,
        ledCount: 128,
        panels: [
          for (final p in grid(2, 1, const PanelWiring(), const PanelWiring()).panels()) Map<String, dynamic>.from(p),
        ],
      );
      final rig = await toReview(tester, device: device);
      final before = [for (final p in device.panels) Map.of(p)];
      device.ignoreLayout = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      expect(find.text('Couldn\'t finish setting it up'), findsOneWidget);
      expect(device.panels, before);
      rig.playback.pause();
    });

    testWidgets('undo puts a previous multi-panel layout back, every panel', (tester) async {
      final before = grid(
        2,
        2,
        const PanelWiring(corner: StartCorner.bottomLeft, zigzag: true),
        const PanelWiring(vertical: true),
        turned: {3},
      );
      final device = FakeSetupDevice(
        width: 8,
        height: 8,
        ledCount: 256,
        panels: [for (final p in before.panels()) Map<String, dynamic>.from(p)],
      );
      final rig = await SetupRig.create(tester, device: device);
      await rig.pump(tester, onePanel: false, size: tall);
      await settle(tester, 800);
      // Already set up: straight to the Look step.
      expect(find.text('Does it match?'), findsOneWidget);
      await tapText(tester, 'It doesn\'t match');
      expect(
        find.text('How are the panels laid out?'),
        findsOneWidget,
        reason: 'a known grid starts on its own screen',
      );
      final c = rig.controller;
      expect((c.draftCols, c.draftRows, c.draftWidth, c.draftHeight), (2, 2, 8, 8));
      expect(c.draftChain, before.chain);
      expect(c.draftWiring, before.wiring[0]);
      expect(c.flippedCells, {before.cellOf(3)});
      expect(c.draftGrid, before, reason: 'what the device has is what is shown');

      // Re-set it up as one 16x16 panel, then undo.
      await tapText(tester, 'It\'s one panel');
      c.setSize(16, 16, click: false);
      c.sizeNext();
      await settle(tester, 600);
      await answerWiring(tester, rig, const PanelWiring(), 16, 16, result: 'Here\'s how it\'s wired');
      await tapText(tester, 'Looks right');
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      expect(device.panels, hasLength(1));
      expect(await c.undo(), isTrue);
      expect(device.panels, before.panels());
      expect(device.length, 256);
      expect(device.rlmValue, 1);
      rig.playback.pause();
    });

    testWidgets('a device that is already this grid goes straight to Look', (tester) async {
      final device = FakeSetupDevice(
        width: 8,
        height: 8,
        ledCount: 128,
        panels: [for (final p in truth.panels()) Map<String, dynamic>.from(p)],
      );
      final rig = await SetupRig.create(tester, device: device);
      await rig.pump(tester, onePanel: false, size: tall);
      await settle(tester, 800);
      expect(rig.controller.fastPath, isTrue);
      expect(find.text('Does it match?'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('Look: it does not match goes back to the panel test with a note', (tester) async {
      final rig = await toReview(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Set up device'));
      await settle(tester, 1500);
      await tapText(tester, 'It doesn\'t match');
      expect(find.text('Which panel lit up?'), findsOneWidget);
      expect(find.text('Let\'s test the panels again.'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('a layout over the limits can not be applied', (tester) async {
      final rig = await toReview(tester);
      rig.controller.setSize(128, 128, click: false);
      expect(rig.controller.sizeProblem, tooBigWords);
      rig.device.writes.clear();
      await rig.controller.apply();
      expect(rig.device.writes.where((w) => w.$1 == 'POST /settings/2D'), isEmpty);
      rig.playback.pause();
    });
  });

  group('review notes', () {
    testWidgets('a big display on one wire says how fast it updates; no power note for one panel', (tester) async {
      final rig = await SetupRig.create(
        tester,
        device: FakeSetupDevice(width: 8, height: 8, ledCount: 2048, matrix: false),
      );
      await rig.pump(tester, onePanel: false, size: tall);
      await settle(tester, 600);
      await tapText(tester, 'Several panels');
      final c = rig.controller;
      expect((c.draftCols, c.draftRows, c.draftWidth), (4, 2, 16));
      c.draftWiring = const PanelWiring();
      c.draftChain = const PanelWiring(zigzag: true);
      c.orderLooksRight();
      await settle(tester, 300);
      c.looksRight();
      await settle(tester, 300);
      c.orientationDone();
      await settle(tester, 600);
      expect(find.text('Ready to set it up'), findsOneWidget);
      expect(
        find.text('At full white this could draw up to 123 A. Typical animations use about a third.'),
        findsOneWidget,
      );
      expect(find.text('Big displays on one wire update more slowly (about 16 frames a second).'), findsOneWidget);
      expect(find.text('4 × 2 panels of 16×16 (64×32)'), findsOneWidget);
      expect(find.text('Power limit'), findsOneWidget);
      rig.playback.pause();
    });
  });
}
