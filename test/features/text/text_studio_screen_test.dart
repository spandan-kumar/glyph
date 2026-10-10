import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/features/text/text_settings.dart';
import 'package:glyph/features/text/text_generators.dart';
import 'package:glyph/features/text/text_studio_screen.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/make/ambient_host.dart';
import '../../ui/make/tool_host.dart';
import '../device/fake_wled.dart';

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

  Future<(PlaybackController, CreationsStore)> pump(WidgetTester tester, Widget screen,
      {DeviceStore? devices}) async {
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
      devices: devices ?? DeviceStore(),
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

    await tapVisible(tester, find.text('Show on device'));
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

  testWidgets('saving long scrolling words retains a complete pass beyond 12 seconds', (tester) async {
    final (playback, creations) = await pump(tester, const TextStudioScreen());
    final text = List.filled(12, 'Complete message').join(' ');
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() async {
      await tapVisible(tester, find.text('Save'));
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 40 && creations.items.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(creations.items, hasLength(1));
    final c = creations.items.single;
    final settings = TextSettings.fromJson(c.meta);
    final loop = (ScrollingText(settings).create(c.clip.width, c.clip.height, 1) as TextInstance).loopSeconds!;
    expect(loop, greaterThan(12));
    expect(c.clip.totalMs, closeTo(loop * 1000, 125));
    playback.pause();
  });

  testWidgets('editing during an asynchronous save preserves its original content', (tester) async {
    final (playback, creations) = await pump(tester, const TextStudioScreen());
    const original = 'Save this complete message';
    await tester.enterText(find.byType(TextField), original);
    await tester.pump(const Duration(milliseconds: 200));
    await tapVisible(tester, find.text('Save'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    await tapVisible(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'New unsaved words');
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 40 && creations.items.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(creations.items.single.meta['text'], original);
    expect(find.byIcon(Icons.check_circle_sharp), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('Send with no device stays tappable and offers Connect', (tester) async {
    final (playback, _) = await pump(tester, const TextStudioScreen());
    await tapVisible(tester, find.text('Send to device'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Connect a device to send this to it.'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
    // Let the toast's timer finish before the scaffold goes away.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Clock opens with only clock controls', (tester) async {
    final (playback, _) = await pump(tester, const TextStudioScreen(mode: 'clock'));
    expect(find.text('Clock'), findsOneWidget);
    expect(find.text('24-hour'), findsOneWidget);
    expect(find.text('Type your message'), findsNothing);
    expect(find.text('COUNT DOWN TO'), findsNothing);
    await tapVisible(tester, find.text('Analog face'));
    await tester.pump(const Duration(milliseconds: 200));
    await tapVisible(tester, find.text('Show on device'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(playback.generator?.id, '_clock');
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('Timer opens with only countdown controls', (tester) async {
    final (playback, _) = await pump(tester, const TextStudioScreen(mode: 'countdown'));
    expect(find.text('Timer'), findsOneWidget);
    expect(find.text('COUNT DOWN TO'), findsOneWidget);
    expect(find.text('24-hour'), findsNothing);
    expect(find.text('Type your message'), findsNothing);
    await tapVisible(tester, find.text('1 min'));
    await tester.pump(const Duration(milliseconds: 200));
    await tapVisible(tester, find.text('Show on device'));
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

  group('leaving Write', () {
    bool exitedLive(FakeWled fake) =>
        fake.posts.any((p) => p.$1 == '/json/state' && p.$2['live'] == false);

    testWidgets('stops the words it was playing', (tester) async {
      final (playback, _) =
          await pump(tester, ToolHost(tool: () => const TextStudioScreen()));
      await openTool(tester);
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump(const Duration(milliseconds: 200));
      await tapVisible(tester, find.text('Show on device'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(playback.generator?.id, '_text');
      expect(playback.isPlaying, isTrue);

      await leaveTool(tester);
      expect(find.byType(TextStudioScreen), findsNothing);
      expect(playback.generator, isNull);
      expect(playback.isPlaying, isFalse);
      expect(playback.isStreaming, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps words that were sent to the device', (tester) async {
      SharedPreferences.setMockInitialValues({
        'devices.v1': jsonEncode([const SavedDevice(host: '192.168.29.6', name: 'Matrix').toJson()]),
        'devices.selected': '192.168.29.6',
      });
      final fake = FakeWled();
      final devices = DeviceStore(clientFactory: fake.client);
      await devices.load();
      final (playback, _) = await pump(
          tester, ToolHost(tool: () => const TextStudioScreen()),
          devices: devices);
      await openTool(tester);
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump(const Duration(milliseconds: 200));
      await tapVisible(tester, find.text('Show on device'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(playback.generator?.id, '_text');

      await tapVisible(tester, find.text('Send to device'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.textContaining('Sent to your device'), findsWidgets);

      fake.posts.clear();
      await leaveTool(tester);
      expect(find.byType(TextStudioScreen), findsNothing);
      expect(playback.generator?.id, '_text', reason: 'the sent words stay');
      expect(exitedLive(fake), isFalse);
      expect(tester.takeException(), isNull);
      playback.pause();
    });

    testWidgets('without playing anything, what played before keeps playing', (tester) async {
      final (playback, _) =
          await pump(tester, ToolHost(tool: () => const TextStudioScreen()));
      final item = catalog.items.first;
      playback.playItem(item);
      await openTool(tester);
      await tester.enterText(find.byType(TextField), 'Not played');
      await tester.pump(const Duration(milliseconds: 300));
      await leaveTool(tester);
      expect(playback.item, same(item));
      expect(playback.isPlaying, isTrue);
      expect(tester.takeException(), isNull);
      playback.pause();
    });
  });
}
