import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/features/editor/editor_screen.dart';
import 'package:glyph/features/text/text_studio_screen.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/make/creation_tile.dart';
import 'package:glyph/ui/make/make_screen.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ambient_host.dart';

void main() {
  late Catalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
  });

  Future<(PlaybackController, CreationsStore)> pumpMake(WidgetTester tester,
      {bool withCreation = false}) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    final dir = Directory.systemTemp.createTempSync('glyph_make');
    addTearDown(() => dir.deleteSync(recursive: true));
    final creations = CreationsStore(directory: () async => dir);
    if (withCreation) {
      final a = Frame(8, 8)..set(1, 1, 0xFF0000);
      final b = Frame(8, 8)..set(2, 2, 0x00FF00);
      await tester.runAsync(() => creations.save(
          title: 'Blinky', kind: 'drawing', clip: FrameClip.uniform([a, b], fps: 4), meta: const {'fps': 4}));
    }
    await tester.pumpWidget(AppScope(
      playback: playback,
      devices: DeviceStore(),
      catalog: catalog,
      creations: creations,
      child: AmbientHost(
        playback: playback,
        child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: MakeScreen())),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    return (playback, creations);
  }

  testWidgets('studio renders at phone size with verb tiles', (tester) async {
    final (playback, _) = await pumpMake(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Make'), findsOneWidget);
    for (final verb in ['Draw', 'Write', 'Clock', 'Timer', 'Bring a GIF', 'Music', 'Now Playing', 'Glance', 'Alerts', 'Play']) {
      expect(find.text(verb), findsOneWidget, reason: verb);
    }
    await tester.scrollUntilVisible(find.text('MADE BY YOU'), 200);
    expect(find.text('MADE BY YOU'), findsOneWidget);
    // Previews keep running without errors.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('tapping Draw opens the editor', (tester) async {
    final (playback, _) = await pumpMake(tester);
    await tester.tap(find.text('Draw'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(EditorScreen), findsOneWidget);
    // Straight to a blank canvas; the size/template picker is skipped.
    expect(find.text('New drawing'), findsNothing);
    expect(find.text('Untitled'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('the studio tools fit at 360 px with no overflow', (tester) async {
    final (playback, _) = await pumpMake(tester);
    // The tool's own panel (the nearest Material around its name).
    Rect tile(String verb) =>
        tester.getRect(find.ancestor(of: find.text(verb), matching: find.byType(Material)).first);
    // Every tool sits inside the 20 px gutters.
    for (final verb in ['Draw', 'Write', 'Clock', 'Timer', 'Bring a GIF', 'Music', 'Now Playing', 'Glance', 'Alerts', 'Play']) {
      final r = tile(verb);
      expect(r.left, greaterThanOrEqualTo(20 - 0.01), reason: verb);
      expect(r.right, lessThanOrEqualTo(340 + 0.01), reason: verb);
    }
    // The live tools share a row of their own, under Timer · GIF · Music.
    expect(tile('Now Playing').top, greaterThan(tile('Timer').bottom));
    expect(tile('Glance').top, closeTo(tile('Now Playing').top, 0.5));
    expect(tile('Alerts').top, closeTo(tile('Now Playing').top, 0.5));
    // Draw leads; the text tools follow it in order; Play closes the studio.
    final draw = tile('Draw');
    final write = tile('Write');
    final timer = tile('Timer');
    final play = tile('Play');
    expect(draw.width, greaterThan(write.width * 1.5));
    expect(write.left, greaterThan(draw.right));
    expect(timer.top, greaterThan(draw.bottom));
    expect(play.top, greaterThan(timer.bottom));
    expect(play.width, closeTo(320, 0.01));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('Timer opens the text studio in countdown mode, with no mode switch', (tester) async {
    final (playback, _) = await pumpMake(tester);
    await tester.tap(find.text('Timer'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    final studio = tester.widget<TextStudioScreen>(find.byType(TextStudioScreen));
    expect(studio.mode, 'countdown');
    expect(find.text('Timer'), findsWidgets);
    expect(find.text('COUNT DOWN TO'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    // Its own tool: no way across to Write or Clock from here.
    expect(find.descendant(of: find.byType(TextStudioScreen), matching: find.text('Clock')),
        findsNothing);
    expect(find.descendant(of: find.byType(TextStudioScreen), matching: find.text('Text')),
        findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('Write and Clock open their own modes', (tester) async {
    final (playback, _) = await pumpMake(tester);
    await tester.tap(find.text('Write'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<TextStudioScreen>(find.byType(TextStudioScreen)).mode, 'text');
    expect(find.byType(SegmentedButton<String>), findsNothing);
    final inStudio = find.byType(TextStudioScreen);
    expect(find.descendant(of: inStudio, matching: find.text('Clock')), findsNothing);
    expect(find.descendant(of: inStudio, matching: find.text('Timer')), findsNothing);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Clock'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<TextStudioScreen>(find.byType(TextStudioScreen)).mode, 'clock');
    expect(find.text('24-hour'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('Made by you shows a saved creation; tap plays, long-press has actions',
      (tester) async {
    final (playback, _) = await pumpMake(tester, withCreation: true);
    await tester.scrollUntilVisible(find.byType(CreationTile), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byType(CreationTile));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Blinky'), findsOneWidget);

    await tester.tap(find.byType(CreationTile));
    await tester.pump(const Duration(milliseconds: 200));
    expect(playback.generator?.name, 'Blinky');

    await tester.longPress(find.byType(CreationTile));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    for (final a in ['Play', 'Edit', 'Send to device', 'Share as GIF', 'Share Glyph file', 'Delete']) {
      expect(find.text(a), findsWidgets, reason: a);
    }
    expect(find.text('Keep on matrix'), findsNothing);
    expect(tester.takeException(), isNull);

    // Sending without a device explains how to connect.
    await tester.tap(find.text('Send to device'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Connect a device to send this to it.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
  });
}
