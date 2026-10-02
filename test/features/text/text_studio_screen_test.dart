import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/features/text/text_settings.dart';
import 'package:glyph/features/text/text_studio_screen.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Catalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
  });

  Future<(PlaybackController, CreationsStore)> pump(WidgetTester tester, Widget screen) async {
    const size = Size(360, 740);
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    final dir = Directory.systemTemp.createTempSync('glyph_text');
    final creations = CreationsStore(directory: () async => dir);
    await tester.pumpWidget(AppScope(
      playback: playback,
      devices: DeviceStore(),
      catalog: catalog,
      creations: creations,
      child: MaterialApp(theme: buildTheme(), home: screen),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    return (playback, creations);
  }

  testWidgets('text studio: type, style, play and save', (tester) async {
    final (playback, creations) = await pump(tester, const TextStudioScreen());
    expect(find.text('Scrolling text'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Hello matrix');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Bold'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Rainbow'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('32×8'));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.scrollUntilVisible(find.text('Play on matrix'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Play on matrix'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(playback.generator?.id, '_text');

    await tester.runAsync(() async {
      await tester.tap(find.text('Save to My Creations'));
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(creations.items, hasLength(1));
    final c = creations.items.single;
    expect(c.kind, 'text');
    expect(c.meta['mode'], 'text');
    expect(c.meta['text'], 'Hello matrix');
    expect(c.clip.width, 32);
    expect(c.clip.height, 8);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('clock and countdown modes build', (tester) async {
    final (playback, _) = await pump(tester, const TextStudioScreen(mode: 'clock'));
    expect(find.text('24-hour'), findsOneWidget);
    await tester.tap(find.text('Analog face'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Timer'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Count down to'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('1 min'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('reopens a saved creation with its settings', (tester) async {
    final meta = {
      ...TextSettings(text: 'Reopened', font: 'tiny', durationSec: 60).toJson(),
      'mode': 'countdown',
    };
    final creation = Creation(
      id: 'abc',
      title: 'Countdown',
      kind: 'text',
      clip: FrameClip.uniform([Frame(16, 16)]),
      updatedAt: DateTime(2026),
      meta: meta,
    );
    final (playback, _) = await pump(tester, TextStudioScreen(initial: creation, mode: 'countdown'));
    expect(find.text('Countdown'), findsOneWidget);
    await tester.tap(find.text('Text'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(TextField, 'Reopened'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
  });
}
