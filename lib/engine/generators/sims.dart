import 'dart:math';
import 'dart:typed_data';

import '../frame.dart';
import '../generator.dart';
import '../palette.dart';
import 'util.dart';

// Library-v2 simulations, automata and particle systems. All of them step at
// a fixed rate so they look the same at any frame rate.

class ReactionDiffusion extends Generator {
  @override
  String get id => 'reaction';
  @override
  String get name => 'Reaction Diffusion';
  @override
  String get defaultPalette => 'mint';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
        ParamSpec('pattern', 'Pattern', min: 0, max: 3, defaultValue: 0),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Reaction(width, height, Random(seed));
}

class _Reaction extends EffectInstance {
  _Reaction(this.w, this.h, this._rnd)
      : _a = Float64List(w * h),
        _b = Float64List(w * h),
        _na = Float64List(w * h),
        _nb = Float64List(w * h) {
    _seed();
  }

  // (feed, kill) pairs that survive on small toroidal panels: coral,
  // worms, labyrinth. Pattern 3 drifts between them.
  static const _presets = [(0.0545, 0.062), (0.078, 0.061), (0.042, 0.059)];
  final int w, h;
  final Random _rnd;
  Float64List _a, _b, _na, _nb;
  final _clock = FixedStep(1 / 40);
  int _steps = 0;
  double _poke = 2;
  bool _erase = true;

  void _seed() {
    _a.fillRange(0, _a.length, 1);
    _b.fillRange(0, _b.length, 0);
    final spots = max(1, w * h ~/ 60);
    for (var s = 0; s < spots; s++) {
      final cx = _rnd.nextInt(w), cy = _rnd.nextInt(h);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          _b[((cy + dy) % h) * w + (cx + dx) % w] = 1;
        }
      }
    }
    _steps = 0;
  }

  void _step(double f, double k) {
    for (var y = 0; y < h; y++) {
      final up = ((y - 1 + h) % h) * w, dn = ((y + 1) % h) * w, row = y * w;
      for (var x = 0; x < w; x++) {
        final l = (x - 1 + w) % w, r = (x + 1) % w;
        final i = row + x;
        final lapA = (_a[row + l] + _a[row + r] + _a[up + x] + _a[dn + x]) * 0.2 +
            (_a[up + l] + _a[up + r] + _a[dn + l] + _a[dn + r]) * 0.05 -
            _a[i];
        final lapB = (_b[row + l] + _b[row + r] + _b[up + x] + _b[dn + x]) * 0.2 +
            (_b[up + l] + _b[up + r] + _b[dn + l] + _b[dn + r]) * 0.05 -
            _b[i];
        final abb = _a[i] * _b[i] * _b[i];
        // Halved diffusion keeps features a few pixels wide on small panels.
        _na[i] = clamp01(_a[i] + 0.5 * lapA - abb + f * (1 - _a[i]));
        _nb[i] = clamp01(_b[i] + 0.25 * lapB + abb - (k + f) * _b[i]);
      }
    }
    final ta = _a, tb = _b;
    _a = _na;
    _b = _nb;
    _na = ta;
    _nb = tb;
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final pick = p['pattern'].round().clamp(0, 3);
    var (f, k) = pick < 3 ? _presets[pick] : _presets[0];
    if (pick == 3) {
      final u = 0.5 + 0.5 * sin(t * 0.05);
      f = _presets[0].$1 + (_presets[1].$1 - _presets[0].$1) * u;
      k = _presets[0].$2 + (_presets[1].$2 - _presets[0].$2) * u;
    }
    // Small panels settle into a still pattern, so keep disturbing it:
    // wipe a patch and let it regrow, or drop in a fresh seed.
    _poke -= dt * (0.4 + p['speed']);
    if (_poke <= 0) {
      _poke = 2.5;
      final cx = _rnd.nextInt(w), cy = _rnd.nextInt(h);
      final r = max(1, min(w, h) ~/ 5);
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx * dx + dy * dy > r * r) continue;
          final i = ((cy + dy) % h + h) % h * w + ((cx + dx) % w + w) % w;
          if (_erase) {
            _a[i] = 1;
            _b[i] = 0;
          } else if (dx.abs() <= 1 && dy.abs() <= 1) {
            _b[i] = 1;
          }
        }
      }
      _erase = !_erase;
    }
    final per = 2 + (p['speed'] * 10).round();
    for (var n = _clock.advance(dt); n > 0; n--) {
      for (var i = 0; i < per; i++) {
        _step(f, k);
      }
      _steps += per;
    }
    var total = 0.0;
    for (final v in _b) {
      total += v;
    }
    // Restart when the pattern dies or after a long run, so it keeps evolving.
    if ((_steps > 200 && total < 0.5) || _steps > 30000) _seed();
    for (var i = 0; i < _b.length; i++) {
      final v = clamp01(_b[i] * 2.2);
      out.set(i % w, i ~/ w, pal.at(0.1 + v * 0.8));
    }
  }
}

class LangtonsAnt extends Generator {
  @override
  String get id => 'ant';
  @override
  String get name => "Langton's Ant";
  @override
  String get defaultPalette => 'cmy';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
        ParamSpec('ants', 'Ants', min: 1, max: 4, defaultValue: 2),
        ParamSpec('rule', 'Rule', min: 0, max: 3, defaultValue: 0),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Ant(width, height, Random(seed));
}

class _Ant extends EffectInstance {
  _Ant(this.w, this.h, this._rnd) : _grid = Uint8List(w * h);

  static const _rules = ['RL', 'RLR', 'LLRR', 'LRRRRRLLR'];
  final int w, h;
  final Random _rnd;
  final Uint8List _grid;
  final _ants = <List<int>>[]; // x y dir
  double _acc = 0;
  int _age = 0;
  String _rule = '';

  void _reset(int n, String rule) {
    _grid.fillRange(0, _grid.length, 0);
    _ants
      ..clear()
      ..addAll(List.generate(n, (_) => [_rnd.nextInt(w), _rnd.nextInt(h), _rnd.nextInt(4)]));
    _age = 0;
    _rule = rule;
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final rule = _rules[p['rule'].round().clamp(0, 3)];
    final n = p['ants'].round().clamp(1, 4);
    if (rule != _rule || n != _ants.length) _reset(n, rule);
    final rate = 8 + p['speed'] * 240;
    _acc = min(_acc + dt * rate, 200);
    while (_acc >= 1) {
      _acc--;
      for (final a in _ants) {
        final i = a[1] * w + a[0];
        final s = _grid[i];
        a[2] = (a[2] + (rule[s] == 'R' ? 1 : 3)) % 4;
        _grid[i] = (s + 1) % rule.length;
        a[0] = (a[0] + const [0, 1, 0, -1][a[2]] + w) % w;
        a[1] = (a[1] + const [-1, 0, 1, 0][a[2]] + h) % h;
      }
      // Wipe the board once it's mostly painted, then start a new walk.
      if (++_age > w * h * 40) _reset(n, rule);
    }
    for (var i = 0; i < _grid.length; i++) {
      final s = _grid[i];
      out.set(i % w, i ~/ w, s == 0 ? scaleColor(pal.at(0.9), 0.05) : pal.at(s / rule.length));
    }
    for (final a in _ants) {
      out.set(a[0], a[1], 0xFFFFFF);
    }
  }
}

class Maze extends Generator {
  @override
  String get id => 'maze';
  @override
  String get name => 'Maze Runner';
  @override
  String get defaultPalette => 'neon';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Maze(width, height, Random(seed));
}

class _Maze extends EffectInstance {
  _Maze(this.w, this.h, this._rnd)
      : cw = max(1, (w - 1) ~/ 2),
        ch = max(1, (h - 1) ~/ 2),
        _open = Uint8List(w * h),
        _dist = Int32List(w * h) {
    if (!_tiny) _start();
  }

  bool get _tiny => w < 3 || h < 3;

  final int w, h, cw, ch;
  final Random _rnd;
  final Uint8List _open; // carved pixels
  final Int32List _dist; // flood distance from the start, -1 unvisited
  final _stack = <int>[]; // cells (cx + cy * cw)
  final _visited = <int>{};
  var _frontier = <int>[];
  var _path = <int>[];
  int _phase = 0, _maxDist = 1, _goal = 0;
  double _acc = 0, _hold = 0;

  int _px(int cx, int cy) => (1 + cy * 2) * w + 1 + cx * 2;

  void _start() {
    _open.fillRange(0, _open.length, 0);
    _dist.fillRange(0, _dist.length, -1);
    _stack
      ..clear()
      ..add(0);
    _visited
      ..clear()
      ..add(0);
    if (_px(0, 0) < _open.length) _open[_px(0, 0)] = 1;
    _phase = 0;
    _path = [];
    _hold = 0;
  }

  void _carveStep() {
    if (_stack.isEmpty) {
      _phase = 1;
      final s = _px(0, 0);
      _dist[s] = 0;
      _frontier = [s];
      _goal = _px(cw - 1, ch - 1);
      return;
    }
    final c = _stack.last;
    final cx = c % cw, cy = c ~/ cw;
    final opts = <(int, int)>[];
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = cx + dx, ny = cy + dy;
      if (nx < 0 || ny < 0 || nx >= cw || ny >= ch || _visited.contains(nx + ny * cw)) continue;
      opts.add((nx, ny));
    }
    if (opts.isEmpty) {
      _stack.removeLast();
      return;
    }
    final (nx, ny) = opts[_rnd.nextInt(opts.length)];
    final a = _px(cx, cy), b = _px(nx, ny);
    _open[(a + b) ~/ 2] = 1;
    _open[b] = 1;
    _visited.add(nx + ny * cw);
    _stack.add(nx + ny * cw);
  }

  void _floodStep() {
    final next = <int>[];
    for (final i in _frontier) {
      for (final d in [1, -1, w, -w]) {
        final j = i + d;
        if (j < 0 || j >= _open.length || _open[j] == 0 || _dist[j] >= 0) continue;
        if ((d == 1 || d == -1) && j ~/ w != i ~/ w) continue;
        _dist[j] = _dist[i] + 1;
        _maxDist = max(_maxDist, _dist[j]);
        next.add(j);
      }
    }
    _frontier = next;
    if (next.isEmpty) {
      // Walk back from the goal along decreasing distance.
      var i = _goal;
      final path = <int>[];
      if (_dist[i] < 0) i = _px(0, 0);
      while (_dist[i] > 0) {
        path.add(i);
        for (final d in [1, -1, w, -w]) {
          final j = i + d;
          if (j >= 0 && j < _dist.length && _dist[j] == _dist[i] - 1) {
            i = j;
            break;
          }
        }
      }
      path.add(i);
      _path = path.reversed.toList();
      _phase = 2;
    }
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    if (_tiny) {
      out.fill(scaleColor(pal.at(t * 0.1), 0.6));
      return;
    }
    final rate = 10 + p['speed'] * 120;
    _acc = min(_acc + dt * rate, 60);
    while (_acc >= 1) {
      _acc--;
      if (_phase == 0) {
        _carveStep();
      } else if (_phase == 1) {
        _floodStep();
      }
    }
    if (_phase == 2) {
      _hold += dt;
      if (_hold > 3.5) _start();
    }
    final wall = scaleColor(pal.at(0.6), 0.12);
    final head = _stack.isNotEmpty ? _stack.last : -1;
    final shown = _phase == 2 ? (_hold / 1.5 * _path.length).floor() : 0;
    final onPath = _path.take(shown).toSet();
    final fade = _phase == 2 ? clamp01((3.5 - _hold) / 0.6) : 1.0;
    for (var i = 0; i < _open.length; i++) {
      int c;
      if (_open[i] == 0) {
        c = wall;
      } else if (onPath.contains(i)) {
        c = 0xFFFFFF;
      } else if (_dist[i] >= 0) {
        c = scaleColor(pal.at(_dist[i] / _maxDist * 0.8), 0.7);
      } else {
        c = scaleColor(pal.at(0.9), 0.25);
      }
      out.set(i % w, i ~/ w, scaleColor(c, fade));
    }
    if (_phase == 0 && head >= 0) {
      final hx = head % cw, hy = head ~/ cw;
      final i = _px(hx, hy);
      if (i < _open.length) out.set(i % w, i ~/ w, pal.at(0.98));
    }
  }
}

class FallingSand extends Generator {
  @override
  String get id => 'sand';
  @override
  String get name => 'Falling Sand';
  @override
  String get defaultPalette => 'desert';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('rate', 'Pour', defaultValue: 0.5),
        ParamSpec('spouts', 'Spouts', min: 1, max: 3, defaultValue: 2),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Sand(width, height, Random(seed));
}

class _Sand extends EffectInstance {
  _Sand(this.w, this.h, this._rnd) : _g = Float64List(w * h)..fillRange(0, w * h, -1);

  final int w, h;
  final Random _rnd;
  final Float64List _g; // grain colour index, -1 empty
  final _clock = FixedStep(1 / 30);
  double _time = 0;
  bool _draining = false;

  void _tick(Params p) {
    _time += 1 / 30;
    if (_draining) {
      // Open the floor: the bottom row drops out until the box is empty.
      for (var x = 0; x < w; x++) {
        _g[(h - 1) * w + x] = -1;
      }
    } else {
      final n = p['spouts'].round().clamp(1, 3);
      for (var s = 0; s < n; s++) {
        if (_rnd.nextDouble() > 0.3 + p['rate'] * 0.7) continue;
        final x = (w * (0.5 + 0.42 * sin(_time * (0.3 + s * 0.17) + s * 2.1))).floor().clamp(0, w - 1);
        if (_g[x] < 0) _g[x] = (_time * 0.04 + s * 0.33) % 1;
      }
    }
    for (var y = h - 2; y >= 0; y--) {
      // Alternate scan direction so piles don't lean one way.
      final ltr = _rnd.nextBool();
      for (var k = 0; k < w; k++) {
        final x = ltr ? k : w - 1 - k;
        final i = y * w + x;
        if (_g[i] < 0) continue;
        final below = i + w;
        if (_g[below] < 0) {
          _g[below] = _g[i];
          _g[i] = -1;
          continue;
        }
        final d = _rnd.nextBool() ? 1 : -1;
        for (final dx in [d, -d]) {
          final nx = x + dx;
          if (nx < 0 || nx >= w) continue;
          if (_g[below + dx] < 0) {
            _g[below + dx] = _g[i];
            _g[i] = -1;
            break;
          }
        }
      }
    }
    var filled = 0;
    for (final v in _g) {
      if (v >= 0) filled++;
    }
    if (!_draining && filled > w * h * 0.7) _draining = true;
    if (_draining && filled == 0) _draining = false;
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    for (var n = _clock.advance(dt); n > 0; n--) {
      _tick(p);
    }
    for (var i = 0; i < _g.length; i++) {
      final v = _g[i];
      final shade = 0.75 + 0.25 * ((i * 2654435761) % 7) / 6;
      out.set(i % w, i ~/ w, v < 0 ? scaleColor(pal.at(0.1), 0.06) : scaleColor(pal.at(v), shade));
    }
  }
}

class PixelSort extends Generator {
  @override
  String get id => 'pixelsort';
  @override
  String get name => 'Pixel Sort';
  @override
  String get defaultPalette => 'vaporwave';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
        ParamSpec('direction', 'Direction', min: 0, max: 1, defaultValue: 0),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _PixelSort(width, height, Random(seed));
}

class _PixelSort extends EffectInstance {
  _PixelSort(this.w, this.h, this._rnd) : _v = Float64List(w * h) {
    _scramble();
  }

  final int w, h;
  final Random _rnd;
  final Float64List _v;
  double _acc = 0, _hold = 0;
  int _pass = 0;
  bool _sorted = false;

  void _scramble() {
    final n = ValueNoise(_rnd);
    for (var i = 0; i < _v.length; i++) {
      _v[i] = clamp01(n.fbm((i % w) * 0.3, (i ~/ w) * 0.3, 0) * 1.4 - 0.2 + (_rnd.nextDouble() - 0.5) * 0.25);
    }
    _pass = 0;
    _sorted = false;
    _hold = 0;
  }

  /// One odd-even transposition pass over every line; returns true if done.
  bool _sortPass(bool vertical) {
    var swapped = false;
    final lines = vertical ? w : h, len = vertical ? h : w;
    for (var l = 0; l < lines; l++) {
      for (var k = _pass % 2; k + 1 < len; k += 2) {
        final a = vertical ? k * w + l : l * w + k;
        final b = vertical ? a + w : a + 1;
        if (_v[a] > _v[b]) {
          final tmp = _v[a];
          _v[a] = _v[b];
          _v[b] = tmp;
          swapped = true;
        }
      }
    }
    _pass++;
    return !swapped && _pass > 1;
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final vertical = p['direction'] < 0.5;
    if (_sorted) {
      _hold += dt;
      if (_hold > 2.5) _scramble();
    } else {
      _acc = min(_acc + dt * (4 + p['speed'] * 40), 20);
      while (_acc >= 1 && !_sorted) {
        _acc--;
        _sorted = _sortPass(vertical);
      }
    }
    final shift = t * 0.02;
    for (var i = 0; i < _v.length; i++) {
      out.set(i % w, i ~/ w, scaleColor(pal.at(_v[i] * 0.85 + shift), 0.25 + 0.75 * _v[i]));
    }
  }
}

class Glitch extends Generator {
  @override
  String get id => 'glitch';
  @override
  String get name => 'Signal Glitch';
  @override
  String get defaultPalette => 'cyberpunk';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('intensity', 'Glitch', defaultValue: 0.5),
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Glitch(width, height, Random(seed));
}

class _Glitch extends EffectInstance {
  _Glitch(this.w, this.h, this._rnd)
      : _base = Frame(w, h),
        _rowShift = Int32List(h);

  final int w, h;
  final Random _rnd;
  final Frame _base;
  final Int32List _rowShift;
  double _burst = 0, _next = 0.5, _split = 0;
  int _blockX = 0, _blockY = 0, _blockW = 0, _blockH = 0;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final inten = p['intensity'];
    final tt = t * (0.3 + p['speed'] * 1.5);
    // Base picture: smooth diagonal bands with scanlines.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = (x + y * 0.6) / max(w, h) * 1.2 + tt * 0.3 + 0.15 * sin(y * 0.7 + tt);
        final scan = y.isOdd ? 0.7 : 1.0;
        _base.set(x, y, scaleColor(pal.at(v), scan * 0.85));
      }
    }
    if (t >= _next) {
      _burst = 0.12 + _rnd.nextDouble() * 0.35;
      _next = t + _burst + (2.5 - inten * 2.2) * (0.3 + _rnd.nextDouble());
      for (var y = 0; y < h; y++) {
        _rowShift[y] = _rnd.nextDouble() < 0.35 ? _rnd.nextInt(max(1, w ~/ 2)) - w ~/ 4 : 0;
      }
      _split = 1 + _rnd.nextInt(max(1, w ~/ 8)).toDouble();
      _blockW = 1 + _rnd.nextInt(max(1, w ~/ 2));
      _blockH = 1 + _rnd.nextInt(max(1, h ~/ 4));
      _blockX = _rnd.nextInt(w);
      _blockY = _rnd.nextInt(h);
    }
    _burst -= dt;
    final active = _burst > 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!active) {
          out.set(x, y, _base.get(x, y));
          continue;
        }
        final sx = ((x - _rowShift[y]) % w + w) % w;
        // Chromatic split: red and blue sampled from shifted columns.
        final s = _split.toInt();
        final r = (_base.get(((sx - s) % w + w) % w, y) >> 16) & 0xFF;
        final g = (_base.get(sx, y) >> 8) & 0xFF;
        final b = _base.get((sx + s) % w, y) & 0xFF;
        var c = rgb(r, g, b);
        final inBlock = x >= _blockX && x < _blockX + _blockW && y >= _blockY && y < _blockY + _blockH;
        if (inBlock) c = _rnd.nextDouble() < 0.5 ? pal.at(_rnd.nextDouble()) : 0;
        out.set(x, y, c);
      }
    }
  }
}

class Confetti extends Generator {
  @override
  String get id => 'confetti';
  @override
  String get name => 'Confetti';
  @override
  String get defaultPalette => 'festive';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('amount', 'Amount', defaultValue: 0.5),
        ParamSpec('wind', 'Wind', min: -1, max: 1, defaultValue: 0),
        ParamSpec('bursts', 'Bursts', defaultValue: 0.4),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Confetti(width, height, Random(seed));
}

class _Confetti extends EffectInstance {
  _Confetti(this.w, this.h, this._rnd);

  final int w, h;
  final Random _rnd;
  final _bits = <List<double>>[]; // x y vx vy spin phase hue
  final _clock = FixedStep(1 / 60);
  double _time = 0, _nextBurst = 1;

  void _add(double x, double y, double vx, double vy) =>
      _bits.add([x, y, vx, vy, 3 + _rnd.nextDouble() * 9, _rnd.nextDouble() * 6, _rnd.nextDouble()]);

  void _tick(Params p) {
    const dt = 1 / 60;
    _time += dt;
    final target = (w * h * (0.03 + p['amount'] * 0.15)).round();
    if (_bits.length < target && _rnd.nextDouble() < 0.5) {
      _add(_rnd.nextDouble() * w, -1, 0, h * 0.1);
    }
    if (p['bursts'] > 0.02 && _time > _nextBurst) {
      final left = _rnd.nextBool();
      for (var i = 0; i < 10 + p['amount'] * 20; i++) {
        final a = (left ? -pi / 3 : -2 * pi / 3) + (_rnd.nextDouble() - 0.5) * 0.7;
        final sp = h * (1.3 + _rnd.nextDouble() * 1.2);
        _add(left ? 0 : w.toDouble(), h.toDouble(), cos(a) * sp, sin(a) * sp);
      }
      _nextBurst = _time + (5 - p['bursts'] * 4) * (0.6 + _rnd.nextDouble() * 0.8);
    }
    final wind = p['wind'] * w * 0.2;
    for (final b in _bits) {
      // Paper has a low terminal velocity and flutters side to side.
      b[3] += h * 1.2 * dt;
      b[2] += (wind - b[2]) * 1.5 * dt;
      b[3] += (h * 0.18 - b[3]) * 2.2 * dt * (b[3] > 0 ? 1 : 0.2);
      b[0] += (b[2] + sin(_time * 3 + b[5]) * w * 0.05) * dt;
      b[1] += b[3] * dt;
    }
    _bits.removeWhere((b) => b[1] > h + 1 || b[0] < -3 || b[0] > w + 3);
    if (_bits.length > 400) _bits.removeRange(0, _bits.length - 400);
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    for (var n = _clock.advance(dt); n > 0; n--) {
      _tick(p);
    }
    out.fill(0);
    for (final b in _bits) {
      // Spinning flakes show their face, then their dim edge.
      final face = 0.25 + 0.75 * cos(_time * b[4] + b[5]).abs();
      final x = b[0].floor(), y = b[1].floor();
      if (x >= 0 && y >= 0 && x < w && y < h) out.set(x, y, scaleColor(pal.at(b[6]), face));
    }
  }
}

class Bubbles extends Generator {
  @override
  String get id => 'bubbles';
  @override
  String get name => 'Bubbles';
  @override
  String get defaultPalette => 'deepsea';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('count', 'Bubbles', min: 2, max: 20, defaultValue: 8),
        ParamSpec('size', 'Size', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Bubbles(width, height, Random(seed));
}

class _Bubbles extends EffectInstance {
  _Bubbles(this.w, this.h, this._rnd);

  final int w, h;
  final Random _rnd;
  final _b = <List<double>>[]; // x y r phase hue
  final _pops = <List<double>>[]; // x y age

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final m = min(w, h).toDouble();
    final n = p['count'].round().clamp(2, 20);
    while (_b.length < n) {
      final r = max(0.5, m * (0.05 + _rnd.nextDouble() * 0.1) * (0.5 + p['size']));
      _b.add([_rnd.nextDouble() * w, h + r + _rnd.nextDouble() * h * (_b.isEmpty ? 0 : 1), r, _rnd.nextDouble() * 6, _rnd.nextDouble()]);
    }
    if (_b.length > n) _b.removeRange(n, _b.length);
    for (var y = 0; y < h; y++) {
      final v = (y + 0.5) / h;
      final bg = mixColor(scaleColor(pal.at(0.75), 0.4), scaleColor(pal.at(0.4), 0.25), v);
      for (var x = 0; x < w; x++) {
        out.set(x, y, bg);
      }
    }
    for (final b in _b) {
      b[1] -= dt * h * (0.15 + 0.5 / (1 + b[2]));
      final x = b[0] + sin(t * 2 + b[3]) * m * 0.04;
      if (b[1] < b[2] * 0.5) {
        _pops.add([x, max(0.5, b[1]), 0]);
        b[1] = h + b[2] + _rnd.nextDouble() * h * 0.5;
        b[0] = _rnd.nextDouble() * w;
        continue;
      }
      final r = b[2];
      final rim = pal.at(0.85 + b[4] * 0.14);
      for (var py = (b[1] - r - 1).floor(); py <= (b[1] + r + 1).ceil(); py++) {
        for (var px = (x - r - 1).floor(); px <= (x + r + 1).ceil(); px++) {
          if (px < 0 || py < 0 || px >= w || py >= h) continue;
          final d = sqrt(pow(px + 0.5 - x, 2) + pow(py + 0.5 - b[1], 2));
          final edge = clamp01(1 - (d - r).abs() * 1.2);
          final inside = d < r ? 0.18 : 0.0;
          final k = max(edge * 0.85, inside);
          if (k > 0) out.set(px, py, mixColor(out.get(px, py), rim, k));
        }
      }
      // Specular glint, top-left.
      splat(out, x - r * 0.45, b[1] - r * 0.45, 0xFFFFFF, r > 1.2 ? 0.9 : 0.4);
    }
    for (final pop in _pops) {
      pop[2] += dt;
      final k = 1 - pop[2] / 0.3;
      if (k <= 0) continue;
      final rr = 0.6 + pop[2] * m * 0.6;
      for (var a = 0; a < 6; a++) {
        final ang = a / 6 * 2 * pi;
        splat(out, pop[0] + cos(ang) * rr, pop[1] + sin(ang) * rr, scaleColor(0xFFFFFF, k * 0.7));
      }
    }
    _pops.removeWhere((pp) => pp[2] > 0.3);
  }
}

class Equalizer extends Generator {
  @override
  String get id => 'equalizer';
  @override
  String get name => 'Equalizer';
  @override
  String get defaultPalette => 'rainbow';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('bpm', 'Tempo', min: 60, max: 180, defaultValue: 120),
        ParamSpec('energy', 'Energy', defaultValue: 0.6),
        ParamSpec('style', 'Style', min: 0, max: 2, defaultValue: 0),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Equalizer(width, Random(seed));
}

class _Equalizer extends EffectInstance {
  _Equalizer(int w, this._rnd)
      : _lvl = Float64List(w),
        _peak = Float64List(w),
        _target = Float64List(w);

  final Random _rnd;
  final Float64List _lvl, _peak, _target;
  final _clock = FixedStep(1 / 60);
  double _time = 0, _nextHit = 0;

  void _tick(int w, Params p) {
    const dt = 1 / 60;
    _time += dt;
    final beat = 60 / p['bpm'];
    final energy = p['energy'];
    final ph = (_time / beat) % 1;
    final kick = exp(-ph * 9);
    if (_time >= _nextHit) {
      for (var i = 0; i < w; i++) {
        final band = i / max(1, w - 1); // 0 = bass
        final base = 0.25 + 0.35 * energy * (1 - band * 0.5);
        _target[i] = clamp01(base + (_rnd.nextDouble() - 0.4) * 0.6 * energy);
      }
      _nextHit = _time + beat / 4;
    }
    for (var i = 0; i < w; i++) {
      final band = i / max(1, w - 1);
      final want = clamp01(_target[i] + kick * (1 - band) * 0.55 * energy);
      // Fast attack, slow release, like a real meter.
      _lvl[i] += (want - _lvl[i]) * (want > _lvl[i] ? 0.5 : 0.08);
      _peak[i] = _lvl[i] > _peak[i] ? _lvl[i] : max(0.0, _peak[i] - dt * 0.35);
    }
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    for (var n = _clock.advance(dt); n > 0; n--) {
      _tick(w, p);
    }
    final style = p['style'].round();
    // Bars are 2 px wide with a gap on wide panels, 1 px on narrow ones.
    final bw = w >= 12 ? 2 : 1, gap = w >= 12 ? 1 : 0;
    final groups = max(1, (w + gap) ~/ (bw + gap));
    out.fill(0);
    for (var g = 0; g < groups; g++) {
      final band = (g * w / groups).floor().clamp(0, w - 1);
      final lvl = _lvl[band], pk = _peak[band];
      for (var k = 0; k < bw; k++) {
        final x = g * (bw + gap) + k + (w - (groups * (bw + gap) - gap)) ~/ 2;
        if (x < 0 || x >= w) continue;
        for (var y = 0; y < h; y++) {
          final fromBottom = style == 1 ? ((y + 0.5) - h / 2).abs() * 2 / h : (h - y - 0.5) / h;
          int c = 0;
          if (fromBottom <= lvl) {
            c = style == 2 ? pal.at(g / groups) : pal.at(0.02 + fromBottom * 0.38);
            c = scaleColor(c, 0.55 + 0.45 * fromBottom / max(0.05, lvl));
          } else if ((fromBottom - pk).abs() < 0.5 / h + 0.01) {
            c = scaleColor(0xFFFFFF, 0.8);
          }
          if (c != 0) out.set(x, y, c);
        }
      }
    }
  }
}

class PendulumWave extends Generator {
  @override
  String get id => 'pendulum';
  @override
  String get name => 'Pendulum Wave';
  @override
  String get defaultPalette => 'rainbow';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.45),
        ParamSpec('trails', 'Trails', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Pendulum(width, height);
}

class _Pendulum extends EffectInstance {
  _Pendulum(int w, int h) : _buf = Frame(w, h);

  final Frame _buf;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = _buf.width, h = _buf.height;
    final vertical = h >= w;
    final n = vertical ? w : h, len = vertical ? h : w;
    // The whole row realigns every [cycle] seconds.
    final cycle = 40 - p['speed'] * 28;
    _buf.fade(pow(0.2 + p['trails'] * 0.6, dt * 30).toDouble());
    for (var i = 0; i < n; i++) {
      final osc = 12 + i; // oscillations per cycle
      final ph = 2 * pi * osc * t / cycle;
      final pos = len / 2 + sin(ph) * (len / 2 - 0.8);
      final c = pal.at(i / n);
      if (vertical) {
        splat(_buf, i + 0.5, pos, c, 1.5);
      } else {
        splat(_buf, pos, i + 0.5, c, 1.5);
      }
    }
    out.rgb.setAll(0, _buf.rgb);
  }
}

class Boids extends Generator {
  @override
  String get id => 'boids';
  @override
  String get name => 'Flocking Birds';
  @override
  String get defaultPalette => 'sunset';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('count', 'Birds', min: 4, max: 30, defaultValue: 14),
        ParamSpec('trails', 'Trails', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Boids(width, height, Random(seed));
}

class _Boids extends EffectInstance {
  _Boids(this.w, this.h, this._rnd) : _heat = Heat(w, h);

  final int w, h;
  final Random _rnd;
  final Heat _heat;
  final _b = <List<double>>[]; // x y vx vy
  final _clock = FixedStep(1 / 40);

  void _tick() {
    const dt = 1 / 40;
    final m = max(4.0, min(w, h).toDouble());
    final maxV = m * 0.5;
    for (final b in _b) {
      var cx = 0.0, cy = 0.0, ax = 0.0, ay = 0.0, sx = 0.0, sy = 0.0;
      var n = 0;
      for (final o in _b) {
        if (identical(o, b)) continue;
        final dx = o[0] - b[0], dy = o[1] - b[1];
        final d2 = dx * dx + dy * dy;
        if (d2 > m * m * 0.12) continue;
        n++;
        cx += dx;
        cy += dy;
        ax += o[2];
        ay += o[3];
        if (d2 < m * m * 0.012) {
          sx -= dx / (d2 + 0.1);
          sy -= dy / (d2 + 0.1);
        }
      }
      if (n > 0) {
        b[2] += (cx / n) * 0.6 * dt + (ax / n - b[2]) * 1.2 * dt + sx * m * 0.3 * dt;
        b[3] += (cy / n) * 0.6 * dt + (ay / n - b[3]) * 1.2 * dt + sy * m * 0.3 * dt;
      }
      // Soft walls steer the flock back into view.
      const margin = 0.15;
      if (b[0] < w * margin) b[2] += maxV * 2 * dt;
      if (b[0] > w * (1 - margin)) b[2] -= maxV * 2 * dt;
      if (b[1] < h * margin) b[3] += maxV * 2 * dt;
      if (b[1] > h * (1 - margin)) b[3] -= maxV * 2 * dt;
      final sp = sqrt(b[2] * b[2] + b[3] * b[3]);
      final target = sp.clamp(maxV * 0.5, maxV);
      if (sp > 0) {
        b[2] *= target / sp;
        b[3] *= target / sp;
      }
    }
    for (final b in _b) {
      b[0] = (b[0] + b[2] * dt).clamp(0, w - 0.01);
      b[1] = (b[1] + b[3] * dt).clamp(0, h - 0.01);
    }
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final n = p['count'].round().clamp(4, 30);
    while (_b.length < n) {
      final a = _rnd.nextDouble() * 2 * pi;
      _b.add([_rnd.nextDouble() * w, _rnd.nextDouble() * h, cos(a) * 3, sin(a) * 3]);
    }
    if (_b.length > n) _b.removeRange(n, _b.length);
    for (var i = _clock.advance(dt); i > 0; i--) {
      _tick();
    }
    _heat.fade(pow(0.3 + p['trails'] * 0.6, dt * 30).toDouble());
    for (final b in _b) {
      _heat.add(b[0], b[1], 0.9);
    }
    for (var i = 0; i < _heat.v.length; i++) {
      final v = _heat.v[i];
      final y = i ~/ w;
      final sky = scaleColor(pal.at(0.15 + 0.2 * y / h), 0.12);
      out.set(i % w, y, v < 0.02 ? sky : maxColor(sky, scaleColor(pal.at(0.6 + v * 0.38), min(1.0, v * 1.3))));
    }
  }
}

class FlowField extends Generator {
  @override
  String get id => 'flowfield';
  @override
  String get name => 'Flow Field';
  @override
  String get defaultPalette => 'aurora';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('count', 'Particles', min: 10, max: 120, defaultValue: 45),
        ParamSpec('speed', 'Speed', defaultValue: 0.45),
        ParamSpec('trails', 'Trails', defaultValue: 0.7),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _FlowField(width, height, Random(seed));
}

class _FlowField extends EffectInstance {
  _FlowField(this.w, this.h, this._rnd)
      : _n = ValueNoise(_rnd),
        _hue = Float64List(w * h),
        _heat = Heat(w, h);

  final int w, h;
  final Random _rnd;
  final ValueNoise _n;
  final Float64List _hue;
  final Heat _heat;
  final _ps = <List<double>>[]; // x y life

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final n = p['count'].round().clamp(10, 120);
    while (_ps.length < n) {
      _ps.add([_rnd.nextDouble() * w, _rnd.nextDouble() * h, 1 + _rnd.nextDouble() * 4]);
    }
    if (_ps.length > n) _ps.removeRange(n, _ps.length);
    final sp = (0.4 + p['speed'] * 2.5) * min(w, h) / 8;
    final s = 2.0 / max(8, min(w, h));
    _heat.fade(pow(0.5 + p['trails'] * 0.47, dt * 30).toDouble());
    for (final q in _ps) {
      final a = _n.at(q[0] * s, q[1] * s, t * 0.08) * 4 * pi;
      q[0] += cos(a) * sp * dt;
      q[1] += sin(a) * sp * dt;
      q[2] -= dt;
      if (q[2] < 0 || q[0] < 0 || q[1] < 0 || q[0] >= w || q[1] >= h) {
        q[0] = _rnd.nextDouble() * w;
        q[1] = _rnd.nextDouble() * h;
        q[2] = 1 + _rnd.nextDouble() * 4;
      }
      _heat.add(q[0], q[1], 0.35);
      final i = q[1].floor().clamp(0, h - 1) * w + q[0].floor().clamp(0, w - 1);
      _hue[i] = a / (4 * pi);
    }
    for (var i = 0; i < _heat.v.length; i++) {
      final v = _heat.v[i];
      out.set(i % w, i ~/ w, v < 0.01 ? 0 : scaleColor(pal.at(_hue[i] + t * 0.02), min(1.0, v * 1.6)));
    }
  }
}

class Floaters extends Generator {
  @override
  String get id => 'floaters';
  @override
  String get name => 'Floating Shapes';
  @override
  String get defaultPalette => 'heart';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('shape', 'Shape', min: 0, max: 4, defaultValue: 0),
        ParamSpec('count', 'Count', min: 2, max: 16, defaultValue: 6),
        ParamSpec('direction', 'Rise / fall', min: -1, max: 1, defaultValue: 1),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Floaters(width, height, Random(seed));
}

class _Floaters extends EffectInstance {
  _Floaters(this.w, this.h, this._rnd);

  // 5x5 stamps: heart, star, petal, snowflake, note.
  static const _shapes = [
    ['.#.#.', '#####', '#####', '.###.', '..#..'],
    ['..#..', '.###.', '#####', '.###.', '.#.#.'],
    ['.##..', '####.', '.####', '..##.', '.....'],
    ['#.#.#', '.###.', '##.##', '.###.', '#.#.#'],
    ['..##.', '..#.#', '..#..', '###..', '###..'],
  ];
  static const _small = [
    ['#.#', '###', '.#.'],
    ['.#.', '###', '#.#'],
    ['##.', '.##', '...'],
    ['#.#', '.#.', '#.#'],
    ['.#.', '.#.', '##.'],
  ];

  final int w, h;
  final Random _rnd;
  final _f = <List<double>>[]; // x y speed phase hue

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final shape = p['shape'].round().clamp(0, 4);
    final dir = p['direction'];
    final n = p['count'].round().clamp(2, 16);
    final stamp = min(w, h) >= 12 ? _shapes[shape] : _small[shape];
    final sz = stamp.length;
    while (_f.length < n) {
      _f.add([_rnd.nextDouble() * w, _rnd.nextDouble() * (h + sz * 2) - sz, 0.5 + _rnd.nextDouble(), _rnd.nextDouble() * 6, _rnd.nextDouble()]);
    }
    if (_f.length > n) _f.removeRange(n, _f.length);
    out.fill(scaleColor(pal.at(0.15), 0.05));
    for (final f in _f) {
      final vy = -dir * h * 0.12 * f[2];
      f[1] += vy * dt;
      if (dir.abs() < 0.05) f[1] += sin(t + f[3]) * dt;
      if (f[1] < -sz - 1 || f[1] > h + sz + 1) {
        f[1] = vy < 0 ? h + sz.toDouble() : -sz.toDouble();
        f[0] = _rnd.nextDouble() * w;
      }
      final x0 = (f[0] + sin(t * 1.2 + f[3]) * min(w, h) * 0.08 - sz / 2).round();
      final y0 = (f[1] - sz / 2).round();
      final c = scaleColor(pal.at(0.55 + f[4] * 0.43), 0.6 + 0.4 * sin(t * 2 + f[3]).abs());
      for (var y = 0; y < sz; y++) {
        for (var x = 0; x < sz; x++) {
          if (stamp[y][x] == '#') out.set(x0 + x, y0 + y, c);
        }
      }
    }
  }
}

class Comets extends Generator {
  @override
  String get id => 'comets';
  @override
  String get name => 'Comets';
  @override
  String get defaultPalette => 'fireice';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('count', 'Comets', min: 1, max: 6, defaultValue: 3),
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
        ParamSpec('tail', 'Tail', defaultValue: 0.7),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Comets(width, height, Random(seed));
}

class _Comets extends EffectInstance {
  _Comets(int w, int h, Random r)
      : _heat = Heat(w, h),
        _hue = Float64List(w * h),
        _c = List.generate(6, (_) => List.generate(5, (_) => r.nextDouble()));

  final Heat _heat;
  final Float64List _hue;
  final List<List<double>> _c; // freqx freqy phase hue -
  double _time = 0;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = _heat.w, h = _heat.h;
    final n = p['count'].round().clamp(1, 6);
    _heat.fade(pow(0.5 + p['tail'] * 0.45, dt * 30).toDouble());
    const sub = 6;
    for (var s = 0; s < sub; s++) {
      _time += dt / sub * (0.3 + p['speed'] * 1.4);
      for (var i = 0; i < n; i++) {
        final c = _c[i];
        final x = w / 2 + (w / 2 - 0.6) * sin(_time * (0.9 + c[0] * 0.8) + c[2] * 6);
        final y = h / 2 + (h / 2 - 0.6) * sin(_time * (0.7 + c[1] * 0.9) + c[2] * 3);
        _heat.add(x, y, 0.4);
        final idx = y.floor().clamp(0, h - 1) * w + x.floor().clamp(0, w - 1);
        _hue[idx] = 0.2 + c[3] * 0.65;
      }
    }
    for (var i = 0; i < _heat.v.length; i++) {
      final v = _heat.v[i];
      out.set(i % w, i ~/ w, v < 0.01 ? 0 : mixColor(scaleColor(pal.at(_hue[i]), v * 1.5), 0xFFFFFF, clamp01((v - 0.75) * 3)));
    }
  }
}

class Spirograph extends Generator {
  @override
  String get id => 'spiro';
  @override
  String get name => 'Spirograph';
  @override
  String get defaultPalette => 'candy';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.45),
        ParamSpec('trail', 'Trail', defaultValue: 0.8),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Spiro(width, height, Random(seed));
}

class _Spiro extends EffectInstance {
  _Spiro(int w, int h, this._rnd) : _buf = Frame(w, h) {
    _pick();
  }

  final Random _rnd;
  final Frame _buf;
  double _k = 0.4, _l = 0.8, _ang = 0, _len = 0;

  void _pick() {
    // Rational gear ratios close the curve after a few laps.
    const ratios = [(2, 5), (3, 7), (3, 8), (2, 7), (4, 9), (3, 10), (5, 12)];
    final (a, b) = ratios[_rnd.nextInt(ratios.length)];
    _k = a / b;
    _l = 0.5 + _rnd.nextDouble() * 0.45;
    _ang = 0;
    _len = 2 * pi * a;
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = _buf.width, h = _buf.height;
    final rx = w / 2 - 0.6, ry = h / 2 - 0.6;
    _buf.fade(pow(0.85 + p['trail'] * 0.14, dt * 30).toDouble());
    final steps = 24;
    final da = dt * (1 + p['speed'] * 6) / steps;
    for (var s = 0; s < steps; s++) {
      _ang += da;
      final k = _k, l = _l;
      // Hypotrochoid, normalised so the curve fits the panel.
      final x = (1 - k) * cos(_ang) + l * k * cos((1 - k) / k * _ang);
      final y = (1 - k) * sin(_ang) - l * k * sin((1 - k) / k * _ang);
      final norm = (1 - k) + l * k;
      splatMax(_buf, w / 2 + x / norm * rx, h / 2 + y / norm * ry, pal.at(_ang / _len));
    }
    if (_ang > _len * 1.3) _pick();
    out.rgb.setAll(0, _buf.rgb);
  }
}

class Wireframe extends Generator {
  @override
  String get id => 'wireframe';
  @override
  String get name => '3D Wireframe';
  @override
  String get defaultPalette => 'cyberpunk';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('shape', 'Shape', min: 0, max: 3, defaultValue: 0),
        ParamSpec('speed', 'Spin', defaultValue: 0.45),
        ParamSpec('size', 'Size', defaultValue: 0.7),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Wireframe();
}

class _Wireframe extends EffectInstance {
  static final _shapes = <(List<List<double>>, List<(int, int)>)>[
    // Cube
    (
      [for (var i = 0; i < 8; i++) [(i & 1) * 2 - 1.0, ((i >> 1) & 1) * 2 - 1.0, ((i >> 2) & 1) * 2 - 1.0]],
      [
        for (var i = 0; i < 8; i++)
          for (final b in [1, 2, 4])
            if (i & b == 0) (i, i | b),
      ],
    ),
    // Octahedron
    (
      [[1.4, 0, 0], [-1.4, 0, 0], [0, 1.4, 0], [0, -1.4, 0], [0, 0, 1.4], [0, 0, -1.4]],
      [(0, 2), (0, 3), (0, 4), (0, 5), (1, 2), (1, 3), (1, 4), (1, 5), (2, 4), (2, 5), (3, 4), (3, 5)],
    ),
    // Tetrahedron
    (
      [[1, 1, 1], [1, -1, -1], [-1, 1, -1], [-1, -1, 1]],
      [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)],
    ),
    // Square pyramid
    (
      [[-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1], [0, -1.3, 0]],
      [(0, 1), (1, 2), (2, 3), (3, 0), (0, 4), (1, 4), (2, 4), (3, 4)],
    ),
  ];

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final (verts, edges) = _shapes[p['shape'].round().clamp(0, 3)];
    final sp = 0.3 + p['speed'] * 2;
    final ax = t * sp * 0.7, ay = t * sp, az = t * sp * 0.3;
    final scale = min(w, h) * (0.18 + p['size'] * 0.14);
    final pts = <(double, double, double)>[];
    for (final v in verts) {
      var x = v[0], y = v[1], z = v[2];
      var ny = y * cos(ax) - z * sin(ax), nz = y * sin(ax) + z * cos(ax);
      y = ny;
      z = nz;
      var nx = x * cos(ay) + z * sin(ay);
      nz = -x * sin(ay) + z * cos(ay);
      x = nx;
      z = nz;
      nx = x * cos(az) - y * sin(az);
      ny = x * sin(az) + y * cos(az);
      final persp = 3.2 / (4 + z);
      pts.add((w / 2 + nx * scale * persp, h / 2 + ny * scale * persp, z));
    }
    out.fill(0);
    for (final (a, b) in edges) {
      final pa = pts[a], pb = pts[b];
      // Depth cue: edges nearer the viewer are brighter.
      final depth = clamp01(0.75 - (pa.$3 + pb.$3) / 2 * 0.3);
      line(out, pa.$1, pa.$2, pb.$1, pb.$2, scaleColor(pal.at(0.15 + depth * 0.6 + t * 0.03), depth), 1.2);
    }
  }
}
