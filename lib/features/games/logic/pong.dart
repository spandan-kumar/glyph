import 'dart:math';

import '../../../engine/frame.dart';
import '../core/game.dart';

/// Player vs. a beatable machine. Worked in court space: `a` runs along the
/// paddles, `d` between them. Tall/square matrices put the player at the
/// bottom; wide ones play sideways with the player on the right.
class Pong extends Game {
  Pong(super.width, super.height, super.seed, {super.demo}) {
    sideways = width > height;
    len = sideways ? height : width;
    depth = sideways ? width : height;
    paddle = max(2, len ~/ 4).toDouble();
    me = len / 2;
    ai = len / 2;
    serve(toPlayer: true);
  }

  late final bool sideways;
  late final int len, depth;
  late final double paddle;
  double me = 0, ai = 0;
  double ba = 0, bd = 0, va = 0, vd = 0;
  double _serveT = 0;
  bool _serveToPlayer = true;
  int lives = 3;
  int rally = 0;
  int _keyDir = 0;
  double _aiError = 0;

  double get speed => (depth * 0.55 + 2) * min(1.8, 1 + rally * 0.05 + score * 0.03);
  double get aiSpeed => min(14.0, 4.5 + score * 0.8) * depth / 16;

  @override
  String? get status => lives == 1 ? '1 life' : '$lives lives';

  @override
  bool get pointerVertical => sideways;

  void serve({required bool toPlayer}) {
    ba = len / 2;
    bd = depth / 2;
    va = vd = 0;
    rally = 0;
    _serveT = 0.9;
    _serveToPlayer = toPlayer;
  }

  void _launch() {
    final a = (rng.nextDouble() - 0.5) * 1.0;
    va = speed * sin(a);
    vd = speed * cos(a) * (_serveToPlayer ? 1 : -1);
  }

  @override
  void pointer(double v) => me = _clamp(v * len);

  double _clamp(double c) => c.clamp(paddle / 2, len - paddle / 2);

  @override
  void press(GameKey k) {
    final dec = sideways ? GameKey.up : GameKey.left, inc = sideways ? GameKey.down : GameKey.right;
    if (k == dec) _keyDir = -1;
    if (k == inc) _keyDir = 1;
  }

  @override
  void release(GameKey k) => _keyDir = 0;

  bool _covers(double center, double a) => (a - center).abs() <= paddle / 2 + 0.5;

  @override
  void update(double dt) {
    if (_keyDir != 0) me = _clamp(me + _keyDir * 16 * dt);
    // The machine chases a slightly wrong spot so it can be beaten.
    final goal = vd < 0 ? ba + _aiError : len / 2;
    final step = aiSpeed * dt;
    ai = _clamp(ai + (goal - ai).clamp(-step, step));

    if (_serveT > 0) {
      _serveT -= dt;
      if (_serveT <= 0) _launch();
      return;
    }
    final n = max(1, (speed * dt / 0.3).ceil());
    for (var i = 0; i < n && _serveT <= 0 && !isOver; i++) {
      _move(dt / n);
    }
  }

  void _bounce(double center, int dirSign) {
    final off = ((ba - center) / (paddle / 2 + 0.5)).clamp(-1.0, 1.0);
    final a = off * 0.9;
    rally++;
    va = speed * sin(a);
    vd = speed * cos(a) * dirSign;
  }

  void _move(double h) {
    final od = bd;
    ba += va * h;
    bd += vd * h;
    if (ba < 0) {
      ba = -ba;
      va = va.abs();
    } else if (ba >= len) {
      ba = 2 * len - ba - 0.001;
      va = -va.abs();
    }
    final near = depth - 1.0;
    if (vd < 0 && od >= 1 && bd < 1 && _covers(ai, ba)) {
      bd = 2 - bd;
      _bounce(ai, 1);
    } else if (vd > 0 && od < near && bd >= near && _covers(me, ba)) {
      bd = 2 * near - bd;
      _bounce(me, -1);
      _aiError = (rng.nextDouble() - 0.5) * (paddle + 3.5) * max(0.35, 1 - score * 0.06);
      emit(GameEvent.bounce);
    }
    if (bd < 0) {
      score++;
      emit(GameEvent.score);
      serve(toPlayer: true);
    } else if (bd >= depth) {
      lives--;
      emit(GameEvent.hit);
      if (lives <= 0) {
        endGame();
      } else {
        serve(toPlayer: false);
      }
    }
  }

  @override
  void think(double dt) {
    final goal = vd > 0 ? ba : len / 2;
    final step = 12 * dt;
    me = _clamp(me + (goal - me).clamp(-step, step));
  }

  void _set(Frame f, int a, int d, int c) => sideways ? f.set(d, a, c) : f.set(a, d, c);

  @override
  void draw(Frame f) {
    f.fill(0);
    final mid = depth ~/ 2;
    for (var a = 1; a < len; a += 2) {
      _set(f, a, mid, 0x1C1C2A);
    }
    for (var i = 0; i < lives; i++) {
      _set(f, i * 2, mid, 0x5A4FB0);
    }
    void bar(double c, int d, int color) {
      final start = (c - paddle / 2).round();
      for (var i = 0; i < paddle; i++) {
        _set(f, start + i, d, color);
      }
    }

    bar(ai, 0, 0xFF5C7A);
    bar(me, depth - 1, 0x3DDCFF);
    if (_serveT <= 0 || (_serveT * 6).floor().isEven) {
      _set(f, ba.floor(), bd.floor(), 0xFFFFFF);
    }
  }
}
