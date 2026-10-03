import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/features/editor/editor_screen.dart';
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
    for (final verb in ['Draw', 'Write', 'Clock', 'Bring a GIF', 'Music', 'Play']) {
      expect(find.text(verb), findsOneWidget, reason: verb);
    }
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
    for (final a in ['Play', 'Edit', 'Keep on matrix', 'Share as GIF', 'Share Glyph file', 'Delete']) {
      expect(find.text(a), findsWidgets, reason: a);
    }
    expect(find.text('Save to matrix'), findsNothing);
    expect(tester.takeException(), isNull);

    // Keeping without a matrix explains how to connect.
    await tester.tap(find.text('Keep on matrix'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Connect a matrix to keep this on it.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
  });
}
