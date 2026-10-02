import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/frame.dart';
import '../engine/generator.dart';
import '../engine/palette.dart';
import '../engine/registry.dart';
import '../library/catalog.dart';
import '../wled/ddp.dart';
import '../wled/layout.dart';

/// Owns the "now playing" animation: runs the render loop, exposes the latest
/// frame for previews, and streams frames to the selected device over DDP.
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

  Timer? _timer;
  final _clock = Stopwatch();
  Duration _last = Duration.zero;

  DdpSender? _sender;
  MatrixLayout _layout = const MatrixLayout();

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
  bool get isStreaming => _sender?.isOpen ?? false;
  int get framesSent => _sender?.framesSent ?? 0;
  int get sendErrors => _sender?.errors ?? 0;

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
    _generator = g;
    _params = Params.defaultsFor(g, params);
    _palette = pal;
    _instance = g.create(_frame.width, _frame.height, DateTime.now().millisecond);
    _t = 0;
    _start();
    notifyListeners();
  }

  void setParam(String key, double value) {
    final m = _params.toMap()..[key] = value;
    _params = Params(m);
    notifyListeners();
  }

  void setPalette(Palette p) {
    _palette = p;
    notifyListeners();
  }

  /// Matches the render size to the device; restarts the effect state.
  void resize(int width, int height) {
    if (width == _frame.width && height == _frame.height) return;
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
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    notifyListeners();
  }

  void resume() {
    if (_instance == null || _timer != null) return;
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
    final s = _sender;
    if (s != null && s.isOpen) s.send(_layout.apply(_frame));
    frameTick.value++;
  }

  Future<void> startStreaming(String host, MatrixLayout layout) async {
    await stopStreaming(notify: false);
    _layout = layout;
    final s = DdpSender(host);
    await s.open();
    _sender = s;
    notifyListeners();
  }

  Future<void> stopStreaming({bool notify = true}) async {
    _sender?.close();
    _sender = null;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sender?.close();
    frameTick.dispose();
    super.dispose();
  }
}
