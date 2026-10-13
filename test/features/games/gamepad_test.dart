import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/device/boot_intro.dart';
import 'package:glyph/features/games/catalog.dart';
import 'package:glyph/features/games/core/game.dart';
import 'package:glyph/features/games/core/game_generator.dart';
import 'package:glyph/features/games/game_page.dart';
import 'package:glyph/features/games/widgets/controls.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/design/tokens.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/ui/widgets/led_matrix_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/make/ambient_host.dart';
import '../device/fake_wled.dart';

class _StreamingPlayback extends PlaybackController {
  bool streaming = false;

  @override
  bool get isStreaming => streaming;

  void setStreaming(bool value) {
    streaming = value;
    notifyListeners();
  }
}

void main() {
  late Catalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(
      File('assets/catalog/starter.json').readAsStringSync(),
    );
  });

  Future<PlaybackController> pumpGame(
    WidgetTester tester,
    GameDef def, {
    PlaybackController? playback,
    Size? displaySize,
    DeviceStore? devices,
  }) async {
    tester.view.physicalSize = const Size(390, 844) * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final pb = playback ?? PlaybackController();
    if (displaySize != null) {
      pb.resize(displaySize.width.toInt(), displaySize.height.toInt());
    }
    addTearDown(pb.dispose);
    await tester.pumpWidget(
      AppScope(
        playback: pb,
        devices: devices ?? DeviceStore(),
        catalog: catalog,
        creations: CreationsStore(
          directory: () async => Directory.systemTemp.createTemp('glyph'),
        ),
        child: AmbientHost(
          playback: pb,
          child: MaterialApp(
            theme: buildTheme(),
            home: GamePage(def: def),
          ),
        ),
      ),
    );
    // Game previews tick forever; never settle them.
    await tester.pump(const Duration(milliseconds: 100));
    return pb;
  }

  Future<void> pumpPad(
    WidgetTester tester,
    Widget pad, {
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(child: SizedBox(width: 350, height: 500, child: pad)),
          ),
        ),
      ),
    );
  }

  testWidgets('a switched-off device gets a thumbnail and a Turn on strip', (tester) async {
    final wled = FakeWled();
    BootIntro.autoInstall = false;
    addTearDown(BootIntro.resetForTest);
    final devices = DeviceStore(clientFactory: wled.client);
    addTearDown(devices.dispose);
    await tester.runAsync(() async {
      await devices.addAndSelect('fake', 'Test device');
      wled.state['on'] = false;
      await devices.refreshState();
    });
    final pb = await pumpGame(tester, gameById('snake'), devices: devices);
    expect(devices.isOn, isFalse);
    expect(find.text('Your device is off'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Turn on'), findsOneWidget);
    expect(tester.getSize(find.byType(LedMatrixView)), const Size(56, 56));
    await tester.runAsync(() async {
      await tester.tap(find.text('Turn on'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(wled.state['on'], isTrue);
    pb.pause();
  });

  testWidgets('phone-only play has a 56px thumbnail and Connect strip', (
    tester,
  ) async {
    final pb = await pumpGame(tester, gameById('snake'));
    expect(pb.isStreaming, isFalse);
    expect(find.byType(LedMatrixView), findsOneWidget);
    expect(tester.getSize(find.byType(LedMatrixView)), const Size(56, 56));
    final preview = tester.widget<LedMatrixView>(find.byType(LedMatrixView));
    expect(preview.glow, isFalse);
    expect(preview.bezel, isTrue);
    expect(find.text('Playing on your phone only'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Connect'), findsOneWidget);
    expect(find.textContaining('Preview ·'), findsNothing);
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Connect a device in the Device tab.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    pb.pause();
  });

  testWidgets('streaming removes the thumbnail and phone-only strip live', (
    tester,
  ) async {
    final pb = _StreamingPlayback();
    await pumpGame(tester, gameById('snake'), playback: pb);
    pb.setStreaming(true);
    await tester.pump();
    expect(find.byType(LedMatrixView), findsNothing);
    expect(find.text('Playing on your phone only'), findsNothing);
    expect(find.text('Connect'), findsNothing);
    pb.setStreaming(false);
    await tester.pump();
    expect(find.byType(LedMatrixView), findsOneWidget);
    expect(find.text('Playing on your phone only'), findsOneWidget);
    expect(tester.takeException(), isNull);
    pb.pause();
  });

  const labels = {
    'snake': <String>[],
    'blocks': ['Move left', 'Move right', 'Rotate', 'Drop', 'Soft drop'],
    'breaker': ['Paddle'],
    'pong': ['Paddle'],
    'flap': ['Flap'],
    'racer': ['Steer left', 'Steer right'],
    'invaders': ['Move left', 'Move right', 'Fire'],
  };
  for (final def in gameDefs) {
    testWidgets('${def.name} has labelled keys of at least 56px at 390×844', (
      tester,
    ) async {
      final pb = await pumpGame(tester, def);
      for (final label in ['Pause game', ...labels[def.id]!]) {
        // The page title can share a game's name ("Flap"); look among keys.
        final key = find.byWidgetPredicate((w) => w is PadButton && w.semanticsLabel == label);
        expect(key.evaluate().isEmpty ? find.bySemanticsLabel(label) : key, findsOneWidget, reason: label);
      }
      final keys = find.byType(PadButton);
      expect(keys, findsWidgets);
      for (final element in keys.evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.width, greaterThanOrEqualTo(56));
        expect(size.height, greaterThanOrEqualTo(56));
      }
      expect(tester.takeException(), isNull);
      pb.pause();
    });
  }

  testWidgets('pause key and bottom Resume button toggle pause', (
    tester,
  ) async {
    final pb = await pumpGame(tester, gameById('snake'));
    final game = (pb.generator as GameGenerator).view!.game;
    await tester.tap(find.bySemanticsLabel('Pause game'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.paused, isTrue);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.bySemanticsLabel('Resume game'), findsOneWidget);
    expect(find.byType(SwipePad), findsNothing);
    final primary = tester.getRect(find.widgetWithText(FilledButton, 'Resume'));
    final secondary = tester.getRect(
      find.widgetWithText(TextButton, 'Restart'),
    );
    expect(primary.height, Lb.cta);
    expect(secondary.top - primary.bottom, 8);
    expect(secondary.bottom, closeTo(844 - 16 - 20 - 1, 0.01));
    await tester.tap(find.text('Resume'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.paused, isFalse);
    expect(find.byType(SwipePad), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Pause game'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Resume game'));
    await tester.pump();
    expect(game.paused, isFalse);
    expect(tester.takeException(), isNull);
    pb.pause();
  });

  testWidgets('HUD scales a large score without overflowing', (tester) async {
    final pb = await pumpGame(tester, gameById('snake'));
    final game = (pb.generator as GameGenerator).view!.game;
    game.score = 123456789012345;
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('123456789012345'), findsOneWidget);
    final pause = tester.getRect(find.bySemanticsLabel('Pause game'));
    expect(pause.right, 390 - Lb.gutter);
    expect(tester.takeException(), isNull);
    pb.pause();
  });

  testWidgets('game over disables the pause key', (tester) async {
    final pb = await pumpGame(tester, gameById('snake'));
    final game = (pb.generator as GameGenerator).view!.game;
    game.endGame();
    await tester.pump(const Duration(milliseconds: 100));
    final pause = find.bySemanticsLabel('Pause game');
    expect(
      tester
          .getSemantics(pause)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    final button = tester.widget<PadButton>(find.byType(PadButton));
    expect(button.enabled, isFalse);
    await tester.tap(pause);
    await tester.pump();
    expect(find.text('Game over'), findsOneWidget);
    expect(find.text('Paused'), findsNothing);
    expect(tester.takeException(), isNull);
    pb.pause();
  });

  testWidgets('wide Racer uses up and down keys with 56px icons', (
    tester,
  ) async {
    final pb = await pumpGame(
      tester,
      gameById('racer'),
      displaySize: const Size(32, 8),
    );
    expect(find.bySemanticsLabel('Steer up'), findsOneWidget);
    expect(find.bySemanticsLabel('Steer down'), findsOneWidget);
    expect(find.text('UP'), findsOneWidget);
    expect(find.text('DOWN'), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.arrow_upward_sharp)).size, 56);
    expect(tester.takeException(), isNull);
    pb.pause();
  });

  testWidgets('Snake side taps, continuous swipes and custom actions steer', (
    tester,
  ) async {
    final directions = <GameKey>[];
    await pumpPad(tester, SwipePad(onDirection: directions.add));
    final pad = tester.getRect(find.byType(SwipePad));
    await tester.tapAt(Offset(pad.left + 20, pad.center.dy));
    expect(directions, [GameKey.left]);
    final gesture = await tester.startGesture(pad.center);
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.up();
    expect(directions, [GameKey.left, GameKey.right, GameKey.right]);
    final node = tester.getSemantics(find.bySemanticsLabel('Snake controls'));
    final actions = node.getSemanticsData().customSemanticsActionIds!;
    expect(
      actions.map((id) => CustomSemanticsAction.getAction(id)!.label),
      unorderedEquals(['Move up', 'Move down', 'Move left', 'Move right']),
    );
    for (final id in actions) {
      node.owner!.performAction(node.id, SemanticsAction.customAction, id);
    }
    expect(directions.skip(3), containsAll(GameKey.values.take(4)));
    await tester.pump(Lb.fast);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Snake tap triangles scale to the surface and track each pointer',
    (tester) async {
      final directions = <GameKey>[];
      await pumpPad(tester, SwipePad(onDirection: directions.add));
      final pad = tester.getRect(find.byType(SwipePad));
      // Pixel distance is larger vertically, but normalised distance is larger horizontally.
      await tester.tapAt(pad.center + const Offset(140, 170));
      expect(directions, [GameKey.right]);
      final left = await tester.startGesture(
        Offset(pad.left + 20, pad.center.dy),
        pointer: 1,
      );
      final up = await tester.startGesture(pad.center, pointer: 2);
      await up.moveBy(const Offset(0, -30));
      await left.up();
      await up.up();
      expect(directions, [GameKey.right, GameKey.up, GameKey.left]);
      final jitter = await tester.startGesture(pad.center);
      await jitter.moveBy(const Offset(10, 0));
      await jitter.moveBy(const Offset(-10, 0));
      await jitter.up();
      expect(
        directions,
        hasLength(3),
        reason: 'total travel of 20px is not a tap',
      );
      final cancelled = await tester.startGesture(pad.center);
      await cancelled.cancel();
      expect(directions, hasLength(3));
      await tester.pump(Lb.fast);
    },
  );

  testWidgets(
    'Snake direction colour holds for 180ms even with reduced motion',
    (tester) async {
      await pumpPad(tester, SwipePad(onDirection: (_) {}), reduceMotion: true);
      final pad = tester.getRect(find.byType(SwipePad));
      await tester.tapAt(Offset(pad.left + 20, pad.center.dy));
      await tester.pump();
      Color? colour() => tester
          .widget<Icon>(find.byIcon(Icons.keyboard_arrow_left_sharp))
          .color;
      expect(colour(), Lb.phosphor);
      await tester.pump(const Duration(milliseconds: 179));
      expect(colour(), Lb.phosphor);
      await tester.pump(const Duration(milliseconds: 1));
      expect(colour(), Lb.text3);
    },
  );

  testWidgets(
    'PadButton supports multi-touch, accessible taps and disabled input',
    (tester) async {
      var downs = 0, ups = 0;
      Widget button(bool enabled) => PadButton(
        width: 40,
        height: 40,
        enabled: enabled,
        semanticsLabel: 'Move left',
        onDown: () => downs++,
        onUp: () => ups++,
        caption: 'Left',
        child: const Icon(Icons.keyboard_arrow_left_sharp),
      );
      await pumpPad(tester, Center(child: button(true)));
      final key = find.byType(PadButton);
      expect(tester.getSize(key), const Size(56, 56));
      final first = await tester.startGesture(
        tester.getCenter(key),
        pointer: 1,
      );
      final second = await tester.startGesture(
        tester.getCenter(key),
        pointer: 2,
      );
      expect(downs, 2);
      await first.up();
      expect(ups, 0);
      await second.up();
      expect(ups, 1);
      final node = tester.getSemantics(find.bySemanticsLabel('Move left'));
      expect(node.getSemanticsData().label, 'Move left');
      node.owner!.performAction(node.id, SemanticsAction.tap);
      expect(downs, 3);
      expect(ups, 2);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: Center(child: button(false))),
        ),
      );
      await tester.tap(find.byType(PadButton));
      expect(downs, 3);
      expect(ups, 2);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Move left'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 60));
    },
  );

  for (final vertical in [false, true]) {
    testWidgets(
      'Paddle maps the ${vertical ? 'vertical' : 'horizontal'} track and semantics',
      (tester) async {
        final positions = <double>[];
        var launches = 0;
        await pumpPad(
          tester,
          DragPad(
            vertical: vertical,
            onPosition: positions.add,
            onDown: () => launches++,
            label: 'Drag to move',
          ),
        );
        final paddle = find.bySemanticsLabel('Paddle');
        expect(tester.getSemantics(paddle).getSemanticsData().value, '50%');
        final node = tester.getSemantics(paddle);
        node.owner!.performAction(node.id, SemanticsAction.increase);
        expect(positions.last, closeTo(0.6, 0.001));
        node.owner!.performAction(node.id, SemanticsAction.decrease);
        expect(positions.last, closeTo(0.5, 0.001));
        final pad = tester.getRect(find.byType(DragPad));
        final start = vertical
            ? Offset(pad.center.dx, pad.top + 28)
            : Offset(pad.left + 28, pad.center.dy);
        final end = vertical
            ? Offset(pad.center.dx, pad.bottom - 28)
            : Offset(pad.right - 28, pad.center.dy);
        final gesture = await tester.startGesture(start);
        expect(positions.last, closeTo(0, 0.001));
        expect(launches, 1);
        await gesture.moveTo(end);
        expect(positions.last, closeTo(1, 0.001));
        await gesture.up();
        await tester.pump();
        expect(tester.getSemantics(paddle).getSemanticsData().value, '100%');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
