import 'dart:math';

import '../../../engine/frame.dart';
import '../core/game.dart';

const _carColors = [0xFF5C7A, 0xFFB547, 0xB57CFF, 0x4BE3A0, 0xF2F2F2];

class Car {
  Car(this.lane, this.y, this.color);

  final int lane;
  double y;
  final int color;
}

/// Lane-based dodging: traffic scrolls down, the player hops lanes.
class Racer extends Game {
  Racer(super.width, super.height, super.seed, {super.demo}) {
    laneW = width >= 11 ? 4 : 3;
    lanes = max(2, (width - 1) ~/ (laneW + 1));
    edges = lanes * (laneW + 1) + 1 <= width;
    if (!edges) laneW = max(1, (width - (lanes - 1)) ~/ lanes);
    final total = edges ? lanes * (laneW + 1) + 1 : lanes * laneW + lanes - 1;
    ox = (width - total) ~/ 2;
    carW = laneW >= 3 ? 2 : 1;
    carH = height >= 12 ? 3 : 2;
    lane = lanes ~/ 2;
    playerY = height - carH;
    _nextSpawn = 2;
  }

  late int laneW;
  late final int lanes, ox, carW, carH, playerY;
  late final bool edges;
  int lane = 0;
  final cars = <Car>[];
  double distance = 0;
  double _nextSpawn = 0;
  int passed = 0;
  int level = 1;
  double _aiCool = 0;

  double get speed => min(20.0, 7 + time * 0.22) * height / 16;

  @override
  String? get status => 'Level $level';

  int laneX(int i) => ox + (edges ? 1 : 0) + i * (laneW + 1);
  int carX(int i) => laneX(i) + (laneW - carW) ~/ 2;

  void steer(int d) {
    final n = (lane + d).clamp(0, lanes - 1);
    if (n == lane || isOver || paused) return;
    lane = n;
    emit(GameEvent.move);
  }

  @override
  void press(GameKey k) {
    if (k == GameKey.left || k == GameKey.up) steer(-1);
    if (k == GameKey.right || k == GameKey.down) steer(1);
  }

  bool _overlaps(Car c, int l, double y0, double y1) =>
      c.lane == l && c.y + carH > y0 && c.y < y1;

  @override
  void update(double dt) {
    final v = speed * dt;
    distance += v;
    for (final c in cars) {
      c.y += v;
    }
    cars.removeWhere((c) {
      if (c.y < height) return false;
      passed++;
      score++;
      if (passed % 15 == 0) {
        level++;
        emit(GameEvent.level);
      }
      return true;
    });
    _nextSpawn -= v;
    if (_nextSpawn <= 0) {
      // Never block every lane, and leave time to switch between rows.
      final count = lanes >= 3 && rng.nextDouble() < 0.35 ? lanes - 1 : 1;
      final order = List.generate(lanes, (i) => i)..shuffle(rng);
      for (final l in order.take(count)) {
        cars.add(Car(l, -carH.toDouble(), _carColors[rng.nextInt(_carColors.length)]));
      }
      _nextSpawn = carH + 2 + speed * 0.28 + rng.nextInt(4);
    }
    if (cars.any((c) => _overlaps(c, lane, playerY.toDouble(), playerY + carH.toDouble()))) {
      endGame();
    }
  }

  /// Rows of clear road ahead of the player in lane [l].
  double clearance(int l) {
    var best = double.infinity;
    for (final c in cars) {
      if (c.lane != l || c.y >= playerY + carH) continue;
      best = min(best, playerY - (c.y + carH));
    }
    return best;
  }

  @override
  void think(double dt) {
    _aiCool -= dt;
    if (_aiCool > 0) return;
    final here = clearance(lane);
    if (here > speed * 0.5 + 2) return;
    var target = lane;
    var best = here;
    for (var l = 0; l < lanes; l++) {
      final c = clearance(l);
      // Only head for lanes we can reach without cutting through a car.
      final step = (l - lane).sign;
      var path = true;
      for (var i = lane + step; i != l; i += step) {
        if (clearance(i) < 0) path = false;
      }
      if (path && c > best + 0.5) {
        best = c;
        target = l;
      }
    }
    if (target != lane) {
      steer((target - lane).sign);
      _aiCool = 0.06;
    }
  }

  void _drawCar(Frame f, int l, int y, int color, {bool player = false}) {
    final x = carX(l);
    for (var r = 0; r < carH; r++) {
      final c = player
          ? (r == 0 ? 0xC8F6FF : color)
          : (r == carH - 1 ? scaleColor(color, 0.55) : color);
      for (var i = 0; i < carW; i++) {
        f.set(x + i, y + r, c);
      }
    }
  }

  @override
  void draw(Frame f) {
    f.fill(0x060609);
    final scroll = distance.floor();
    for (var y = 0; y < height; y++) {
      if (edges) {
        f.set(laneX(0) - 1, y, 0x34343F);
        f.set(laneX(lanes - 1) + laneW, y, 0x34343F);
      }
      if (((y - scroll) ~/ 2).isEven) {
        for (var i = 1; i < lanes; i++) {
          f.set(laneX(i) - 1, y, 0x22222C);
        }
      }
    }
    for (final c in cars) {
      _drawCar(f, c.lane, c.y.floor(), c.color);
    }
    _drawCar(f, lane, playerY, 0x3DDCFF, player: true);
  }
}
