import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/frame.dart';
import '../engine/generator.dart';
import '../engine/palette.dart';
import '../engine/registry.dart';
import '../library/catalog.dart';
import '../wled/ddp_group.dart';
import '../wled/layout.dart';

/// Owns the "now playing" animation: runs the render loop, exposes the latest
/// frame for previews, and streams frames over DDP to the selected device and
/// any mirrored matrices (each scaled to its own size).
class PlaybackController extends ChangeNotifier {
  PlaybackController({int width = 16, int height = 16})
      : _frame = Frame(width, height);

  static const fps = 40;

  Frame _frame;
  Generator? _generator;
  EffectInstance? _instance;
  Params _params = Params({});
  Palette _palette = palettes.first;
  LibraryItem? _item;
  double _timeScale = 1;
  double _t = 0;
  int _revision = 0;
  int _streamGen = 0;
  bool _disposed = false;

  /// User playback changes invalidate an in-flight Send's handoff.
  int get revision => _revision;
  int get streamGeneration => _streamGen;

  Timer? _timer;
  final _clock = Stopwatch();
  Duration _last = Duration.zero;

  DdpGroupSender? _group;
  List<DdpTarget> _mirrors = const [];

  /// Bumps every rendered frame; previews repaint off this without
  /// rebuilding the whole widget tree.
  final frameTick = ValueNotifier<int>(0);

  Frame get frame => _alert?.frame ?? _frame;
  bool get isAlerting => _alert != null;
  final _alertBlocks = <Object>{};
  bool get alertsBlocked => _alertBlocks.isNotEmpty;
  int _alertGeneration = 0;
  int get alertGeneration => _alertGeneration;

  /// Interactive tools and Send discard incoming alerts instead of queueing them.
  void blockAlerts(Object owner) {
    if (!_alertBlocks.add(owner)) return;
    _alertGeneration++;
    endAlert(notify: false);
    scheduleMicrotask(() { if (!_disposed) notifyListeners(); });
  }

  void unblockAlerts(Object owner) {
    if (_alertBlocks.remove(owner)) {
      scheduleMicrotask(() { if (!_disposed) notifyListeners(); });
    }
  }

  _PlaybackAlert? _alert;

  /// Draws temporarily without replacing the user's generator or its instance.
  /// Media followers keep their subscriptions and mirrors keep the base look.
  Future<bool> beginAlert(Generator generator, DdpTarget target, {required int width, required int height}) async {
    if (_disposed || alertsBlocked || _held || _alert != null) return false;
    final revision = _revision, stream = _streamGen, alerts = _alertGeneration;
    final group = streamingHosts.contains(target.host) ? null : DdpGroupSender([target]);
    try {
      await group?.open();
    } catch (_) {
      group?.close();
      rethrow;
    }
    if (_disposed || revision != _revision || stream != _streamGen || alerts != _alertGeneration || alertsBlocked || _held || _alert != null) {
      group?.close();
      return false;
    }
    _alert = _PlaybackAlert(generator, target.host, width, height, isPlaying, group);
    if (!isPlaying) _start();
    notifyListeners();
    return true;
  }

  void endAlert({bool notify = true}) {
    final alert = _alert;
    if (alert == null) return;
    _alert = null;
    alert.group?.close();
    if (!alert.wasPlaying) {
      _timer?.cancel();
      _timer = null;
      _clock.stop();
    }
    if (notify && !_disposed) notifyListeners();
  }
  Generator? get generator => _generator;
  Params get params => _params;
  Palette get palette => _palette;
  LibraryItem? get item => _item;
  double get timeScale => _timeScale;
  bool get isPlaying => _timer != null;
  bool get isStreaming => _group?.isOpen ?? false;

  /// Frames delivered to the primary target.
  int get framesSent => _group?.framesSent ?? 0;

  /// Dropped frames across every target.
  int get sendErrors => _group?.errors ?? 0;

  /// Targets of the current stream (primary first); empty when not streaming.
  List<DdpTarget> get targets => _group?.targets ?? const [];

  /// Hosts actually receiving frames right now.
  List<String> get streamingHosts => _group?.activeHosts ?? const [];

  /// Secondary targets that could not be opened.
  List<String> get failedHosts => _group?.failedHosts ?? const [];

  /// Extra matrices that [startStreaming] mirrors to.
  List<DdpTarget> get mirrors => _mirrors;

  void playItem(LibraryItem item) {
    _item = item;
    _timeScale = item.speed ?? 1;
    _play(generatorById(item.generatorId), item.params, paletteById(item.paletteId));
  }

  void playGenerator(Generator g) {
    _item = null;
    _timeScale = 1;
    _play(g, const {}, paletteById(g.defaultPalette));
  }

  void _play(Generator g, Map<String, double> params, Palette pal) {
    endAlert(notify: false);
    _revision++;
    _generator = g;
    _params = Params.defaultsFor(g, params);
    _palette = pal;
    _instance = g.create(_frame.width, _frame.height, DateTime.now().millisecond);
    _t = 0;
    _start();
    notifyListeners();
  }

  void setParam(String key, double value) {
    endAlert(notify: false);
    _revision++;
    final m = _params.toMap()..[key] = value;
    _params = Params(m);
    notifyListeners();
  }

  void setPalette(Palette p) {
    endAlert(notify: false);
    _revision++;
    _palette = p;
    notifyListeners();
  }

  /// Matches the render size to the device; restarts the effect state.
  void resize(int width, int height) {
    if (width == _frame.width && height == _frame.height) return;
    endAlert(notify: false);
    _revision++;
    _frame = Frame(width, height);
    final g = _generator;
    if (g != null) _instance = g.create(width, height, 1);
    notifyListeners();
  }

  void _start() {
    if (_timer != null) return;
    _clock
      ..reset()
      ..start();
    _last = Duration.zero;
    _timer = Timer.periodic(const Duration(microseconds: 1000000 ~/ fps), (_) => _tick());
  }

  void pause() {
    endAlert(notify: false);
    _revision++;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    notifyListeners();
  }

  /// Stops the render loop and forgets what was playing, leaving nothing on
  /// the phone. Streaming is separate (see [stopStreaming]).
  void stop() {
    endAlert(notify: false);
    _revision++;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    _generator = null;
    _instance = null;
    _item = null;
    _frame.fill(0);
    frameTick.value++;
    notifyListeners();
  }

  void resume() {
    if (_instance == null) return;
    // An alert's own timer is running: remember the user's intent so ending the
    // alert doesn't stop playback again.
    if (_alert != null && !_alert!.wasPlaying) {
      _alert!.wasPlaying = true;
      notifyListeners();
      return;
    }
    if (_timer != null) return;
    _revision++;
    _clock.start();
    _timer = Timer.periodic(const Duration(microseconds: 1000000 ~/ fps), (_) => _tick());
    notifyListeners();
  }

  void _tick() {
    final now = _clock.elapsed;
    // Clamp dt so a stalled frame (app switch, GC) doesn't make physics jump.
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1) * _timeScale;
    _last = now;
    final alert = _alert;
    if (alert == null || (alert.wasPlaying && !(_generator?.pauseDuringAlert ?? false))) {
      _t += dt;
      _instance?.render(_frame, _t, dt, _params, _palette);
    }
    if (alert != null) {
      alert.time += ((now - alert.last).inMicroseconds / 1e6).clamp(0.0, 0.1);
      alert.last = now;
      alert.effect.render(alert.frame, alert.time, 1 / fps, alert.params, alert.palette);
      if (!_held) alert.group?.send(alert.frame);
    }
    final g = _group;
    if (g != null && g.isOpen && !_held && _ticks++ % _sendEvery == 0) g.send(_frame, overrideFrame: alert?.frame, overrideHost: alert?.host);
    frameTick.value++;
  }

  int _ticks = 0;
  int _sendEvery = 1;
  Object? _throttleOwner;
  bool _held = false;

  /// While true, the stream stays open but no frames go out — the device is
  /// switched off. WLED lights itself back up when live frames resume after
  /// its realtime timeout, so an off device must get none; the phone keeps
  /// rendering, and sending resumes the moment it's switched back on.
  bool get streamHeld => _held;
  set streamHeld(bool on) {
    if (on == _held) return;
    if (on) endAlert(notify: false);
    _held = on;
    notifyListeners();
  }

  /// While true, frames go to the matrix at ~2.5 fps instead of 40: enough
  /// to stay in live mode (WLED's realtime timeout is 2.5 s) and keep showing
  /// the current look, while leaving the Wi-Fi to a file upload.
  bool get streamThrottled => _sendEvery > 1;
  set streamThrottled(bool on) => _sendEvery = on ? 16 : 1;

  void throttleStream(Object owner) {
    _throttleOwner = owner;
    streamThrottled = true;
  }

  void releaseStreamThrottle(Object owner) {
    if (!identical(_throttleOwner, owner)) return;
    _throttleOwner = null;
    streamThrottled = false;
  }

  /// Streams to [host] plus the current [mirrors].
  Future<void> startStreaming(String host, MatrixLayout layout) =>
      startStreamingTo([DdpTarget(host, layout: layout), ..._mirrors]);

  /// Streams to every target; the first is the primary and is rendered at the
  /// current frame size. Throws if the primary can't be opened; unreachable
  /// others are skipped (see [failedHosts]).
  Future<void> startStreamingTo(List<DdpTarget> targets) async {
    final stopped = stopStreaming(notify: false);
    final gen = _streamGen;
    await stopped;
    if (_disposed || gen != _streamGen) return;
    if (targets.isEmpty) return notifyListeners();
    final g = DdpGroupSender(targets);
    await g.open();
    if (_disposed || gen != _streamGen) {
      g.close();
      return;
    }
    _group = g;
    notifyListeners();
  }

  /// Sets the matrices mirrored alongside the primary. While streaming the
  /// group is reopened so the change applies immediately.
  Future<void> setMirrors(List<DdpTarget> mirrors) async {
    if (listEquals(mirrors, _mirrors)) return;
    _mirrors = List.unmodifiable(mirrors);
    final primary = targets.isEmpty ? null : targets.first;
    if (primary != null && isStreaming) {
      await startStreamingTo([primary, ..._mirrors]);
    } else {
      notifyListeners();
    }
  }

  Future<void> stopStreaming({bool notify = true}) async {
    endAlert(notify: false);
    _streamGen++;
    _group?.close();
    _group = null;
    _throttleOwner = null;
    _sendEvery = 1;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    endAlert(notify: false);
    _streamGen++;
    _revision++;
    _timer?.cancel();
    _group?.close();
    frameTick.dispose();
    super.dispose();
  }
}

class _PlaybackAlert {
  _PlaybackAlert(Generator generator, this.host, int width, int height, this.wasPlaying, this.group)
      : frame = Frame(width, height), effect = generator.create(width, height, 1),
        params = Params.defaultsFor(generator), palette = paletteById(generator.defaultPalette);
  final String host;
  final Frame frame;
  final EffectInstance effect;
  final Params params;
  final Palette palette;
  bool wasPlaying;
  final DdpGroupSender? group;
  double time = 0;
  Duration last = Duration.zero;
}
