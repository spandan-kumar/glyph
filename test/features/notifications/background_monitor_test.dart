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
  late List<bool> power;
  setUp(() {
    BackgroundStreaming.debugReset();
    power = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('glyph/power'), (call) async { power.add(call.arguments as bool); return null; });
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

  test('background audio keeps its service when the activity pauses', () async {
    expect(await BackgroundStreaming.start(
      title: 'Music', microphone: true, onStop: () {},
    ), isTrue);
    final args = startArgs.single as Map;
    // Leave task removal to Android's manifest flag. Plugin 11's override
    // stops on activity pause, including Home/lock.
    expect(args, isNot(contains('stopWithTask')));
    expect(args['serviceTypes'], contains(ForegroundServiceTypes.microphone.rawValue));
    await BackgroundStreaming.stop();
    expect(power, [true, false]);
    expect(running, isFalse);
  });

  test('idle monitor stays foreground without locks; releasing its last owner stops service', () async {
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    BackgroundStreaming.watch(playback);
    final owner = Object();
    expect(await BackgroundStreaming.retain(owner, () {}), isTrue);
    expect(power, isEmpty);
    expect(startArgs.single.toString(), contains('allowWakeLock: false'));
    expect(startArgs.single.toString(), contains('allowWifiLock: false'));
    playback.pause();
    await BackgroundStreaming.stop();
    expect(BackgroundStreaming.isRunning, isTrue);
    expect(running, isTrue);
    expect(calls.where((c) => c == 'stopService'), isEmpty);
    await BackgroundStreaming.release(owner);
    expect(BackgroundStreaming.isRunning, isFalse);
    expect(running, isFalse);
  });

  test('nested alert work holds locks only until restoration completes', () async {
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    BackgroundStreaming.watch(playback);
    final owner = Object();
    await BackgroundStreaming.retain(owner, () {});
    await BackgroundStreaming.duringWork(() async {
      expect(power, [true]);
      await BackgroundStreaming.duringWork(() async {
        expect(power, [true]);
      });
      expect(power, [true]);
    });
    expect(power, [true, false]);
    await BackgroundStreaming.release(owner);
  });

  test('removing the last monitor waits for in-flight restoration before stopping', () async {
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    BackgroundStreaming.watch(playback);
    final owner = Object();
    await BackgroundStreaming.retain(owner, () {});
    await BackgroundStreaming.duringWork(() async {
      await BackgroundStreaming.release(owner);
      expect(running, true);
      expect(power, [true]);
    });
    expect(running, false);
    expect(power, [true, false]);
  });

  test('failed alert preparation releases locks and leaves monitoring alive', () async {
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    BackgroundStreaming.watch(playback);
    final owner = Object();
    await BackgroundStreaming.retain(owner, () {});
    await expectLater(BackgroundStreaming.duringWork(() async { throw StateError('offline'); }), throwsStateError);
    expect(power, [true, false]);
    expect(running, true);
    await BackgroundStreaming.release(owner);
  });

  test('a power permission failure stops the service and reports start failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('glyph/power'), (_) async {
          throw PlatformException(code: 'power');
        });
    expect(await BackgroundStreaming.start(title: 'Audio', microphone: true, onStop: () {}), false);
    expect(running, false);
    expect(BackgroundStreaming.isRunning, false);
  });

  test('failed lock release still stops the service and allows a fresh start', () async {
    var failRelease = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('glyph/power'), (call) async {
          final active = call.arguments as bool;
          power.add(active);
          if (!active && failRelease) throw PlatformException(code: 'power');
          return null;
        });
    await BackgroundStreaming.start(title: 'Music', microphone: true, onStop: () {});
    await BackgroundStreaming.stop();
    expect(running, false);
    expect(BackgroundStreaming.isRunning, false);
    expect(calls.where((c) => c == 'stopService'), hasLength(1));
    failRelease = false;
    expect(await BackgroundStreaming.start(title: 'Music', onStop: () {}), true);
    expect(power, [true, false, true]);
    await BackgroundStreaming.stop();
  });

  test('a missing power channel cannot leave the foreground service running', () async {
    await BackgroundStreaming.start(title: 'Music', onStop: () {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('glyph/power'), null);
    await BackgroundStreaming.stop();
    expect(running, false);
    expect(BackgroundStreaming.isRunning, false);
    expect(calls.where((c) => c == 'stopService'), hasLength(1));
  });

  test('a missing power channel during startup shuts the new service down', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('glyph/power'), null);
    expect(await BackgroundStreaming.start(title: 'Music', onStop: () {}), false);
    expect(running, false);
    expect(BackgroundStreaming.isRunning, false);
    expect(calls.where((c) => c == 'stopService'), hasLength(1));
  });

  test('power locks follow a monitored stream and device power without service restarts', () async {
    final playback = PlaybackController()..managePreviews();
    addTearDown(playback.dispose);
    BackgroundStreaming.watch(playback);
    final owner = Object();
    await BackgroundStreaming.retain(owner, () {});
    playback.playGenerator(NotificationLogoGenerator(NotificationLogo.fallback));
    await playback.startStreamingTo([const DdpTarget('127.0.0.1')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(power.last, true);
    playback.streamHeld = true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(power.last, false);
    playback.streamHeld = false;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(power.last, true);
    await playback.stopStreaming();
    await BackgroundStreaming.stop();
    expect(power.last, false);
    expect(calls.where((c) => c == 'startService'), hasLength(1));
    await BackgroundStreaming.release(owner);
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
