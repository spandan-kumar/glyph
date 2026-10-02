import 'dart:math';

import '../../../engine/frame.dart';
import '../core/digits.dart';
import '../core/game.dart';

/// The seven tetromino shapes in spawn orientation, inside an n×n box.
const _shapes = <(int, List<(int, int)>)>[
  (4, [(0, 1), (1, 1), (2, 1), (3, 1)]), // I
  (2, [(0, 0), (1, 0), (0, 1), (1, 1)]), // O
  (3, [(1, 0), (0, 1), (1, 1), (2, 1)]), // T
  (3, [(1, 0), (2, 0), (0, 1), (1, 1)]), // S
  (3, [(0, 0), (1, 0), (1, 1), (2, 1)]), // Z
  (3, [(0, 0), (0, 1), (1, 1), (2, 1)]), // J
  (3, [(2, 0), (0, 1), (1, 1), (2, 1)]), // L
];

const blockColors = [0x2EE6FF, 0xFFE14D, 0xB45CFF, 0x4BE36A, 0xFF4D5E, 0x3D6BFF, 0xFF9F1C];

/// Offsets tried in order when a rotation collides (simple SRS-style kicks).
const _kicks = [(0, 0), (-1, 0), (1, 0), (0, -1), (-1, -1), (1, -1), (-2, 0), (2, 0)];

const _lineScores = [0, 100, 300, 500, 800];

class Piece {
  Piece(this.type, this.x, this.y, [this.rot = 0]);

  final int type;
  int x, y, rot;

  int get size => _shapes[type].$1;

  List<(int, int)> cellsFor(int r) {
    final n = size;
    return [
      for (final c in _shapes[type].$2)
        switch (r & 3) {
          0 => c,
          1 => (n - 1 - c.$2, c.$1),
          2 => (n - 1 - c.$1, n - 1 - c.$2),
          _ => (c.$2, n - 1 - c.$1),
        }
    ];
  }

  /// Board coordinates of the four minos.
  List<(int, int)> get cells => [for (final c in cellsFor(rot)) (x + c.$1, y + c.$2)];
}

class Blocks extends Game {
  Blocks(super.width, super.height, super.seed, {super.demo}) {
    wellW = min(10, width);
    wellH = height;
    final spare = width - wellW;
    walls = spare >= 2;
    preview = spare >= 6;
    final total = wellW + (walls ? 2 : 0) + (preview ? 4 : 0);
    wellX = (width - total) ~/ 2 + (walls ? 1 : 0);
    cells = List.filled(wellW * wellH, 0);
    _next = _draw();
    _spawnNext();
  }

  late final int wellW, wellH, wellX;
  late final bool walls, preview;

  /// Locked minos, colour index + 1 (0 = empty), row-major.
  late List<int> cells;
  Piece? piece;
  late int _next;
  final _bag = <int>[];

  int level = 1;
  int lines = 0;
  List<int>? clearing;
  double _clearT = 0;
  double _fall = 0;
  double _lockT = 0;
  int _resets = 0;
  bool softDrop = false;
  int _dasDir = 0;
  double _dasT = 0;

  (int, int)? _target;
  double _aiT = 0;
  int _aiStuck = 0;

  int get nextType => _next;
  double get gravity => max(0.06, 0.8 * pow(0.82, level - 1));

  @override
  String? get status => 'Level $level · $lines lines';

  int cellAt(int x, int y) => cells[y * wellW + x];
  void setCell(int x, int y, int v) => cells[y * wellW + x] = v;

  int _draw() {
    if (_bag.isEmpty) _bag.addAll(List.generate(7, (i) => i)..shuffle(rng));
    return _bag.removeLast();
  }

  bool fits(Piece p, int x, int y, int rot) {
    for (final c in p.cellsFor(rot)) {
      final cx = x + c.$1, cy = y + c.$2;
      if (cx < 0 || cx >= wellW || cy >= wellH) return false;
      if (cy >= 0 && cellAt(cx, cy) != 0) return false;
    }
    return true;
  }

  /// Puts [type] at the top of the well; ends the game if it can't fit.
  void spawn(int type) {
    final n = _shapes[type].$1;
    final p = Piece(type, (wellW - n) ~/ 2, type == 0 ? -1 : 0);
    piece = p;
    _fall = 0;
    _lockT = 0;
    _resets = 0;
    _target = null;
    if (!fits(p, p.x, p.y, 0)) {
      piece = null;
      endGame();
    }
  }

  void _spawnNext() {
    final t = _next;
    _next = _draw();
    spawn(t);
  }

  bool _canAct() => piece != null && clearing == null && !isOver && !paused;

  bool move(int dx, int dy) {
    final p = piece;
    if (p == null || !fits(p, p.x + dx, p.y + dy, p.rot)) return false;
    p
      ..x += dx
      ..y += dy;
    if (dx != 0) _touched();
    return true;
  }

  bool rotate([int dir = 1]) {
    final p = piece;
    if (p == null || !_canAct()) return false;
    final r = (p.rot + dir) & 3;
    for (final k in _kicks) {
      if (fits(p, p.x + k.$1, p.y + k.$2, r)) {
        p
          ..x += k.$1
          ..y += k.$2
          ..rot = r;
        _touched();
        return true;
      }
    }
    return false;
  }

  // Moving a grounded piece buys it a little more time before locking.
  void _touched() {
    if (_lockT > 0 && _resets < 15) {
      _lockT = 0;
      _resets++;
    }
  }

  int dropDistance() {
    final p = piece!;
    var d = 0;
    while (fits(p, p.x, p.y + d + 1, p.rot)) {
      d++;
    }
    return d;
  }

  void hardDrop() {
    if (!_canAct()) return;
    final d = dropDistance();
    piece!.y += d;
    score += 2 * d;
    emit(GameEvent.bounce);
    _lock();
  }

  @override
  void press(GameKey k) {
    if (!_canAct()) return;
    switch (k) {
      case GameKey.left || GameKey.right:
        _dasDir = k == GameKey.left ? -1 : 1;
        _dasT = -0.16;
        move(_dasDir, 0);
      case GameKey.down:
        softDrop = true;
        if (move(0, 1)) score++;
        _fall = 0;
      case GameKey.up || GameKey.a:
        rotate();
      case GameKey.b:
        hardDrop();
    }
  }

  @override
  void release(GameKey k) {
    if ((k == GameKey.left && _dasDir < 0) || (k == GameKey.right && _dasDir > 0)) _dasDir = 0;
    if (k == GameKey.down) softDrop = false;
  }

  @override
  void update(double dt) {
    final rows = clearing;
    if (rows != null) {
      _clearT += dt;
      if (_clearT >= 0.3) _finishClear(rows);
      return;
    }
    final p = piece;
    if (p == null) return;
    if (_dasDir != 0) {
      _dasT += dt;
      while (_dasT >= 0.05) {
        _dasT -= 0.05;
        move(_dasDir, 0);
      }
    }
    final g = softDrop ? min(0.04, gravity) : gravity;
    _fall += dt;
    while (_fall >= g) {
      _fall -= g;
      if (!move(0, 1)) {
        _fall = 0;
        break;
      }
      if (softDrop) score++;
    }
    if (fits(p, p.x, p.y + 1, p.rot)) {
      _lockT = 0;
    } else {
      _lockT += dt;
      if (_lockT >= 0.5) _lock();
    }
  }

  void _lock() {
    final p = piece!;
    piece = null;
    var above = false;
    for (final c in p.cells) {
      if (c.$2 < 0) {
        above = true;
      } else {
        setCell(c.$1, c.$2, p.type + 1);
      }
    }
    if (above) return endGame();
    final full = [
      for (var y = 0; y < wellH; y++)
        if (List.generate(wellW, (x) => cellAt(x, y)).every((v) => v != 0)) y,
    ];
    if (full.isEmpty) {
      _spawnNext();
    } else {
      clearing = full;
      _clearT = 0;
      emit(GameEvent.clear);
    }
  }

  void _finishClear(List<int> rows) {
    final kept = <List<int>>[
      for (var y = 0; y < wellH; y++)
        if (!rows.contains(y)) cells.sublist(y * wellW, (y + 1) * wellW),
    ];
    cells = [
      ...List.filled(rows.length * wellW, 0),
      for (final r in kept) ...r,
    ];
    score += _lineScores[min(4, rows.length)] * level;
    lines += rows.length;
    final lv = 1 + lines ~/ 10;
    if (lv > level) {
      level = lv;
      emit(GameEvent.level);
    }
    clearing = null;
    _spawnNext();
  }

  // Attract mode: pick the best landing spot, then walk the piece there.
  @override
  void think(double dt) {
    final p = piece;
    if (p == null || clearing != null) return;
    _target ??= _bestPlacement(p);
    _aiT += dt;
    if (_aiT < 0.07) return;
    _aiT = 0;
    final (tr, tx) = _target!;
    final ok = p.rot != tr
        ? rotate()
        : p.x != tx
            ? move(p.x < tx ? 1 : -1, 0)
            : false;
    if (ok) {
      _aiStuck = 0;
    } else if (p.rot == tr && p.x == tx || ++_aiStuck > 3) {
      _aiStuck = 0;
      hardDrop();
    }
  }

  (int, int) _bestPlacement(Piece p) {
    var best = (p.rot, p.x);
    var bestScore = -1e9;
    for (var r = 0; r < (p.type == 1 ? 1 : 4); r++) {
      for (var x = -2; x < wellW; x++) {
        if (!fits(p, x, p.y, r)) continue;
        var y = p.y;
        while (fits(p, x, y + 1, r)) {
          y++;
        }
        final s = _evaluate(p, x, y, r) + rng.nextDouble() * 0.01;
        if (s > bestScore) {
          bestScore = s;
          best = (r, x);
        }
      }
    }
    return best;
  }

  double _evaluate(Piece p, int px, int py, int r) {
    final b = List.of(cells);
    for (final c in p.cellsFor(r)) {
      final y = py + c.$2;
      if (y < 0) return -1e6;
      b[y * wellW + px + c.$1] = 1;
    }
    var cleared = 0;
    for (var y = 0; y < wellH; y++) {
      var full = true;
      for (var x = 0; x < wellW; x++) {
        if (b[y * wellW + x] == 0) full = false;
      }
      if (full) cleared++;
    }
    var agg = 0, holes = 0, bump = 0, prev = -1;
    for (var x = 0; x < wellW; x++) {
      var h = 0;
      var seen = false;
      for (var y = 0; y < wellH; y++) {
        final filled = b[y * wellW + x] != 0;
        if (filled && !seen) {
          seen = true;
          h = wellH - y;
        } else if (!filled && seen) {
          holes++;
        }
      }
      agg += h;
      if (prev >= 0) bump += (h - prev).abs();
      prev = h;
    }
    return -0.51 * agg + 0.76 * cleared - 0.36 * holes - 0.18 * bump;
  }

  @override
  void draw(Frame f) {
    f.fill(0);
    if (walls) {
      for (var y = 0; y < wellH; y++) {
        f.set(wellX - 1, y, 0x1E1E2C);
        f.set(wellX + wellW, y, 0x1E1E2C);
      }
    }
    final rows = clearing;
    final blink = ((_clearT * 20).floor()).isEven;
    for (var y = 0; y < wellH; y++) {
      final flashing = rows != null && rows.contains(y);
      for (var x = 0; x < wellW; x++) {
        final v = cellAt(x, y);
        if (v == 0) continue;
        f.set(wellX + x, y,
            flashing ? (blink ? 0xFFFFFF : scaleColor(blockColors[v - 1], 0.4)) : blockColors[v - 1]);
      }
    }
    final p = piece;
    if (p != null) {
      final ghost = dropDistance();
      final color = blockColors[p.type];
      if (ghost > 0) {
        for (final c in p.cells) {
          f.set(wellX + c.$1, c.$2 + ghost, scaleColor(color, 0.18));
        }
      }
      for (final c in p.cells) {
        f.set(wellX + c.$1, c.$2, color);
      }
    }
    if (preview) {
      final px = wellX + wellW + 1;
      final n = Piece(_next, 0, 0);
      for (final c in n.cellsFor(0)) {
        // Centre smaller boxes in the 4-wide panel.
        f.set(px + c.$1 + (n.size == 4 ? 0 : 1), c.$2 + (n.type == 0 ? 0 : 1),
            scaleColor(blockColors[n.type], 0.8));
      }
      if (wellH >= 12) {
        drawDigits(f, '${level % 10}', px + 1, wellH - 6, 0x6A6A88);
      }
    }
  }
}
