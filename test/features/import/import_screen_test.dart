import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/features/import/crop_editor.dart';
import 'package:glyph/features/import/decode.dart';
import 'package:glyph/features/import/import_screen.dart';
import 'package:glyph/features/import/processing.dart';
import 'package:glyph/ui/design/parts.dart';
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

class _Jobs {
  final gates = <Completer<void>>[];
  final jobs = <ImportJob>[];

  Future<R> run<Q, R>(ComputeCallback<Q, R> callback, Q message) async {
    jobs.add(message as ImportJob);
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return callback(message);
  }
}

class _Pops extends NavigatorObserver {
  int count = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => count++;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ImportScreen.runner = compute);

  Future<PlaybackController> pumpImport(WidgetTester tester, {bool drawing = false,
      _Pops? observer, void Function(FrameClip?)? picked}) async {
    // A phone-sized screen, so the bottom controls are on screen to tap.
    tester.view.physicalSize = const Size(412, 915) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    ImportScreen.runner = <Q, R>(cb, Q q) async => cb(q);
    final playback = PlaybackController(), devices = DeviceStore();
    addTearDown(playback.dispose);
    addTearDown(devices.dispose);
    final dir = Directory.systemTemp.createTempSync('glyph-import-races');
    addTearDown(() => dir.deleteSync(recursive: true));
    final screen = ImportScreen(initialSource: _gradientClip(),
        drawingSize: drawing ? (8, 8) : null);
    await tester.pumpWidget(AppScope(
      playback: playback, devices: devices,
      catalog: Catalog.parse(File('assets/catalog/starter.json').readAsStringSync()),
      creations: CreationsStore(directory: () async => dir),
      child: AmbientHost(playback: playback, child: MaterialApp(
        theme: buildTheme(), navigatorObservers: [?observer],
        home: Builder(builder: (context) => TextButton(
          child: const Text('home'),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (context) => TextButton(child: const Text('drawing'), onPressed: () async {
              final clip = await Navigator.of(context).push<FrameClip>(
                  MaterialPageRoute(builder: (_) => screen));
              picked?.call(clip);
            }),
          )),
        )),
      )),
    ));
    await tester.tap(find.text('home'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('drawing'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    return playback;
  }

  testWidgets('Show retries when settings change during the final render', (tester) async {
    final playback = await pumpImport(tester);
    final jobs = _Jobs();
    ImportScreen.runner = jobs.run;
    await tester.tap(find.byTooltip('Rotate'));
    await tester.tap(find.byTooltip('Show on device'));
    expect(jobs.jobs, hasLength(1));
    await tester.tap(find.byTooltip('Rotate'));
    jobs.gates[0].complete();
    await tester.pump();
    expect(jobs.jobs, hasLength(2));
    expect(playback.generator, isNull);
    jobs.gates[1].complete();
    await tester.pump();
    final expected = runImportJob(jobs.jobs.last).clip;
    final actual = (playback.generator! as ClipGenerator).clip;
    expect(actual.frames.first.rgb, expected.frames.first.rgb);
    expect(tester.takeException(), isNull);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('two drawing taps render the latest settings and pop only the import', (tester) async {
    final observer = _Pops();
    FrameClip? picked;
    final playback = await pumpImport(tester, drawing: true, observer: observer,
        picked: (clip) => picked = clip);
    final jobs = _Jobs();
    ImportScreen.runner = jobs.run;
    await tester.tap(find.byTooltip('Rotate'));
    final button = find.widgetWithText(FilledButton, 'Use in drawing');
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(jobs.jobs, hasLength(1));
    expect(find.bySemanticsLabel('Preparing your drawing'), findsOneWidget);
    expect(find.byType(LedSpinner), findsWidgets);
    await tester.tap(find.byTooltip('Rotate'));
    jobs.gates[0].complete();
    await tester.pump();
    expect(jobs.jobs, hasLength(2));
    expect(observer.count, 0);
    jobs.gates[1].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(observer.count, 1);
    expect(find.text('drawing'), findsOneWidget);
    expect(picked!.frames.first.rgb, runImportJob(jobs.jobs.last).clip.frames.first.rgb);
    expect(tester.takeException(), isNull);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('five changing renders give up without handing back a stale drawing', (tester) async {
    final observer = _Pops();
    final playback = await pumpImport(tester, drawing: true, observer: observer);
    final jobs = _Jobs();
    ImportScreen.runner = jobs.run;
    await tester.tap(find.byTooltip('Rotate'));
    await tester.tap(find.text('Use in drawing'));
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byTooltip('Rotate'));
      jobs.gates[i].complete();
      await tester.pump();
    }
    expect(jobs.jobs, hasLength(5));
    expect(observer.count, 0);
    expect(find.text('Use in drawing'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });

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
    expect(find.text('Send to device'), findsOneWidget);

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
    await tester.tap(find.byTooltip('Show on device'));
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

    // No device: Send stays enabled and offers Connect.
    await tester.tap(find.text('Send to device'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Connect a device to send this to it.'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);

    playback.pause();
    // Unmount so the preview ticker and timers stop before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('for a drawing: same tuning at the drawing size, Use in drawing returns the frames',
      timeout: const Timeout(Duration(seconds: 60)), (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    ImportScreen.runner = <Q, R>(cb, Q q) async => cb(q);

    final playback = PlaybackController();
    addTearDown(playback.dispose);
    final dir = Directory.systemTemp.createTempSync('glyph_import');
    addTearDown(() => dir.deleteSync(recursive: true));
    final creations = CreationsStore(directory: () async => dir);
    final catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
    FrameClip? picked;

    await tester.pumpWidget(AppScope(
      playback: playback,
      devices: DeviceStore(),
      catalog: catalog,
      creations: creations,
      child: AmbientHost(
        playback: playback,
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await Navigator.of(context).push<FrameClip>(
                MaterialPageRoute(
                  builder: (_) => ImportScreen(
                    initialSource: _gradientClip(),
                    initialName: 'gradient',
                    drawingSize: (8, 8),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Start from a picture'), findsOneWidget);
    // The drawing decides the size; GIF size and device room don't apply.
    expect(find.text('8×8'), findsOneWidget);
    expect(find.byTooltip('Device size'), findsNothing);
    expect(find.textContaining('GIF ≈'), findsNothing);
    // Every adjustment is still there.
    expect(find.text('FRAME'), findsOneWidget);
    expect(find.text('Fill'), findsOneWidget);
    expect(find.byTooltip('Rotate'), findsOneWidget);
    // One way out: into the drawing. No Save, Send, Play or Share here.
    expect(find.text('Send to device'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.byTooltip('Show on device'), findsNothing);
    expect(find.byTooltip('Share'), findsNothing);

    await tester.ensureVisible(find.text('Fit'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Fit'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Start from a picture'), findsOneWidget);
    await tester.tap(find.text('Use in drawing'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(picked, isNotNull);
    expect((picked!.width, picked!.height), (8, 8));
    expect(picked!.frames.length, 6);
    expect(playback.generator, isNull);
    expect(creations.items, isEmpty);
    expect(tester.takeException(), isNull);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
