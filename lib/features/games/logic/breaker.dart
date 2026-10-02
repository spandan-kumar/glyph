import 'dart:math';

import '../../../engine/frame.dart';
import '../core/game.dart';

const _rowColors = [0xFF3B5C, 0xFF9F1C, 0xFFE14D, 0x4BE3A0, 0x3DDCFF];

class Breaker extends Game {
  Breaker(super.width, super.height, super.seed, {super.demo}) {
    paddleW = max(2, width ~/ 4).toDouble();
    brickW = width >= 12 ? 2 : 1;
    cols = width ~/ brickW;
    brickX = (width - cols * brickW) ~/ 2;
    rows = (height ~/ 4).clamp(1, 5);
    top = height >= 12 ? 2 : 1;
    px = width / 2;
    target = px;
    buildLevel();
    resetBall();
  }

  late final double paddleW;
  late final int brickW, cols, rows, top, brickX;

  /// Row-major, true = brick present.
  late List<bool> bricks;
  double px = 0, target = 0;
  double bx = 0, by = 0, vx = 0, vy = 0;
  bool stuck = true;
  double _stuckT = 0;
  int lives = 3;
  int level = 1;
  int _keyDir = 0;
  double _aim = 0;

  double get speed => (height * 0.55 + 2) * pow(1.1, level - 1);
  double get paddleRow => height - 1.0;

  @override
  String? get status => 'Level $level · ${'●' * lives}';

  void buildLevel() => bricks = List.filled(rows * cols, true);

  bool brickAt(int x, int y) {
    final r = y - top, dx = x - brickX;
    if (r < 0 || r >= rows || dx < 0) return false;
    final c = dx ~/ brickW;
    return c < cols && bricks[r * cols + c];
  }

  void resetBall() {
    stuck = true;
    _stuckT = 0;
    bx = px;
    by = paddleRow - 0.5;
  }

  void launch() {
    if (!stuck) return;
    stuck = false;
    final a = (rng.nextDouble() - 0.5) * 0.9;
    vx = speed * sin(a);
    vy = -speed * cos(a);
  }

  @override
  void press(GameKey k) {
    switch (k) {
      case GameKey.left:
        _keyDir = -1;
      case GameKey.right:
        _keyDir = 1;
      case GameKey.a || GameKey.up:
        launch();
      default:
    }
  }

  @override
  void release(GameKey k) {
    if ((k == GameKey.left && _keyDir < 0) || (k == GameKey.right && _keyDir > 0)) _keyDir = 0;
  }

  @override
  void pointer(double v) {
    target = v * width;
    px = _clampPaddle(target);
  }

  double _clampPaddle(double x) => x.clamp(paddleW / 2, width - paddleW / 2);

  @override
  void update(double dt) {
    if (_keyDir != 0) target = px + _keyDir * 18 * dt;
    if (_keyDir != 0 || demo) {
      final maxStep = (demo ? 16 : 18) * dt;
      px = _clampPaddle(px + (target - px).clamp(-maxStep, maxStep));
    }
    if (stuck) {
      bx = px;
      by = paddleRow - 0.5;
      _stuckT += dt;
      if (_stuckT > (demo ? 0.6 : 3)) launch();
      return;
    }
    final n = max(1, (speed * dt / 0.3).ceil());
    for (var i = 0; i < n && !stuck && !isOver; i++) {
      _move(dt / n);
    }
  }

  void _move(double h) {
    final ox = bx, oy = by;
    bx += vx * h;
    by += vy * h;
    if (bx < 0) {
      bx = -bx;
      vx = vx.abs();
    } else if (bx >= width) {
      bx = 2 * width - bx - 0.001;
      vx = -vx.abs();
    }
    if (by < 0) {
      by = -by;
      vy = vy.abs();
    }
    final cx = bx.floor(), cy = by.floor();
    if (brickAt(cx, cy)) {
      final pcx = ox.floor(), pcy = oy.floor();
      if (pcy != cy || pcx == cx) {
        vy = -vy;
        by = oy;
      }
      if (pcx != cx) {
        vx = -vx;
        bx = ox;
      }
      final r = cy - top, c = (cx - brickX) ~/ brickW;
      bricks[r * cols + c] = false;
      score += 10 * (rows - r);
      emit(GameEvent.score);
      if (!bricks.contains(true)) {
        level++;
        emit(GameEvent.level);
        buildLevel();
        resetBall();
      }
      return;
    }
    if (vy > 0 && oy < paddleRow && by >= paddleRow) {
      final half = paddleW / 2 + 0.5;
      if ((bx - px).abs() <= half) {
        var off = ((bx - px) / half).clamp(-1.0, 1.0);
        // Never return perfectly vertical; that would loop forever.
        if (off.abs() < 0.12) off = off.isNegative ? -0.15 : 0.15;
        final a = off * 1.05;
        vx = speed * sin(a);
        vy = -speed * cos(a);
        by = 2 * paddleRow - by;
        _aim = (rng.nextDouble() - 0.5) * paddleW * 0.8;
        emit(GameEvent.bounce);
      }
    }
    if (by >= height) {
      lives--;
      emit(GameEvent.hit);
      if (lives <= 0) {
        endGame();
      } else {
        resetBall();
      }
    }
  }

  @override
  void think(double dt) {
    target = stuck ? width / 2 : bx + _aim;
  }

  @override
  void draw(Frame f) {
    f.fill(0);
    for (var r = 0; r < rows; r++) {
      final color = _rowColors[(r + level - 1) % _rowColors.length];
      for (var c = 0; c < cols; c++) {
        if (!bricks[r * cols + c]) continue;
        for (var i = 0; i < brickW; i++) {
          // Alternate shading separates neighbouring bricks.
          f.set(brickX + c * brickW + i, top + r, i == 0 ? color : scaleColor(color, 0.65));
        }
      }
    }
    for (var i = 0; i < lives - 1; i++) {
      f.set(width - 1 - 2 * i, 0, 0x5A4FB0);
    }
    final left = (px - paddleW / 2).round();
    for (var i = 0; i < paddleW; i++) {
      f.set(left + i, height - 1, i == 0 || i == paddleW - 1 ? 0x8B7CFF : 0xE6E6FF);
    }
    f.set(bx.floor(), by.floor(), 0xFFFFFF);
  }
}
