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

import '../../ui/make/ambient_host.dart';

/// The studio is a long scroll; bring a control into view before tapping it.
Future<void> tapVisible(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    // Not built yet (below) or recycled (above).
    final list = find.byType(Scrollable).first;
    try {
      await tester.scrollUntilVisible(f, 200, scrollable: list, maxScrolls: 12);
    } on StateError {
      await tester.scrollUntilVisible(f, -200, scrollable: list, maxScrolls: 24);
    }
  }
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(f);
}

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
      child: AmbientHost(
        playback: playback,
        child: MaterialApp(theme: buildTheme(), home: screen),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    return (playback, creations);
  }

  testWidgets('text studio: type, style, play and save', (tester) async {
    final (playback, creations) = await pump(tester, const TextStudioScreen());
    expect(find.text('Write'), findsOneWidget);
    // Write is its own tool: no switch across to Clock or Timer.
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.text('Clock'), findsNothing);
    expect(find.text('Timer'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Hello device');
    await tester.pump(const Duration(milliseconds: 200));
    await tapVisible(tester, find.text('Bold'));
    await tester.pump(const Duration(milliseconds: 100));
    await tapVisible(tester, find.text('Rainbow'));
    await tester.pump(const Duration(milliseconds: 100));
    await tapVisible(tester, find.text('32×8'));
    await tester.pump(const Duration(milliseconds: 200));

    await tapVisible(tester, find.text('Play on device'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(playback.generator?.id, '_text');

    await tester.runAsync(() async {
      await tapVisible(tester, find.text('Save'));
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    // Real file IO: wait for it rather than guessing how long it takes.
    for (var i = 0; i < 40 && creations.items.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(creations.items, hasLength(1));
    final c = creations.items.single;
    expect(c.kind, 'text');
    expect(c.meta['mode'], 'text');
    expect(c.meta['text'], 'Hello device');
    expect(c.clip.width, 32);
    expect(c.clip.height, 8);
    // No device: sending is offered but can't be done yet.
    expect(find.text('Send to device'), findsOneWidget);
    expect(find.text('Keep on matrix'), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('Clock opens with only clock controls', (tester) async {
    final (playback, _) = await pump(tester, const TextStudioScreen(mode: 'clock'));
    expect(find.text('Clock'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.text('24-hour'), findsOneWidget);
    expect(find.text('Type your message'), findsNothing);
    expect(find.text('COUNT DOWN TO'), findsNothing);
    await tapVisible(tester, find.text('Analog face'));
    await tester.pump(const Duration(milliseconds: 200));
    await tapVisible(tester, find.text('Play on device'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(playback.generator?.id, '_clock');
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('Timer opens with only countdown controls', (tester) async {
    final (playback, _) = await pump(tester, const TextStudioScreen(mode: 'countdown'));
    expect(find.text('Timer'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.text('COUNT DOWN TO'), findsOneWidget);
    expect(find.text('24-hour'), findsNothing);
    expect(find.text('Type your message'), findsNothing);
    await tapVisible(tester, find.text('1 min'));
    await tester.pump(const Duration(milliseconds: 200));
    await tapVisible(tester, find.text('Play on device'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(playback.generator?.id, '_countdown');
    expect(playback.generator?.name, 'Timer');
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  Creation saved(String mode, {String text = 'Reopened'}) => Creation(
        id: 'abc-$mode',
        title: mode,
        kind: 'text',
        clip: FrameClip.uniform([Frame(16, 16)]),
        updatedAt: DateTime(2026),
        meta: {
          ...TextSettings(text: text, font: 'tiny', durationSec: 60, doneText: 'Lift off').toJson(),
          'mode': mode,
        },
      );

  testWidgets('reopens a saved timer in Timer, whatever mode was asked for', (tester) async {
    final (playback, _) = await pump(tester, TextStudioScreen(initial: saved('countdown')));
    expect(find.text('Timer'), findsOneWidget);
    expect(find.text('COUNT DOWN TO'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Lift off'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('reopens saved words in Write with their settings', (tester) async {
    final (playback, _) = await pump(tester, TextStudioScreen(initial: saved('text'), mode: 'clock'));
    expect(find.text('Write'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Reopened'), findsOneWidget);
    expect(find.text('24-hour'), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('reopens a saved clock in Clock', (tester) async {
    final (playback, _) = await pump(tester, TextStudioScreen(initial: saved('clock')));
    expect(find.text('Clock'), findsOneWidget);
    expect(find.text('24-hour'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
  });
}
