import 'dart:math';

import '../../../engine/frame.dart';
import '../core/game.dart';

class Pipe {
  Pipe(this.x, this.gapTop, this.gap);

  double x;
  final int gapTop;
  final int gap;
  bool passed = false;
}

class Flap extends Game {
  Flap(super.width, super.height, super.seed, {super.demo}) {
    birdX = max(1, width ~/ 4);
    y = height / 2;
    pipeW = width >= 12 ? 2 : 1;
    spacing = max(5, width * 9 ~/ 16);
    final k = height / 16;
    gravity = 40 * k;
    flapSpeed = -12.5 * k;
  }

  late final int birdX, pipeW, spacing;
  late final double gravity, flapSpeed;
  double y = 0, vy = 0, _lastY = 0;
  bool started = false;
  final pipes = <Pipe>[];
  double _aiWait = 0;

  double get speed => min(8.0, 4.5 + score * 0.08) * max(1.0, width / 16);
  int get gap => max(height >= 12 ? 4 : 3, (height ~/ 3 + 1).clamp(3, 7) - score ~/ 10);

  @override
  void press(GameKey k) => flap();

  void flap() {
    if (isOver || paused) return;
    started = true;
    vy = flapSpeed;
    emit(GameEvent.flap);
  }

  void _spawn() {
    final g = gap;
    final top = 1 + rng.nextInt(max(1, height - g - 1));
    pipes.add(Pipe(pipes.isEmpty ? width + 2.0 : width.toDouble(), top, g));
  }

  bool _hits(Pipe p, int cy) {
    final x0 = p.x.floor();
    if (birdX < x0 || birdX >= x0 + pipeW) return false;
    return cy < p.gapTop || cy >= p.gapTop + p.gap;
  }

  @override
  void update(double dt) {
    _lastY = y;
    if (!started) {
      y = height / 2 + sin(time * 4) * 0.6;
      return;
    }
    vy += gravity * dt;
    y += vy * dt;
    if (y < 0) {
      y = 0;
      vy = 0;
    }
    if (y >= height) return endGame();
    if (pipes.isEmpty || pipes.last.x <= width - spacing) _spawn();
    for (final p in pipes) {
      p.x -= speed * dt;
      if (!p.passed && p.x + pipeW <= birdX) {
        p.passed = true;
        score++;
        emit(GameEvent.score);
      }
    }
    pipes.removeWhere((p) => p.x < -pipeW);
    final cy = y.floor();
    if (pipes.any((p) => _hits(p, cy))) endGame();
  }

  @override
  void think(double dt) {
    if (!started) {
      _aiWait += dt;
      if (_aiWait > 0.6) flap();
      return;
    }
    final ahead = pipes.where((p) => p.x + pipeW > birdX).toList();
    final target = ahead.isEmpty ? height / 2 : ahead.first.gapTop + ahead.first.gap / 2;
    if (y > target + 0.2 && vy > -2) flap();
  }

  @override
  void draw(Frame f) {
    for (var row = 0; row < height; row++) {
      final c = rgb(2, 4 + row * 10 ~/ height, 12 + row * 24 ~/ height);
      for (var x = 0; x < width; x++) {
        f.set(x, row, c);
      }
    }
    for (final p in pipes) {
      final x0 = p.x.floor();
      for (var row = 0; row < height; row++) {
        if (row >= p.gapTop && row < p.gapTop + p.gap) continue;
        final lip = row == p.gapTop - 1 || row == p.gapTop + p.gap;
        for (var i = 0; i < pipeW; i++) {
          f.set(x0 + i, row, lip ? 0x7CFF8A : (i == 0 ? 0x2EBD4E : 0x1D8A38));
        }
      }
    }
    final cy = y.floor().clamp(0, height - 1);
    final ly = _lastY.floor().clamp(0, height - 1);
    f.set(birdX - 1, ly, 0x6A3A00);
    f.set(birdX, cy, 0xFFD23C);
  }
}
