import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:glyph/app/background.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/notifications/notification_logo.dart';
import 'package:glyph/wled/ddp_group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_foreground_task/methods');
  late bool running;
  late List<String> calls;
  late List<Object?> startArgs;
  setUp(() {
    BackgroundStreaming.debugReset();
    running = false;
    calls = [];
    startArgs = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'isRunningService':
              return running;
            case 'startService':
              startArgs.add(call.arguments);
              running = true;
              return null;
            case 'stopService':
              running = false;
              return null;
            case 'checkNotificationPermission':
              return 0;
          }
          return null;
        });
  });
  tearDown(() {
    BackgroundStreaming.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('monitor remains awake without a stream; releasing its last owner stops service', () async {
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    BackgroundStreaming.watch(playback);
    final owner = Object();
    expect(await BackgroundStreaming.retain(owner, () {}), isTrue);
    playback.pause();
    await BackgroundStreaming.stop();
    expect(BackgroundStreaming.isRunning, isTrue);
    expect(running, isTrue);
    expect(calls.where((c) => c == 'stopService'), isEmpty);
    await BackgroundStreaming.release(owner);
    expect(BackgroundStreaming.isRunning, isFalse);
    expect(running, isFalse);
  });

  test(
    'releasing monitor preserves explicitly started background playback',
    () async {
      final playback = PlaybackController();
      addTearDown(playback.dispose);
      playback.playGenerator(
        NotificationLogoGenerator(NotificationLogo.fallback),
      );
      await playback.startStreamingTo([const DdpTarget('127.0.0.1')]);
      BackgroundStreaming.watch(playback);
      expect(
        await BackgroundStreaming.start(
          title: 'Now Playing',
          onStop: playback.pause,
        ),
        isTrue,
      );
      final owner = Object();
      await BackgroundStreaming.retain(owner, () {});
      await BackgroundStreaming.release(owner);
      expect(BackgroundStreaming.isRunning, isTrue);
      expect(running, isTrue);
    },
  );

  test(
    'foreground notification Stop releases both monitor and playback',
    () async {
      var stops = 0;
      await BackgroundStreaming.start(
        title: 'Now Playing',
        onStop: () => stops++,
      );
      await BackgroundStreaming.retain(Object(), () => stops++);
      for (final callback in FlutterForegroundTask.dataCallbacks.toList()) {
        callback('stop');
      }
      expect(stops, 2);
      expect(BackgroundStreaming.isRunning, isFalse);
    },
  );

  test(
    'foreground Stop ends ordinary streaming owned only by a monitor',
    () async {
      final playback = PlaybackController();
      addTearDown(playback.dispose);
      playback.playGenerator(NotificationLogoGenerator(NotificationLogo.fallback));
      await playback.startStreamingTo([const DdpTarget('127.0.0.1')]);
      BackgroundStreaming.watch(playback);
      var stopped = false;
      await BackgroundStreaming.retain(Object(), () => stopped = true);
      for (final callback in FlutterForegroundTask.dataCallbacks.toList()) {
        callback('stop');
      }
      expect(stopped, isTrue);
      expect(playback.isPlaying, isFalse);
      expect(playback.isStreaming, isFalse);
      expect(BackgroundStreaming.isRunning, isFalse);
    },
  );

  test(
    'a stop followed by a new start cannot stop the new service later',
    () async {
      await BackgroundStreaming.start(title: 'First', onStop: () {});
      final stop = BackgroundStreaming.stop();
      final start = BackgroundStreaming.start(title: 'Second', onStop: () {});
      await stop;
      expect(await start, isTrue);
      expect(running, isTrue);
      expect(BackgroundStreaming.isRunning, isTrue);
    },
  );

  test('microphone type is dropped when the last mic user leaves a monitored service', () async {
    await BackgroundStreaming.start(title: 'Audio', microphone: true, onStop: () {});
    expect(startArgs.last.toString(), contains('[1, 7]'));
    await BackgroundStreaming.retain(Object(), () {});
    await BackgroundStreaming.stop();
    expect(startArgs, hasLength(2));
    expect(startArgs.last.toString(), contains('serviceTypes: [1]'));
    expect(running, isTrue);
  });
}
