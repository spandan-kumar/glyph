import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/games/catalog.dart';
import 'package:glyph/features/games/core/game.dart';
import 'package:glyph/features/games/core/game_generator.dart';
import 'package:glyph/features/games/game_page.dart';
import 'package:glyph/features/games/games_screen.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/make/ambient_host.dart';

void main() {
  late Catalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
  });

  Future<PlaybackController> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(360, 740) * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(AppScope(
      playback: playback,
      devices: DeviceStore(),
      catalog: catalog,
      creations: CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph')),
      child: AmbientHost(
        playback: playback,
        child: MaterialApp(theme: buildTheme(), home: home),
      ),
    ));
    // Previews tick forever, so pump fixed durations instead of settling.
    await tester.pump(const Duration(milliseconds: 300));
    return playback;
  }

  testWidgets('grid shows every game; Snake opens and takes input', (tester) async {
    final playback = await pump(tester, const GamesScreen());
    expect(find.text('Play'), findsOneWidget);
    for (final d in gameDefs.take(4)) {
      expect(find.text(d.name), findsOneWidget);
    }
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Snake'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GamePage), findsOneWidget);
    expect(playback.generator, isA<GameGenerator>());
    expect(playback.isPlaying, isTrue);

    final gen = playback.generator as GameGenerator;
    final game = gen.view!.game;
    await tester.tap(find.bySemanticsLabel('down'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.bySemanticsLabel('left').first, const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.time, greaterThan(0));

    // Pause, then resume from the panel.
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Paused'), findsOneWidget);
    expect(game.paused, isTrue);
    await tester.tap(find.text('Resume'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(game.paused, isFalse);

    // Force a game over and restart.
    game.endGame();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Game over'), findsOneWidget);
    await tester.tap(find.text('Play again'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(gen.view!.game, isNot(same(game)));
    expect(find.text('Game over'), findsNothing);

    await tester.pageBack();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(GamePage), findsNothing);
    expect(gen.view!.game.paused, isTrue, reason: 'leaving pauses the game');
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  for (final def in gameDefs) {
    testWidgets('${def.name} page builds and handles its controls', (tester) async {
      final playback = await pump(tester, GamePage(def: def));
      final gen = playback.generator as GameGenerator;
      final area = tester.getRect(find.byType(LayoutBuilder).last);
      switch (def.controls) {
        case Controls.dpad || Controls.blocks:
          for (final k in ['up', 'left', 'right', 'down']) {
            await tester.tap(find.bySemanticsLabel(k));
            await tester.pump(const Duration(milliseconds: 50));
          }
          if (def.controls == Controls.blocks) {
            await tester.tap(find.bySemanticsLabel('rotate'));
            await tester.tap(find.bySemanticsLabel('drop'));
          }
        case Controls.paddle:
          await tester.dragFrom(area.center, const Offset(-100, 0));
        case Controls.tap:
          await tester.tapAt(area.center);
        case Controls.steer:
          await tester.tap(find.bySemanticsLabel('left'));
          await tester.tap(find.bySemanticsLabel('right'));
        case Controls.shooter:
          await tester.tap(find.bySemanticsLabel('left'));
          await tester.tap(find.text('FIRE'));
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(gen.view!.game.time, greaterThan(0));
      expect(tester.takeException(), isNull);
      playback.pause();
    });
  }
}
