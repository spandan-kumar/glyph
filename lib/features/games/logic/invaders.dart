import 'dart:math';

import '../../../engine/frame.dart';
import '../core/game.dart';

const _rowColors = [0xFF5CD2, 0xB57CFF, 0x3DDCFF, 0x4BE3A0];

class Bomb {
  Bomb(this.x, this.y);

  final int x;
  double y;
}

/// A marching formation; one shot on screen at a time.
class Invaders extends Game {
  Invaders(super.width, super.height, super.seed, {super.demo}) {
    cols = ((width - 2) ~/ 3).clamp(2, 6);
    rows = (height ~/ 5).clamp(1, 4);
    px = width / 2;
    _wave();
  }

  late final int cols, rows;
  late List<bool> alive;
  int fx = 0, fy = 1, dir = 1;
  double _stepT = 0;
  int _frame = 0;
  double px = 0;
  double? shotX, shotY;
  double _cool = 0;
  final bombs = <Bomb>[];
  double _bombT = 1.5;
  int lives = 3;
  int wave = 1;
  double _invuln = 0;
  int _keyDir = 0;

  @override
  String? get status => 'Wave $wave · ${'●' * lives}';

  int get _total => rows * cols;
  int get _left => alive.where((a) => a).length;
  double get stepInterval => (0.08 + 0.55 * _left / _total) * pow(0.85, wave - 1);

  void _wave() {
    alive = List.filled(_total, true);
    fx = (width - (cols * 3 - 1)) ~/ 2;
    fy = 1 + min(wave - 1, 2);
    dir = 1;
    bombs.clear();
    shotY = null;
  }

  int invX(int c) => fx + c * 3;
  int invY(int r) => fy + r * 2;

  @override
  void press(GameKey k) {
    switch (k) {
      case GameKey.left:
        _keyDir = -1;
      case GameKey.right:
        _keyDir = 1;
      case GameKey.a || GameKey.up || GameKey.b:
        fire();
      default:
    }
  }

  @override
  void release(GameKey k) {
    if ((k == GameKey.left && _keyDir < 0) || (k == GameKey.right && _keyDir > 0)) _keyDir = 0;
  }

  @override
  void pointer(double v) => px = (v * width).clamp(1.0, width - 2.0);

  void fire() {
    if (shotY != null || _cool > 0 || isOver || paused) return;
    shotX = px.roundToDouble();
    shotY = height - 2.0;
    _cool = 0.25;
    emit(GameEvent.flap);
  }

  @override
  void update(double dt) {
    _cool -= dt;
    _invuln -= dt;
    if (_keyDir != 0) px = (px + _keyDir * 11 * dt).clamp(1.0, width - 2.0);

    _stepT += dt;
    if (_stepT >= stepInterval) {
      _stepT = 0;
      _frame++;
      _march();
    }

    final sy = shotY;
    if (sy != null) {
      final ny = sy - 22 * dt;
      // Check every row crossed so a fast shot can't skip an invader.
      for (var y = sy.floor(); y >= ny.floor(); y--) {
        if (y < 0) {
          shotY = null;
          break;
        }
        if (_hitInvader(shotX!.round(), y)) {
          shotY = null;
          break;
        }
      }
      if (shotY != null) shotY = ny;
    }

    _bombT -= dt;
    if (_bombT <= 0) {
      _dropBomb();
      _bombT = (1.4 - wave * 0.1).clamp(0.5, 1.4) * (0.6 + rng.nextDouble() * 0.8);
    }
    final p = px.round();
    for (final b in bombs) {
      b.y += 7 * dt * height / 16;
      final by = b.y.floor();
      final hit = (by == height - 1 && (b.x - p).abs() <= 1) || (by == height - 2 && b.x == p);
      if (hit && _invuln <= 0) {
        lives--;
        _invuln = 1.2;
        emit(GameEvent.hit);
        b.y = height + 1.0;
        if (lives <= 0) return endGame();
      }
    }
    bombs.removeWhere((b) => b.y >= height);
    if (_left == 0) {
      wave++;
      emit(GameEvent.level);
      _wave();
    }
  }

  void _march() {
    var minX = width, maxX = -1, maxY = -1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (!alive[r * cols + c]) continue;
        minX = min(minX, invX(c));
        maxX = max(maxX, invX(c) + 1);
        maxY = max(maxY, invY(r));
      }
    }
    if (maxX < 0) return;
    if (minX + dir < 0 || maxX + dir >= width) {
      fy++;
      dir = -dir;
      if (maxY + 1 >= height - 2) endGame();
    } else {
      fx += dir;
    }
  }

  bool _hitInvader(int x, int y) {
    for (var r = 0; r < rows; r++) {
      if (invY(r) != y) continue;
      for (var c = 0; c < cols; c++) {
        final i = r * cols + c;
        if (alive[i] && (x == invX(c) || x == invX(c) + 1)) {
          alive[i] = false;
          score += 10 * (rows - r);
          emit(GameEvent.score);
          return true;
        }
      }
    }
    return false;
  }

  void _dropBomb() {
    final shooters = <(int, int)>[];
    for (var c = 0; c < cols; c++) {
      for (var r = rows - 1; r >= 0; r--) {
        if (alive[r * cols + c]) {
          shooters.add((invX(c) + rng.nextInt(2), invY(r) + 1));
          break;
        }
      }
    }
    if (shooters.isEmpty) return;
    final (x, y) = shooters[rng.nextInt(shooters.length)];
    bombs.add(Bomb(x, y.toDouble()));
  }

  @override
  void think(double dt) {
    double? goal;
    var lowest = -1;
    for (var c = 0; c < cols; c++) {
      for (var r = rows - 1; r >= 0; r--) {
        if (!alive[r * cols + c]) continue;
        final x = invX(c) + 0.5;
        if (r > lowest || (r == lowest && (x - px).abs() < (goal! - px).abs())) {
          lowest = r;
          goal = x;
        }
        break;
      }
    }
    final threat = bombs.any((b) => b.y > height - 6 && (b.x - px).abs() < 2);
    if (threat) {
      final b = bombs.firstWhere((b) => b.y > height - 6 && (b.x - px).abs() < 2);
      goal = b.x >= px ? px - 3 : px + 3;
    }
    if (goal != null) {
      final step = 9 * dt;
      px = (px + (goal - px).clamp(-step, step)).clamp(1.0, width - 2.0);
      if (!threat && (goal - px).abs() < 0.8) fire();
    }
  }

  @override
  void draw(Frame f) {
    f.fill(0);
    for (var r = 0; r < rows; r++) {
      final color = _rowColors[r % _rowColors.length];
      for (var c = 0; c < cols; c++) {
        if (!alive[r * cols + c]) continue;
        final x = invX(c), y = invY(r);
        final step = (_frame + c).isEven;
        f.set(x, y, step ? color : scaleColor(color, 0.6));
        f.set(x + 1, y, step ? scaleColor(color, 0.6) : color);
      }
    }
    for (var i = 0; i < lives - 1; i++) {
      f.set(width - 1 - 2 * i, 0, 0x5A4FB0);
    }
    for (final b in bombs) {
      f.set(b.x, b.y.floor(), 0xFF5C7A);
    }
    final sy = shotY;
    if (sy != null) f.set(shotX!.round(), sy.floor(), 0xFFFFFF);
    final blink = _invuln > 0 && (_invuln * 10).floor().isEven;
    if (!blink) {
      final p = px.round();
      for (var i = -1; i <= 1; i++) {
        f.set(p + i, height - 1, 0x3DDCFF);
      }
      f.set(p, height - 2, 0xC8F6FF);
    }
  }
}
