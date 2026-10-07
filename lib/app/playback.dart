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

  Frame get frame => _frame;
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
    _revision++;
    final m = _params.toMap()..[key] = value;
    _params = Params(m);
    notifyListeners();
  }

  void setPalette(Palette p) {
    _revision++;
    _palette = p;
    notifyListeners();
  }

  /// Matches the render size to the device; restarts the effect state.
  void resize(int width, int height) {
    if (width == _frame.width && height == _frame.height) return;
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
    _revision++;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    notifyListeners();
  }

  /// Stops the render loop and forgets what was playing, leaving nothing on
  /// the phone. Streaming is separate (see [stopStreaming]).
  void stop() {
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
    if (_instance == null || _timer != null) return;
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
    _t += dt;
    _instance?.render(_frame, _t, dt, _params, _palette);
    final g = _group;
    if (g != null && g.isOpen && !_held && _ticks++ % _sendEvery == 0) g.send(_frame);
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
    _streamGen++;
    _revision++;
    _timer?.cancel();
    _group?.close();
    frameTick.dispose();
    super.dispose();
  }
}
