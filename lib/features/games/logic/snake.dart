import 'dart:math';

import '../../../engine/frame.dart';
import '../core/game.dart';

typedef Cell = (int, int);

class Snake extends Game {
  Snake(super.width, super.height, super.seed, {super.demo, this.wrap = true}) {
    final x = min(width - 1, max(2, width ~/ 2)), y = height ~/ 2;
    body = [(x, y), (x - 1, y), (x - 2, y)];
    placeFood();
  }

  /// Wrap around the edges instead of dying on them.
  final bool wrap;

  /// Head first.
  late List<Cell> body;
  Cell dir = (1, 0);
  Cell? food;
  final _queue = <Cell>[];
  double _acc = 0;
  int steps = 0;
  int _aiStep = -1;

  double get interval => max(0.075, 0.2 - 0.006 * score);

  @override
  String? get status => 'Length ${body.length}';

  @override
  void press(GameKey k) {
    final d = switch (k) {
      GameKey.left => (-1, 0),
      GameKey.right => (1, 0),
      GameKey.up => (0, -1),
      GameKey.down => (0, 1),
      _ => null,
    };
    if (d != null) turn(d);
  }

  /// Queues a turn; a couple can be buffered so quick swipes aren't lost.
  void turn(Cell d) {
    final last = _queue.isEmpty ? dir : _queue.last;
    if (d == last || (d.$1 == -last.$1 && d.$2 == -last.$2)) return;
    if (_queue.length < 3) _queue.add(d);
  }

  @override
  void update(double dt) {
    _acc += dt;
    while (_acc >= interval && !isOver) {
      _acc -= interval;
      step();
    }
  }

  Cell? _next(Cell from, Cell d) {
    var x = from.$1 + d.$1, y = from.$2 + d.$2;
    if (wrap) {
      x %= width;
      y %= height;
    } else if (x < 0 || y < 0 || x >= width || y >= height) {
      return null;
    }
    return (x, y);
  }

  void step() {
    if (_queue.isNotEmpty) dir = _queue.removeAt(0);
    steps++;
    final n = _next(body.first, dir);
    if (n == null) return endGame();
    final eating = n == food;
    // The tail moves out of the way unless we're growing.
    final solid = eating ? body.length : body.length - 1;
    for (var i = 0; i < solid; i++) {
      if (body[i] == n) return endGame();
    }
    body.insert(0, n);
    if (eating) {
      score++;
      emit(GameEvent.score);
      placeFood();
    } else {
      body.removeLast();
    }
  }

  void placeFood() {
    final taken = body.toSet();
    final free = [
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
          if (!taken.contains((x, y))) (x, y),
    ];
    if (free.isEmpty) {
      food = null;
      endGame();
      return;
    }
    food = free[rng.nextInt(free.length)];
  }

  @override
  void think(double dt) {
    if (_queue.isNotEmpty || _aiStep == steps) return;
    _aiStep = steps;
    final obstacles = body.sublist(0, body.length - 1).toSet();
    Cell? best;
    var bestScore = -1e9;
    for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      if (d.$1 == -dir.$1 && d.$2 == -dir.$2) continue;
      final n = _next(body.first, d);
      if (n == null || obstacles.contains(n)) continue;
      final area = _flood(n, obstacles);
      final f = food;
      final dist = f == null ? 0 : _dist(n, f);
      final s = (area >= body.length ? 1000 : area * 2) - dist + rng.nextDouble() * 0.5;
      if (s > bestScore) {
        bestScore = s;
        best = d;
      }
    }
    if (best != null) turn(best);
  }

  int _dist(Cell a, Cell b) {
    var dx = (a.$1 - b.$1).abs(), dy = (a.$2 - b.$2).abs();
    if (wrap) {
      dx = min(dx, width - dx);
      dy = min(dy, height - dy);
    }
    return dx + dy;
  }

  int _flood(Cell start, Set<Cell> blocked) {
    final seen = {start, ...blocked};
    final todo = [start];
    var n = 0;
    while (todo.isNotEmpty && n < 400) {
      final c = todo.removeLast();
      n++;
      for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final m = _next(c, d);
        if (m != null && seen.add(m)) todo.add(m);
      }
    }
    return n;
  }

  @override
  void draw(Frame f) {
    f.fill(0);
    final fd = food;
    if (fd != null) {
      f.set(fd.$1, fd.$2, scaleColor(0xFF3355, 0.65 + 0.35 * sin(time * 9)));
    }
    final len = body.length;
    for (var i = len - 1; i >= 1; i--) {
      final c = body[i];
      f.set(c.$1, c.$2, scaleColor(0x2EF06E, 1 - 0.65 * i / len));
    }
    f.set(body.first.$1, body.first.$2, 0xD8FFB0);
  }
}
