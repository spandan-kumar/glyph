import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/background.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/now_playing/now_playing_generator.dart';
import 'package:glyph/features/now_playing/now_playing_screen.dart';
import 'package:glyph/features/now_playing/now_playing_service.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/actions.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/make/ambient_host.dart';
import '../../ui/make/tool_host.dart';

void main() {
  late Catalog catalog;
  late StreamController<Object?> bridge;
  late NowPlayingService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
    bridge = StreamController<Object?>.broadcast();
    service = NowPlayingService(supported: true, events: () => bridge.stream);
  });

  tearDown(() {
    debugResetNowPlayingScreen();
    bridge.close();
  });

  Map<String, Object?> event({String title = 'Golden Hour', bool playing = true}) => {
        'access': true,
        'title': title,
        'artist': 'Pixel Coast',
        'app': 'Spotify',
        'durationMs': 200000,
        'positionMs': 30000,
        'atMs': DateTime.now().millisecondsSinceEpoch,
        'speed': 1.0,
        'playing': playing,
        'art': Uint8List(4 * 4 * 3)..fillRange(0, 48, 200),
        'artSize': 4,
      };

  Future<(PlaybackController, BuildContext)> pumpScreen(WidgetTester tester, {bool hosted = false}) async {
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
        child: AmbientHost(
          playback: playback,
          child: MaterialApp(theme: buildTheme(), home: hosted
              ? ToolHost(tool: () => NowPlayingScreen(service: service))
              : NowPlayingScreen(service: service)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    if (hosted) await openTool(tester);
    return (playback, tester.element(find.byType(NowPlayingScreen)));
  }

  testWidgets('asks for access until it is granted', (tester) async {
    await pumpScreen(tester);
    expect(service.isListening, isTrue);
    bridge.add({'access': false});
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Let Glyph see what\'s playing'), findsOneWidget);

    bridge.add({'access': true});
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Let Glyph see what\'s playing'), findsNothing);
    expect(find.text('Nothing playing. Start a song in any music app.'), findsOneWidget);
  });

  testWidgets('shows the song, plays it and stays on the phone only', (tester) async {
    final (playback, context) = await pumpScreen(tester);
    bridge.add(event());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Golden Hour'), findsOneWidget);
    expect(find.text('Pixel Coast · Spotify'), findsOneWidget);
    expect(find.text('0:30'), findsOneWidget);
    expect(find.text('3:20'), findsOneWidget);

    await tester.tap(find.text('Show here'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(playback.generator, isA<NowPlayingGenerator>());
    expect(playback.isPlaying, isTrue);
    // Some cover pixels are lit on the panel.
    expect(playback.frame.rgb.any((v) => v > 0), isTrue);

    // Display's Send refuses it: no GIF per song piling up on the device.
    expect(await GlyphActions.saveToDevice(context), liveOnlyMessage);

    bridge.add(event(title: 'Next One', playing: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Next One'), findsOneWidget);
    expect(find.text('PAUSED'), findsOneWidget);

    playback.pause();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('leaving stops the cover and lets go of the media sessions', (tester) async {
    final (playback, _) = await pumpScreen(tester, hosted: true);
    bridge.add(event());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Show here'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.isListening, isTrue);

    await leaveTool(tester);
    expect(playback.generator, isNull);
    expect(service.isListening, isFalse);
  });

  testWidgets('with background running, leaving keeps the cover going', (tester) async {
    final (playback, _) = await pumpScreen(tester, hosted: true);
    addTearDown(BackgroundStreaming.debugReset);
    bridge.add(event());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Show here'));
    await tester.pump(const Duration(milliseconds: 300));
    BackgroundStreaming.running.value = true;

    await leaveTool(tester);
    expect(playback.generator, isA<NowPlayingGenerator>());
    expect(playback.isPlaying, isTrue);
    expect(service.isListening, isTrue, reason: 'still following the music app');

    // Once something else plays, it lets go.
    playback.stop();
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.isListening, isFalse);
  });

  testWidgets('style switches reach the running cover', (tester) async {
    final (playback, _) = await pumpScreen(tester);
    bridge.add(event());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Show here'));
    await tester.pump(const Duration(milliseconds: 300));
    final g = playback.generator as NowPlayingGenerator;
    expect(g.style.bar, isTrue);
    await tester.scrollUntilVisible(find.text('Progress bar'), 200);
    await tester.tap(find.text('Progress bar'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(g.style.bar, isFalse);
    playback.pause();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
