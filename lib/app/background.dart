import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'playback.dart';

/// Keeps the app process — and so PlaybackController's render loop, its UDP
/// socket and the mic stream, all on the main isolate — alive with the
/// screen off, via an Android foreground service.
///
/// Why no work in the service's own isolate: on Android the main Dart
/// isolate keeps running Timers and sockets after the activity stops; what
/// ends streaming is the OS freezing or killing a backgrounded process, the
/// CPU sleeping, and Wi-Fi power-save. A foreground service puts the process
/// at foreground-service priority (not frozen, keeps network in Doze), its
/// partial wake lock keeps the CPU running and its Wi-Fi lock keeps latency
/// low. The service isolate only exists to relay the notification's Stop
/// button back here.
///
/// Must be started while the app is visible: Android 12+ refuses to start
/// foreground services from the background, and Android 14+ also requires
/// RECORD_AUDIO to already be granted for the `microphone` type.
abstract final class BackgroundStreaming {
  static final running = ValueNotifier(false);
  static bool get isRunning => running.value;

  static VoidCallback? _onStop;
  static bool _ready = false;
  static Future<void> _operations = Future.value();
  static int _pendingOperations = 0;
  static final _retainers = <Object, ({VoidCallback stop, String title, String text})>{};
  static PlaybackController? _watched;
  static bool _micType = false;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<T> _serial<T>(Future<T> Function() operation) {
    _pendingOperations++;
    final result = _operations.then((_) => operation()).whenComplete(() => _pendingOperations--);
    _operations = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  static const _stopId = 'stop';

  /// Shows the persistent "streaming" notification and holds the CPU/Wi-Fi
  /// awake. [microphone] adds the mic service type so the visualiser keeps
  /// hearing with the screen off. [onStop] runs when the notification's Stop
  /// button is pressed. Returns whether the service is running.
  static Future<bool> start({
    required String title,
    String text = 'Tap to open Glyph',
    bool microphone = false,
    VoidCallback? onStop,
  }) => _serial(() => _start(title: title, text: text, microphone: microphone, onStop: onStop));

  static Future<bool> _start({required String title, required String text,
    required bool microphone, VoidCallback? onStop}) async {
    if (!supported) return false;
    if (onStop != null) _onStop = onStop;
    _init();
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      // Without it the service still runs; the notification just hides in
      // the task manager.
      await FlutterForegroundTask.requestNotificationPermission();
    }
    final types = [
      ForegroundServiceTypes.connectedDevice,
      if (microphone) ForegroundServiceTypes.microphone,
    ];
    if (await FlutterForegroundTask.isRunningService) {
      // The type can't change on a running service, so restart it.
      await FlutterForegroundTask.stopService();
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: 4711,
      serviceTypes: types,
      notificationTitle: title,
      notificationText: text,
      notificationButtons: const [NotificationButton(id: _stopId, text: 'Stop')],
      callback: _startCallback,
    );
    running.value = result is ServiceRequestSuccess;
    _micType = running.value && microphone;
    return running.value;
  }

  /// A live feature can own the service independently of other streaming tools.
  static Future<bool> retain(Object owner, VoidCallback onStop, {
    String title = 'Glyph notification alerts',
    String text = 'Listening for your selected apps',
  }) async {
    _retainers[owner] = (stop: onStop, title: title, text: text);
    if (isRunning) { await update(title: title, text: text); return true; }
    final ok = await start(title: title, text: text);
    if (!ok) _retainers.remove(owner);
    return ok;
  }

  static Future<void> release(Object owner) async {
    _retainers.remove(owner);
    final p = _watched;
    if (_retainers.isEmpty && (_onStop == null || p == null || !p.isPlaying || !p.isStreaming)) await stop();
  }

  static Future<void> update({String? title, String? text}) async {
    if (!isRunning) return;
    await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
  }

  static Future<void> stop() {
    if (_pendingOperations == 0 && !isRunning) {
      _onStop = null;
      return Future.value();
    }
    return _serial(_stop);
  }

  static Future<void> _stop() async {
    _onStop = null;
    if (_retainers.isNotEmpty) {
      final owner = _retainers.values.last;
      if (_micType && running.value) {
        // The last microphone user left: the type can't change on a running
        // service, so restart without it (no stale mic indicator/permission use).
        await _start(title: owner.title, text: owner.text, microphone: false, onStop: null);
      } else {
        await update(title: owner.title, text: owner.text);
      }
      return;
    }
    _micType = false;
    if (!running.value) return;
    running.value = false;
    await FlutterForegroundTask.stopService();
  }

  /// Releases streaming ownership when playback ends. A notification monitor
  /// may still need the service while the device plays on its own.
  static void watch(PlaybackController playback) {
    if (identical(_watched, playback)) return;
    _watched?.removeListener(_check);
    _watched = playback..addListener(_check);
  }

  static void _check() {
    final p = _watched;
    if (p == null || !isRunning) return;
    if (!p.isPlaying || !p.isStreaming) stop();
  }

  static void _init() {
    if (_ready) return;
    _ready = true;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'glyph_streaming',
        channelName: 'Streaming',
        channelDescription: 'Shown while Glyph streams or listens for logo alerts.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        // A restarted service would have no render loop behind it.
        allowAutoRestart: false,
        stopWithTask: true,
      ),
    );
  }

  static void _onTaskData(Object data) {
    if (data != _stopId) return;
    final cb = _onStop;
    running.value = false;
    _onStop = null;
    final monitors = _retainers.values.toList();
    _retainers.clear();
    cb?.call();
    for (final stopMonitor in monitors) { stopMonitor.stop(); }
    // Monitoring can keep a regular animation alive without a tool callback.
    final p = _watched;
    if (p != null && (p.isPlaying || p.isStreaming)) {
      p.pause();
      p.stopStreaming();
    }
  }

  @visibleForTesting
  static void debugReset() {
    _watched?.removeListener(_check);
    _watched = null;
    _onStop = null;
    _retainers.clear();
    _micType = false;
    running.value = false;
  }
}

@pragma('vm:entry-point')
void _startCallback() => FlutterForegroundTask.setTaskHandler(_RelayHandler());

/// Runs in the service's isolate. Forwards Stop to the main isolate, and
/// stops the service itself in case the UI engine is already gone.
class _RelayHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id != BackgroundStreaming._stopId) return;
    FlutterForegroundTask.sendDataToMain(BackgroundStreaming._stopId);
    FlutterForegroundTask.stopService();
  }
}
