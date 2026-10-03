import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/features/editor/color_picker.dart';
import 'package:glyph/features/editor/editor_canvas.dart';
import 'package:glyph/features/editor/editor_screen.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/actions.dart';
import 'package:glyph/ui/make/tool_session.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/make/ambient_host.dart';
import '../../ui/make/tool_host.dart';
import '../device/fake_wled.dart';

int lit(Frame f) => [
      for (var y = 0; y < f.height; y++)
        for (var x = 0; x < f.width; x++)
          if (f.get(x, y) != 0) 1,
    ].length;

void main() {
  late Catalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
  });

  Future<PlaybackController> pumpEditor(WidgetTester tester, Widget screen,
      {DeviceStore? devices}) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(AppScope(
      playback: playback,
      devices: devices ?? DeviceStore(),
      catalog: catalog,
      creations: CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph')),
      child: AmbientHost(
        playback: playback,
        child: MaterialApp(theme: buildTheme(), home: screen),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    return playback;
  }

  EditorScreenState state(WidgetTester tester) =>
      tester.state<EditorScreenState>(find.byType(EditorScreen));

  testWidgets('start blank, drag-paint, undo, preview', (tester) async {
    final playback = await pumpEditor(tester, const EditorScreen());
    expect(find.text('New drawing'), findsOneWidget);
    expect(find.text('Heart'), findsOneWidget);
    await tester.tap(find.text('Blank'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    final m = state(tester).model!;
    expect((m.width, m.height), (16, 16));
    // No matrix: the live mirror says so instead of pretending.
    expect(find.text('NO DEVICE CONNECTED'), findsOneWidget);
    expect(state(tester).mirroring, isFalse);
    final canvas = find.byType(EditorCanvas);
    final rect = tester.getRect(canvas);
    await tester.dragFrom(rect.center - const Offset(120, 0), const Offset(240, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(lit(m.frame), greaterThanOrEqualTo(10), reason: 'stroke has no gaps');
    expect(m.canUndo, isTrue);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(lit(m.frame), 0);

    await tester.tap(find.byTooltip('Add frame'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(m.frameCount, 2);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(milliseconds: 50));

    // A second finger turns the stroke into a pinch and leaves no mark.
    final f1 = await tester.startGesture(rect.center - const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await f1.moveBy(const Offset(10, 0));
    final f2 = await tester.startGesture(rect.center + const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 5; i++) {
      await f1.moveBy(const Offset(-15, 0));
      await f2.moveBy(const Offset(15, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await f1.up();
    await f2.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(lit(m.frame), 0);
    expect(find.byTooltip('Fit to screen'), findsOneWidget);
    await tester.tap(find.byTooltip('Fit to screen'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byTooltip('Fit to screen'), findsNothing);

    // Fill applies on tap.
    await tester.tap(find.byTooltip('Fill'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(rect.center);
    await tester.pump(const Duration(milliseconds: 50));
    expect(lit(m.frame), 256);

    // The colour picker opens without layout errors and records the colour.
    await tester.tap(find.byTooltip('Colour picker'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Done'), findsOneWidget);
    final pad = tester.getTopLeft(find.byType(HsvPicker));
    await tester.dragFrom(pad + const Offset(300, 40), const Offset(-200, 0));
    await tester.pump(const Duration(milliseconds: 50));
    final picked = m.color;
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(m.recent.first, picked);
    expect(find.text('Done'), findsNothing);

    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('re-opens a saved drawing with its frames and fps', (tester) async {
    final a = Frame(8, 8)..set(1, 1, 0xFF0000);
    final b = Frame(8, 8)..set(2, 2, 0x00FF00);
    final creation = Creation(
      id: 'abc',
      title: 'Blink',
      kind: 'drawing',
      clip: FrameClip.uniform([a, b], fps: 5),
      updatedAt: DateTime(2026),
      meta: const {'fps': 5},
    );
    final playback = await pumpEditor(tester, EditorScreen(initial: creation));
    final m = state(tester).model!;
    expect(find.text('Blink'), findsOneWidget);
    expect(m.frameCount, 2);
    expect(m.fps, 5);
    expect(m.frames[1].get(2, 2), 0x00FF00);
    expect(find.text('5 fps'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('with a matrix connected, drawing goes live by default', (tester) async {
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([const SavedDevice(host: '192.168.29.6', name: 'Matrix').toJson()]),
      'devices.selected': '192.168.29.6',
    });
    final devices = DeviceStore(clientFactory: FakeWled().client);
    await devices.load();
    expect(devices.isConnected, isTrue);
    final playback = await pumpEditor(tester, const EditorScreen(), devices: devices);
    await tester.tap(find.text('Blank'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(state(tester).mirroring, isTrue);
    expect(playback.generator?.id, '_editor_live');
    expect(find.text('NO DEVICE CONNECTED'), findsNothing);

    // Turning it off sticks.
    await tester.tap(find.byTooltip('Stop showing on your device'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(state(tester).mirroring, isFalse);
    expect(find.text('SHOW ON DEVICE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  group('leaving Draw', () {
    Future<(DeviceStore, FakeWled)> connected() async {
      SharedPreferences.setMockInitialValues({
        'devices.v1': jsonEncode([const SavedDevice(host: '192.168.29.6', name: 'Matrix').toJson()]),
        'devices.selected': '192.168.29.6',
      });
      final fake = FakeWled();
      final devices = DeviceStore(clientFactory: fake.client);
      await devices.load();
      return (devices, fake);
    }

    bool exitedLive(FakeWled fake) =>
        fake.posts.any((p) => p.$1 == '/json/state' && p.$2['live'] == false);

    testWidgets('stops the drawing it was showing', (tester) async {
      final (devices, fake) = await connected();
      final playback = await pumpEditor(
          tester, ToolHost(tool: () => const EditorScreen(blank: true)),
          devices: devices);
      await openTool(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(playback.generator?.id, '_editor_live');
      expect(playback.isPlaying, isTrue);

      fake.posts.clear();
      await leaveTool(tester);
      expect(find.byType(EditorScreen), findsNothing);
      expect(playback.generator, isNull);
      expect(playback.isPlaying, isFalse);
      expect(playback.isStreaming, isFalse);
      expect(exitedLive(fake), isTrue, reason: 'the matrix goes back to its own look');
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps a drawing that was sent to the device', (tester) async {
      ToolSession.clipSender = (context, clip, title) async =>
          'Sent to your device (1.0 KB). It keeps playing without your phone.';
      addTearDown(() => ToolSession.clipSender = GlyphActions.saveClipToDevice);
      final (devices, fake) = await connected();
      final playback = await pumpEditor(
          tester, ToolHost(tool: () => const EditorScreen(blank: true)),
          devices: devices);
      await openTool(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(playback.generator?.id, '_editor_live');

      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Send to device'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state(tester).sentFromTool, isTrue);

      fake.posts.clear();
      await leaveTool(tester);
      expect(find.byType(EditorScreen), findsNothing);
      expect(playback.generator?.name, 'Hi', reason: 'the sent drawing stays');
      expect(exitedLive(fake), isFalse);
      expect(tester.takeException(), isNull);
      playback.pause();
    });

    testWidgets('without drawing anything live, what played before keeps playing',
        (tester) async {
      final playback = await pumpEditor(
          tester, ToolHost(tool: () => const EditorScreen(blank: true)));
      final item = catalog.items.first;
      playback.playItem(item);
      await openTool(tester);
      expect(find.byType(EditorScreen), findsOneWidget);
      await leaveTool(tester);
      expect(playback.item, same(item));
      expect(playback.generator?.id, item.generatorId);
      expect(playback.isPlaying, isTrue);
      expect(tester.takeException(), isNull);
      playback.pause();
    });
  });
}
