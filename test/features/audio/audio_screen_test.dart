import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/audio/audio_engine.dart';
import 'package:glyph/features/audio/audio_screen.dart';
import 'package:glyph/features/audio/visualizers.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  late Catalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
  });

  tearDown(debugResetAudioScreen);

  Future<PlaybackController> pumpScreen(WidgetTester tester, AudioEngine engine) async {
    tester.view.physicalSize = const Size(360, 740) * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      AppScope(
        playback: playback,
        devices: DeviceStore(),
        catalog: catalog,
        creations: CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph')),
        child: MaterialApp(
          theme: buildTheme(),
          home: AudioScreen(engine: engine),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    return playback;
  }

  void music(FakePcmSource src, double t0, double seconds) {
    const sr = 44100;
    src.addSamples([
      for (var i = 0; i < (seconds * sr).round(); i++)
        () {
          final t = t0 + i / sr;
          final kick = exp(-(t % 0.5) / 0.08) * sin(2 * pi * 60 * t);
          return 0.5 * kick + 0.2 * sin(2 * pi * 880 * t);
        }(),
    ]);
  }

  testWidgets('listens, previews, plays and tweaks without errors', (tester) async {
    final src = FakePcmSource();
    final engine = AudioEngine(source: src, permission: FakeMicPermission(MicAccess.granted));
    final playback = await pumpScreen(tester, engine);

    expect(find.text('Music visualiser'), findsOneWidget);
    expect(engine.status, AudioStatus.listening);
    expect(find.text('Let Glyph hear the music'), findsNothing);
    expect(find.text('Spectrum'), findsOneWidget);

    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async => music(src, i * 0.25, 0.25));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(engine.latest.silent, isFalse);

    await tester.tap(find.text('Waveform'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(playback.generator, isA<AudioVisualizer>());
    expect(playback.generator!.id, 'audio_wave');
    expect(find.text('Playing (preview)'), findsOneWidget);

    // Switching look while playing swaps what's on the matrix.
    await tester.scrollUntilVisible(
      find.text('Bass fire'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Bass fire'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(playback.generator!.id, 'audio_fire');

    await tester.scrollUntilVisible(
      find.text('Sensitivity'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(engine.sensitivity, greaterThan(0.5));

    await tester.scrollUntilVisible(
      find.text('Keep screen on'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Keep screen on'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Keep running in background'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Leaving the screen keeps the mic while the visualiser plays...
    await tester.pumpWidget(const SizedBox());
    expect(engine.status, AudioStatus.listening);
    // ...and pausing playback releases it.
    playback.pause();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.status, AudioStatus.off);
  });

  testWidgets('asks for the mic with a rationale, then listens', (tester) async {
    final perm = FakeMicPermission(MicAccess.denied, onRequest: MicAccess.granted);
    final engine = AudioEngine(source: FakePcmSource(), permission: perm);
    final playback = await pumpScreen(tester, engine);

    expect(find.text('Let Glyph hear the music'), findsOneWidget);
    expect(find.textContaining('nothing is recorded'), findsOneWidget);
    // Previews still idle-animate behind the prompt.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Allow microphone'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.status, AudioStatus.listening);
    expect(find.text('Let Glyph hear the music'), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('a blocked mic offers settings', (tester) async {
    final perm = FakeMicPermission(MicAccess.blocked);
    final engine = AudioEngine(source: FakePcmSource(), permission: perm);
    final playback = await pumpScreen(tester, engine);
    expect(find.text('Microphone is off for Glyph'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(perm.openedSettings, isTrue);
    expect(tester.takeException(), isNull);
    playback.pause();
  });
}
