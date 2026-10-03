import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/import/crop_editor.dart';
import 'package:glyph/features/import/decode.dart';
import 'package:glyph/features/import/import_screen.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/ui/widgets/led_matrix_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/make/ambient_host.dart';

DecodedSource _gradientClip() {
  const w = 48, h = 32;
  final frames = <Uint8List>[];
  for (var f = 0; f < 6; f++) {
    final rgb = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 3;
        rgb[i] = (x * 5 + f * 20) & 0xFF;
        rgb[i + 1] = y * 8;
        rgb[i + 2] = 128;
      }
    }
    frames.add(rgb);
  }
  return DecodedSource.rgb(w, h, frames, delaysMs: List.filled(6, 80));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ImportScreen.runner = compute);

  testWidgets('editor renders an injected clip at phone size without exceptions',
      timeout: const Timeout(Duration(seconds: 60)), (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Run jobs inline so the fake clock drives them.
    ImportScreen.runner = <Q, R>(cb, Q q) async => cb(q);

    final playback = PlaybackController();
    addTearDown(playback.dispose);
    final dir = Directory.systemTemp.createTempSync('glyph_import');
    addTearDown(() => dir.deleteSync(recursive: true));
    final creations = CreationsStore(directory: () async => dir);
    final catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());

    await tester.pumpWidget(AppScope(
      playback: playback,
      devices: DeviceStore(),
      catalog: catalog,
      creations: creations,
      child: AmbientHost(
        playback: playback,
        child: MaterialApp(
          theme: buildTheme(),
          home: ImportScreen(initialSource: _gradientClip(), initialName: 'gradient'),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byType(LedMatrixView), findsOneWidget);
    expect(find.text('FRAME'), findsOneWidget);
    expect(find.text('16×16'), findsOneWidget);
    expect(find.textContaining('GIF ≈'), findsOneWidget);
    expect(find.text('6 frames · 0.5 s'), findsOneWidget);
    expect(find.text('Bring a GIF'), findsOneWidget);
    expect(find.text('Keep on matrix'), findsOneWidget);

    // Change fit mode and rotate; preview keeps rendering.
    await tester.ensureVisible(find.text('Fit'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Fit'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // Pinch/drag the crop window in fill mode.
    await tester.tap(find.text('Fill'));
    await tester.pump(const Duration(milliseconds: 100));
    final crop = find.byType(CropEditor);
    await tester.ensureVisible(crop);
    await tester.pump(const Duration(milliseconds: 100));
    final zoomBefore = tester.widget<CropEditor>(crop).settings.zoom;
    // Two-finger pinch out.
    final c = tester.getCenter(crop);
    final g1 = await tester.startGesture(c - const Offset(20, 0));
    final g2 = await tester.startGesture(c + const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 50));
    // The first steps only get past the gesture slop; the rest zoom.
    for (var i = 0; i < 4; i++) {
      await g1.moveBy(const Offset(-15, 0));
      await g2.moveBy(const Offset(15, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<CropEditor>(crop).settings.zoom, greaterThan(zoomBefore));
    await tester.drag(crop, const Offset(-40, 10));
    await tester.pump(const Duration(milliseconds: 400));

    // Scroll through the rest of the editor.
    // From the gutter, so the drag scrolls rather than turning a knob.
    await tester.dragFrom(
        tester.getTopLeft(find.byType(ListView)) + const Offset(8, 200), const Offset(0, -1500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TIMING'), findsOneWidget);
    await tester.ensureVisible(find.byType(Slider).last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(Slider).last, const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // Play hands the clip to the shared player.
    await tester.tap(find.byTooltip('Play on matrix'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(playback.generator?.name, 'gradient');
    expect(tester.takeException(), isNull);

    // Save to My Creations.
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    // The store writes a real file; let real IO finish between pumps.
    for (var i = 0; i < 40 && creations.items.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(creations.items.single.kind, 'import');
    expect(creations.items.single.clip.width, 16);

    playback.pause();
    // Unmount so the preview ticker and timers stop before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
