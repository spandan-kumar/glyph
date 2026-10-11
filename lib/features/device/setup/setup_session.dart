import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../app/devices.dart';
import '../../../app/playback.dart';
import '../../../engine/frame.dart';
import '../../../wled/ddp.dart';
import '../../../wled/ddp_group.dart';
import '../../../wled/device.dart';
import '../../../wled/wled_client.dart';

typedef SetupSenderFactory = DdpSender Function(String host);

/// Owns the device while the wizard shows test patterns on it.
///
/// [start] pauses whatever the app was playing or streaming and blocks
/// alerts; the session then streams its own buffers over a private DDP
/// sender, repeating the current one every [resendEvery] so the device stays
/// in live mode (its realtime timeout is 2.5 s). [end] gives everything back
/// as it was. Sending stops while the app is in the background.
class SetupSession with WidgetsBindingObserver {
  SetupSession({
    required this.playback,
    required this.devices,
    required this.host,
    this.client,
    SetupSenderFactory? senderFactory,
    this.resendEvery = const Duration(milliseconds: 100),
    this.observeLifecycle = true,
  }) : _factory = senderFactory ?? ((h) => DdpSender(h));

  final PlaybackController playback;
  final DeviceStore devices;
  final String host;

  /// Used to clear a realtime override before and to leave live mode after.
  final WledClient? client;
  final Duration resendEvery;
  final bool observeLifecycle;
  final SetupSenderFactory _factory;

  DdpSender? _sender;
  Timer? _timer;
  Uint8List? _buffer;
  bool _active = false, _ended = false, _backgrounded = false, _observing = false;
  bool _wasPlaying = false, _wasStreaming = false;
  List<DdpTarget> _previousTargets = const [];

  /// Power and brightness to give back when the test had to wake the device.
  ({bool on, int bri})? _wakeRestore;

  /// Below this a test pattern is hard to see; the test lifts it to [testBri].
  static const dimBelow = 32, testBri = 64;

  bool get isActive => _active;

  /// Nothing is being sent (backgrounded, or no buffer yet).
  bool get isSending => _timer != null;

  /// Takes over the device. Throws when the DDP socket cannot be opened, with
  /// the app's playback already restored.
  Future<void> start() async {
    if (_active || _ended) return;
    _active = true;
    _wasPlaying = playback.isPlaying;
    _wasStreaming = playback.isStreaming;
    _previousTargets = List.of(playback.targets);
    playback.blockAlerts(this);
    playback.pause();
    await playback.stopStreaming();
    final sender = _factory(host);
    try {
      await sender.open();
    } catch (_) {
      sender.close();
      await end();
      rethrow;
    }
    if (_ended) {
      sender.close();
      return;
    }
    _sender = sender;
    if (observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    try {
      await client?.prepareStream();
    } catch (_) {}
    await _wake();
  }

  /// A test on a device that is off or nearly dark would look like a failure.
  Future<void> _wake() async {
    final c = client;
    if (c == null) return;
    try {
      final st = await c.state();
      final on = st['on'] != false;
      final bri = st['bri'] is num ? (st['bri'] as num).toInt() : 128;
      if (on && bri >= dimBelow) return;
      _wakeRestore = (on: on, bri: bri);
      await c.setState({'on': true, 'bri': testBri});
    } catch (_) {}
  }

  /// Shows an LED-ordered RGB buffer as it is (not mapped, not corrected).
  void showRaw(Uint8List rgb) {
    if (!_active || _ended) return;
    _buffer = Uint8List.fromList(rgb);
    _push();
    _syncTimer();
  }

  /// Shows [frame] the way a normal stream would show it on a device with no
  /// app-side layout: the device's own map applies and its gamma settings are
  /// matched.
  void showFrame(Frame frame) {
    final color = knownLedColor[host.toLowerCase()] ?? LedColorConfig.unknown;
    showRaw(color.streamCorrection().apply(frame.rgb));
  }

  /// All LEDs off ([ledCount] of them), still in live mode.
  void showBlack(int ledCount) => showRaw(Uint8List(ledCount * 3));

  void _push() {
    final b = _buffer;
    if (b != null && !_backgrounded) _sender?.send(b);
  }

  void _syncTimer() {
    final want = _active && !_ended && !_backgrounded && _buffer != null;
    if (!want) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(resendEvery, (_) => _push());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (away == _backgrounded) return;
    _backgrounded = away;
    _syncTimer();
    if (!away) _push();
  }

  /// Stops sending, leaves live mode on the device and restores what the app
  /// was doing. Pass the new display size when it changed so playback renders
  /// at it. Safe to call more than once.
  Future<void> end({int? width, int? height}) async {
    if (_ended) return;
    _ended = true;
    final wasActive = _active;
    _active = false;
    _timer?.cancel();
    _timer = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    final sent = _sender != null;
    _sender?.close();
    _sender = null;
    _buffer = null;
    if (!wasActive) return;
    if (sent) {
      try {
        await client?.exitLive();
      } catch (_) {}
    }
    final wake = _wakeRestore;
    _wakeRestore = null;
    if (wake != null) {
      try {
        await client?.setState({'on': wake.on, 'bri': wake.bri});
      } catch (_) {}
    }
    playback.unblockAlerts(this);
    if (width != null && height != null) playback.resize(width, height);
    if (_wasPlaying) playback.resume();
    if (_wasStreaming && _previousTargets.isNotEmpty) {
      // The setup may have changed the app layout of this device.
      final layout = devices.saved
          .where((d) => d.host == host)
          .firstOrNull
          ?.layout;
      final targets = [
        for (final t in _previousTargets)
          if (layout != null && t.host == host) t.copyWith(layout: layout) else t,
      ];
      try {
        await playback.startStreamingTo(targets);
      } catch (_) {
        // The next play action reopens the stream.
      }
    }
  }
}
