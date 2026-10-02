import 'dart:math';
import 'dart:typed_data';

import '../frame.dart';
import '../generator.dart';
import '../palette.dart';

// Second batch of effects. Physics effects step at a fixed rate (like Fire)
// and positions are in pixels, scaled from the matrix size so a 16x16 and a
// 64x32 show the same picture at different resolutions.

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

int _maxColor(int a, int b) =>
    (max((a >> 16) & 0xFF, (b >> 16) & 0xFF) << 16) |
    (max((a >> 8) & 0xFF, (b >> 8) & 0xFF) << 8) |
    max(a & 0xFF, b & 0xFF);

int _mix(int a, int b, double t) {
  int ch(int s) {
    final x = (a >> s) & 0xFF, y = (b >> s) & 0xFF;
    return (x + (y - x) * t).round();
  }

  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/// Adds [color] at a sub-pixel position spread over the 4 nearest pixels, so
/// slow-moving points glide instead of jumping a whole LED at a time.
void _splat(Frame f, double px, double py, int color, [double gain = 1]) {
  final fx = px - 0.5, fy = py - 0.5;
  final x0 = fx.floor(), y0 = fy.floor();
  final wx = fx - x0, wy = fy - y0;
  void add(int x, int y, double w) {
    if (x < 0 || y < 0 || x >= f.width || y >= f.height || w <= 0.01) return;
    f.set(x, y, addColors(f.get(x, y), scaleColor(color, min(1.0, w * gain))));
  }

  add(x0, y0, (1 - wx) * (1 - wy));
  add(x0 + 1, y0, wx * (1 - wy));
  add(x0, y0 + 1, (1 - wx) * wy);
  add(x0 + 1, y0 + 1, wx * wy);
}

/// Advances [acc] by [dt] and returns how many fixed steps of [step] to run.
/// Clamped so a long pause doesn't trigger a burst of catch-up simulation.
(int, double) _steps(double acc, double dt, double step) {
  acc = min(acc + dt, 0.25);
  final n = (acc / step).floor();
  return (n, acc - n * step);
}

class Aurora extends Generator {
  @override
  String get id => 'aurora';
  @override
  String get name => 'Aurora';
  @override
  String get defaultPalette => 'aurora';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.35),
        ParamSpec('length', 'Curtain', defaultValue: 0.5),
        ParamSpec('shimmer', 'Shimmer', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Aurora(Random(seed).nextDouble() * 50);
}

class _Aurora extends EffectInstance {
  _Aurora(this._phase);

  final double _phase;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final tt = t * (0.1 + p['speed'] * 1.0) + _phase;
    final len = 0.15 + p['length'] * 0.7;
    final shimmer = p['shimmer'];
    for (var x = 0; x < w; x++) {
      final u = (x + 0.5) / w;
      // Two curtains: a bright near one and a dim one further back. Each has
      // a wandering lower edge, slow folds and fast vertical rays.
      final base1 = 0.62 + 0.12 * sin(u * 2.7 + tt * 0.6) +
          0.06 * sin(u * 6.1 - tt * 1.1);
      final base2 = 0.42 + 0.1 * sin(u * 3.4 - tt * 0.45 + 2) +
          0.05 * sin(u * 7.7 + tt * 0.9);
      final fold1 = 0.5 + 0.5 * sin(u * 8 + tt * 1.3 + 1.8 * sin(u * 3.3 - tt * 0.4));
      final fold2 = 0.5 + 0.5 * sin(u * 5.5 - tt * 0.8 + 2.2 * sin(u * 2.1 + tt * 0.3));
      final rays = 1 - shimmer * 0.45 * (0.5 + 0.5 * sin(u * 23 + tt * 5));
      for (var y = 0; y < h; y++) {
        final v = (y + 0.5) / h;
        int curtain(double base, double fold, double gain) {
          final d = base - v; // > 0 above the lower edge
          final k = d < 0 ? exp(-pow(d * h, 2) * 0.6) : exp(-d / len * 1.6);
          final value = 0.42 + min(0.5, max(0.0, d) / len * 0.7);
          return scaleColor(pal.at(value), k * (0.3 + 0.7 * fold) * gain * 1.5);
        }

        out.set(
            x,
            y,
            addColors(curtain(base2, fold2, 0.45),
                curtain(base1, fold1, rays)));
      }
    }
  }
}

/// Seeded 3D value noise with quintic smoothing, in 0..1.
class _ValueNoise {
  _ValueNoise(Random r)
      : _perm = Uint8List(512),
        _vals = Float64List.fromList(List.generate(256, (_) => r.nextDouble())) {
    final p = List.generate(256, (i) => i)..shuffle(r);
    for (var i = 0; i < 512; i++) {
      _perm[i] = p[i & 255];
    }
  }

  final Uint8List _perm;
  final Float64List _vals;

  double _v(int x, int y, int z) =>
      _vals[_perm[_perm[_perm[x & 255] + (y & 255)] + (z & 255)]];

  static double _fade(double f) => f * f * f * (f * (f * 6 - 15) + 10);

  double at(double x, double y, double z) {
    final xi = x.floor(), yi = y.floor(), zi = z.floor();
    final u = _fade(x - xi), v = _fade(y - yi), w = _fade(z - zi);
    double lerp(double a, double b, double t) => a + (b - a) * t;
    final x00 = lerp(_v(xi, yi, zi), _v(xi + 1, yi, zi), u);
    final x10 = lerp(_v(xi, yi + 1, zi), _v(xi + 1, yi + 1, zi), u);
    final x01 = lerp(_v(xi, yi, zi + 1), _v(xi + 1, yi, zi + 1), u);
    final x11 = lerp(_v(xi, yi + 1, zi + 1), _v(xi + 1, yi + 1, zi + 1), u);
    return lerp(lerp(x00, x10, v), lerp(x01, x11, v), w);
  }

  double fbm(double x, double y, double z) =>
      (at(x, y, z) * 0.65 + at(x * 2.03 + 17, y * 2.03 + 31, z * 1.6) * 0.35);
}

class NoiseFlow extends Generator {
  @override
  String get id => 'noise';
  @override
  String get name => 'Noise Flow';
  @override
  String get defaultPalette => 'neon';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.35),
        ParamSpec('scale', 'Scale', defaultValue: 0.45),
        ParamSpec('warp', 'Warp', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _NoiseFlow(_ValueNoise(Random(seed)));
}

class _NoiseFlow extends EffectInstance {
  _NoiseFlow(this._n);

  final _ValueNoise _n;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final s = (0.03 + p['scale'] * 0.2) * 16 / max(out.width, out.height);
    final z = t * (0.05 + p['speed'] * 0.8);
    final warp = p['warp'] * 3.5;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final nx = x * s, ny = y * s;
        // Domain warp: offset the lookup by another noise field.
        final qx = _n.fbm(nx, ny, z) - 0.5;
        final qy = _n.fbm(nx + 5.2, ny + 1.3, z + 7.1) - 0.5;
        final v = _n.fbm(nx + warp * qx, ny + warp * qy, z * 0.7 + 3);
        out.set(x, y, pal.at((v - 0.5) * 1.6 + 0.5 + t * 0.015));
      }
    }
  }
}

class Fireworks extends Generator {
  @override
  String get id => 'fireworks';
  @override
  String get name => 'Fireworks';
  @override
  String get defaultPalette => 'rainbow';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('rate', 'Launches', defaultValue: 0.5),
        ParamSpec('size', 'Burst size', defaultValue: 0.5),
        ParamSpec('trails', 'Trails', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Fireworks(width, height, Random(seed));
}

class _Spark {
  _Spark(this.x, this.y, this.vx, this.vy, this.hue, this.life);

  double x, y, vx, vy, age = 0;
  final double hue, life;
}

class _Fireworks extends EffectInstance {
  _Fireworks(int w, int h, this._rnd) : _buf = Frame(w, h);

  static const _step = 1 / 60;
  final Random _rnd;
  final Frame _buf;
  final _rockets = <_Spark>[];
  final _sparks = <_Spark>[];
  double _acc = 0, _time = 0, _nextLaunch = 0.15;

  double get _g => _buf.height * 1.1;

  void _launch() {
    final w = _buf.width, h = _buf.height;
    final apex = h * (0.15 + _rnd.nextDouble() * 0.3);
    final vy = -sqrt(2 * _g * (h - apex));
    _rockets.add(_Spark(w * (0.2 + _rnd.nextDouble() * 0.6), h.toDouble(),
        (_rnd.nextDouble() - 0.5) * w * 0.15, vy, 0.2 + _rnd.nextDouble() * 0.7, 9));
  }

  void _explode(_Spark r, Params p) {
    final size = p['size'];
    final reach = min(_buf.width, _buf.height) * (0.35 + size * 0.5);
    final count = (14 + size * 46).round();
    final twoTone = _rnd.nextBool();
    for (var i = 0; i < count && _sparks.length < 600; i++) {
      final a = _rnd.nextDouble() * 2 * pi;
      final sp = reach * (0.5 + 0.5 * sqrt(_rnd.nextDouble()));
      _sparks.add(_Spark(
          r.x,
          r.y,
          cos(a) * sp + r.vx * 0.3,
          sin(a) * sp,
          r.hue + (twoTone && i.isOdd ? 0.12 : 0),
          0.7 + _rnd.nextDouble() * 0.8));
    }
  }

  void _tick(Params p) {
    _time += _step;
    if (_time >= _nextLaunch) {
      _launch();
      _nextLaunch =
          _time + (2.4 - p['rate'] * 2.1) * (0.4 + _rnd.nextDouble() * 0.9);
    }
    for (final r in _rockets) {
      r.vy += _g * _step;
      r.x += r.vx * _step;
      r.y += r.vy * _step;
    }
    _rockets.removeWhere((r) {
      if (r.vy < 0) return false;
      _explode(r, p);
      return true;
    });
    final drag = pow(0.15, _step).toDouble();
    for (final s in _sparks) {
      s.vx *= drag;
      s.vy = s.vy * drag + _g * 0.3 * _step;
      s.x += s.vx * _step;
      s.y += s.vy * _step;
      s.age += _step;
    }
    _sparks.removeWhere((s) => s.age >= s.life || s.y > _buf.height + 1);
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final (n, acc) = _steps(_acc, dt, _step);
    _acc = acc;
    for (var i = 0; i < n; i++) {
      _tick(p);
    }
    _buf.fade(pow(0.35 + p['trails'] * 0.5, dt * 30).toDouble());
    for (final r in _rockets) {
      _splat(_buf, r.x, r.y, scaleColor(pal.at(r.hue), 0.35), 1.5);
      _splat(_buf, r.x, r.y, 0x303030);
    }
    for (final s in _sparks) {
      final k = 1 - s.age / s.life;
      // Sparks flicker as they burn out.
      final flicker = k < 0.35 && _rnd.nextDouble() < 0.4 ? 0.3 : 1.0;
      _splat(_buf, s.x, s.y, scaleColor(pal.at(s.hue), k * flicker), 1.4);
    }
    out.rgb.setAll(0, _buf.rgb);
  }
}

class Snowfall extends Generator {
  @override
  String get id => 'snow';
  @override
  String get name => 'Snowfall';
  @override
  String get defaultPalette => 'ice';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('amount', 'Amount', defaultValue: 0.45),
        ParamSpec('wind', 'Wind', min: -1, max: 1, defaultValue: 0.15),
        ParamSpec('melt', 'Melt', defaultValue: 0.4),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Snowfall(width, height, Random(seed));
}

class _Snowfall extends EffectInstance {
  _Snowfall(this.w, this.h, this._rnd) : _pile = Float64List(w);

  static const _step = 1 / 40;
  final int w, h;
  final Random _rnd;
  final Float64List _pile;
  final _flakes = <List<double>>[]; // [x, y, depth, phase]
  double _acc = 0, _time = 0;
  bool _thaw = false;

  List<double> _spawn(double y) => [
        _rnd.nextDouble() * w,
        y,
        _rnd.nextDouble(),
        _rnd.nextDouble() * 2 * pi,
      ];

  void _tick(Params p) {
    _time += _step;
    final target = max(1, (w * h * (0.015 + p['amount'] * 0.11)).round());
    // The first batch is scattered over the screen, later ones start above it.
    final scatter = _flakes.isEmpty;
    while (_flakes.length < target) {
      _flakes.add(_spawn(scatter
          ? _rnd.nextDouble() * h
          : -_rnd.nextDouble() * h * 0.5));
    }
    if (_flakes.length > target) _flakes.removeRange(target, _flakes.length);

    final wind = p['wind'] * w * 0.25;
    for (final f in _flakes) {
      final fall = h * (0.1 + f[2] * 0.18);
      f[0] = (f[0] + (wind + sin(_time * 1.7 + f[3]) * w * 0.03) * _step) % w;
      f[1] += fall * _step;
      final col = min(max(f[0].floor(), 0), w - 1);
      if (f[1] >= h - _pile[col]) {
        if (!_thaw) _pile[col] += 0.6;
        final n = _spawn(-_rnd.nextDouble() * 2);
        f.setAll(0, n);
      }
    }
    // Snow slides off steep steps so the pile stays a smooth drift.
    for (var x = 0; x < w - 1; x++) {
      final d = _pile[x] - _pile[x + 1];
      if (d.abs() > 1.2) {
        final m = d.sign * 0.2;
        _pile[x] -= m;
        _pile[x + 1] += m;
      }
    }
    var total = 0.0;
    final melt = (_thaw ? h * 0.08 : p['melt'] * 0.03) * _step;
    for (var x = 0; x < w; x++) {
      _pile[x] = max(0.0, _pile[x] - melt * (0.6 + _rnd.nextDouble() * 0.8));
      total += _pile[x];
    }
    final avg = total / w;
    if (!_thaw && avg > h * (0.18 + p['amount'] * 0.12)) _thaw = true;
    if (_thaw && avg < 0.15) _thaw = false;
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final (n, acc) = _steps(_acc, dt, _step);
    _acc = acc;
    for (var i = 0; i < n; i++) {
      _tick(p);
    }
    final sky = pal.at(0.3);
    for (var y = 0; y < h; y++) {
      final bg = scaleColor(sky, 0.03 + 0.07 * (y + 0.5) / h);
      for (var x = 0; x < w; x++) {
        final fromBottom = h - 1 - y;
        final fill = _clamp01(_pile[x] - fromBottom);
        final shade = 0.55 + 0.45 * _clamp01((fromBottom + 1) / max(1, _pile[x]));
        out.set(x, y, _mix(bg, scaleColor(pal.at(0.9), shade), fill));
      }
    }
    for (final f in _flakes) {
      final c = scaleColor(pal.at(0.75 + f[2] * 0.24), 0.45 + f[2] * 0.55);
      _splat(out, f[0], f[1], c, 1.3);
    }
  }
}

class BouncingBalls extends Generator {
  @override
  String get id => 'balls';
  @override
  String get name => 'Bouncing Balls';
  @override
  String get defaultPalette => 'rainbow';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('count', 'Balls', min: 1, max: 8, defaultValue: 3),
        ParamSpec('gravity', 'Gravity', defaultValue: 0.4),
        ParamSpec('trails', 'Trails', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Balls(width, height, Random(seed));
}

class _Balls extends EffectInstance {
  _Balls(int w, int h, this._rnd) : _buf = Frame(w, h);

  static const _step = 1 / 120;
  final Random _rnd;
  final Frame _buf;
  final _balls = <List<double>>[]; // [x, y, vx, vy]
  double _acc = 0;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = _buf.width.toDouble(), h = _buf.height.toDouble();
    final r = max(0.6, min(w, h) * 0.07);
    final g = h * (0.8 + p['gravity'] * 5);
    final count = min(max(p['count'].round(), 1), 8);
    while (_balls.length < count) {
      _balls.add([
        r + _rnd.nextDouble() * max(0, w - 2 * r),
        r + _rnd.nextDouble() * h * 0.4,
        (_rnd.nextDouble() * 2 - 1) * w * 0.5,
        0,
      ]);
    }
    if (_balls.length > count) _balls.removeRange(count, _balls.length);

    final (n, acc) = _steps(_acc, dt, _step);
    _acc = acc;
    for (var s = 0; s < n; s++) {
      for (final b in _balls) {
        b[3] += g * _step;
        b[0] += b[2] * _step;
        b[1] += b[3] * _step;
        if (b[1] > h - r) {
          b[1] = h - r;
          b[3] = -b[3] * 0.86;
          // Kick tired balls back up so the show never stops.
          if (b[3].abs() < sqrt(2 * g * h * 0.25)) {
            b[3] = -sqrt(2 * g * h * (0.55 + _rnd.nextDouble() * 0.4));
          }
        }
        if (b[1] < r) b[3] = b[3].abs();
        if (b[0] < r) b[2] = b[2].abs();
        if (b[0] > w - r) b[2] = -b[2].abs();
      }
    }

    _buf.fade(pow(0.25 + p['trails'] * 0.6, dt * 30).toDouble());
    for (var i = 0; i < _balls.length; i++) {
      final b = _balls[i];
      final c = pal.at(i / count);
      for (var y = (b[1] - r - 1).floor(); y <= (b[1] + r + 1).ceil(); y++) {
        for (var x = (b[0] - r - 1).floor(); x <= (b[0] + r + 1).ceil(); x++) {
          if (x < 0 || y < 0 || x >= _buf.width || y >= _buf.height) continue;
          final d = sqrt(pow(x + 0.5 - b[0], 2) + pow(y + 0.5 - b[1], 2));
          final a = _clamp01(r + 0.5 - d);
          if (a > 0) _buf.set(x, y, _maxColor(_buf.get(x, y), scaleColor(c, a)));
        }
      }
    }
    out.rgb.setAll(0, _buf.rgb);
  }
}

class Helix extends Generator {
  @override
  String get id => 'helix';
  @override
  String get name => 'DNA Helix';
  @override
  String get defaultPalette => 'neon';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.4),
        ParamSpec('twist', 'Twist', defaultValue: 0.4),
        ParamSpec('rungs', 'Rungs', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Helix();
}

class _Helix extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    // The helix runs along the longer side of the matrix.
    final vertical = out.height >= out.width;
    final len = vertical ? out.height : out.width;
    final across = vertical ? out.width : out.height;
    final freq = 2 * pi * (0.5 + p['twist'] * 1.2) / len;
    final amp = max(0.5, across * 0.32);
    final mid = across / 2;
    final spacing = max(2.0, len / 16 * 2.5);
    final rungs = p['rungs'];
    final spin = t * (0.5 + p['speed'] * 5);
    for (var a = 0; a < len; a++) {
      final ph = (a + 0.5) * freq + spin;
      final pos1 = mid + amp * sin(ph), pos2 = mid - amp * sin(ph);
      final front1 = cos(ph) >= 0;
      final rp = (a + 0.5) / spacing;
      final rung = _clamp01(1 - (rp - rp.roundToDouble()).abs() * spacing) * rungs;
      final c1 = pal.at(0.08 + a / len * 0.2), c2 = pal.at(0.55 + a / len * 0.2);
      final depth = 0.5 + 0.5 * cos(ph).abs();
      // Strands cross several pixels per row where they're steep; widen them
      // there so they stay continuous lines.
      final slope = amp * freq * cos(ph);
      final norm = sqrt(1 + slope * slope);
      for (var c = 0; c < across; c++) {
        final cc = c + 0.5;
        var col = 0;
        final lo = min(pos1, pos2), hi = max(pos1, pos2);
        if (rung > 0 && cc > lo - 0.5 && cc < hi + 0.5) {
          final f = hi - lo < 0.01 ? 0.5 : _clamp01((cc - pos1) / (pos2 - pos1));
          col = scaleColor(_mix(c1, c2, f), rung * 0.45);
        }
        final i1 = _clamp01(1.1 - (cc - pos1).abs() / norm);
        final i2 = _clamp01(1.1 - (cc - pos2).abs() / norm);
        final s1 = scaleColor(c1, front1 ? 1 : 1 - depth * 0.7);
        final s2 = scaleColor(c2, front1 ? 1 - depth * 0.7 : 1);
        // Paint the back strand first so the front one covers it.
        if (front1) {
          col = _mix(_mix(col, s2, i2), s1, i1);
        } else {
          col = _mix(_mix(col, s1, i1), s2, i2);
        }
        if (vertical) {
          out.set(c, a, col);
        } else {
          out.set(a, c, col);
        }
      }
    }
  }
}

class Galaxy extends Generator {
  @override
  String get id => 'galaxy';
  @override
  String get name => 'Spiral Galaxy';
  @override
  String get defaultPalette => 'galaxy';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.3),
        ParamSpec('arms', 'Arms', min: 1, max: 4, defaultValue: 2),
        ParamSpec('twist', 'Twist', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Galaxy(width, height, Random(seed));
}

class _Galaxy extends EffectInstance {
  _Galaxy(int w, int h, Random r)
      : _stars = Float64List.fromList(List.generate(
            w * h, (_) => r.nextDouble() < 0.07 ? r.nextDouble() * 2 * pi : -1.0));

  final Float64List _stars; // twinkle phase per pixel, -1 for none

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final cx = w / 2, cy = h / 2;
    final radius = max(1.0, sqrt(w * h.toDouble()) / 2);
    final arms = p['arms'].roundToDouble();
    final twist = 1 + p['twist'] * 6;
    final rot = t * (0.1 + p['speed'] * 1.2);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x + 0.5 - cx, dy = (y + 0.5 - cy) * 1.15;
        final r = sqrt(dx * dx + dy * dy) / radius;
        final a = atan2(dy, dx);
        final spiral = cos(arms * (a - rot) - twist * log(r + 0.08));
        final arm = pow(0.5 + 0.5 * spiral, 2).toDouble() * exp(-r * 1.5);
        final core = exp(-r * r * 22);
        final glow = exp(-r * 3) * 0.12;
        final k = min(1.0, arm * 2.2 + core * 1.1 + glow);
        var c = scaleColor(pal.at(_clamp01(0.95 - r * 0.75) * 0.98), k);
        final s = _stars[y * w + x];
        if (s >= 0 && k < 0.5) {
          final tw = 0.15 + 0.35 * (0.5 + 0.5 * sin(t * 2.5 + s * 3));
          c = _maxColor(c, scaleColor(pal.at(0.97), tw));
        }
        out.set(x, y, c);
      }
    }
  }
}

class Oscilloscope extends Generator {
  @override
  String get id => 'scope';
  @override
  String get name => 'Oscilloscope';
  @override
  String get defaultPalette => 'neon';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.45),
        ParamSpec('waves', 'Waves', min: 1, max: 4, defaultValue: 3),
        ParamSpec('amp', 'Amplitude', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Scope(width, height, Random(seed));
}

class _Scope extends EffectInstance {
  _Scope(int w, int h, Random r)
      : _buf = Frame(w, h),
        _ph = List.generate(4, (_) => r.nextDouble() * 2 * pi);

  final Frame _buf;
  final List<double> _ph;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = _buf.width, h = _buf.height;
    final n = min(max(p['waves'].round(), 1), 4);
    final cy = h / 2;
    final sp = 0.4 + p['speed'] * 5;
    _buf.fade(pow(0.3, dt * 30).toDouble());
    for (var i = 0; i < n; i++) {
      final k = 2 * pi * (0.7 + i * 0.55) / w;
      final amp = h * (0.15 + p['amp'] * 0.3) * (0.75 + 0.25 * sin(t * 0.6 + i * 2));
      final omega = sp * (1 + i * 0.37) * (i.isOdd ? -1 : 1);
      final c = pal.at(i / n + 0.1 + t * 0.02);
      for (var x = 0; x < w; x++) {
        final arg = (x + 0.5) * k + t * omega + _ph[i];
        final fy = cy + amp * sin(arg);
        final slope = amp * k * cos(arg);
        final norm = sqrt(1 + slope * slope);
        for (var y = 0; y < h; y++) {
          final d = ((y + 0.5) - fy).abs() / norm;
          final a = _clamp01(1 - d);
          if (a > 0) _buf.set(x, y, _maxColor(_buf.get(x, y), scaleColor(c, a * a)));
        }
      }
    }
    final axis = scaleColor(pal.at(0.5), 0.07);
    for (var y = 0; y < h; y++) {
      final onAxis = (y + 0.5 - cy).abs() < 0.5;
      for (var x = 0; x < w; x++) {
        final c = _buf.get(x, y);
        out.set(x, y, onAxis ? _maxColor(c, axis) : c);
      }
    }
  }
}

class Heartbeat extends Generator {
  @override
  String get id => 'heartbeat';
  @override
  String get name => 'Heartbeat';
  @override
  String get defaultPalette => 'heart';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('bpm', 'BPM', min: 40, max: 180, defaultValue: 72),
        ParamSpec('size', 'Size', defaultValue: 0.6),
        ParamSpec('rings', 'Rings', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Heartbeat();
}

class _Heartbeat extends EffectInstance {
  // Fast attack, slower decay.
  static double _pulse(double x) =>
      x >= 0 ? exp(-x / 0.07) : exp(-pow(x / 0.02, 2).toDouble());

  static bool _inHeart(double x, double y) {
    final q = x * x + y * y - 1;
    return q * q * q - x * x * y * y * y <= 0;
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final beatLen = 60 / max(20.0, p['bpm']);
    final ph = (t / beatLen) % 1;
    // "Lub-dub": a strong beat followed by a weaker one.
    final pulse = min(1.0, _pulse(ph) + _pulse(ph - 1) + 0.6 * _pulse(ph - 0.3));
    final m = min(w, h).toDouble();
    final scale = m * (0.18 + p['size'] * 0.16) * (1 + 0.12 * pulse);
    final cx = w / 2, cy = h / 2 + scale * 0.12;
    const life = 1.4;
    final rings = p['rings'];
    final speed = m * 0.55;
    final heartC = pal.at(0.6 + 0.3 * pulse);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var bg = 0;
        if (rings > 0) {
          final d = sqrt(pow(x + 0.5 - cx, 2) + pow(y + 0.5 - cy, 2));
          final beat = (t / beatLen).floor();
          for (var b = beat; b >= 0 && (t - b * beatLen) < life; b--) {
            final age = t - b * beatLen;
            final rr = scale * 0.9 + age * speed;
            final k = exp(-pow((d - rr) / 0.8, 2)) * (1 - age / life) * rings;
            if (k > 0.01) bg = addColors(bg, scaleColor(pal.at(0.5 + 0.2 * (1 - age / life)), k));
          }
        }
        // 3x3 supersampling gives the heart a smooth edge at 16x16.
        var cover = 0;
        for (var sy = 0; sy < 3; sy++) {
          for (var sx = 0; sx < 3; sx++) {
            final hx = (x + (sx + 0.5) / 3 - cx) / scale;
            final hy = -(y + (sy + 0.5) / 3 - cy) / scale;
            if (_inHeart(hx * 0.9, hy)) cover++;
          }
        }
        final c = scaleColor(heartC, 0.55 + 0.45 * pulse);
        out.set(x, y, _mix(bg, c, cover / 9));
      }
    }
  }
}

class Tunnel extends Generator {
  @override
  String get id => 'tunnel';
  @override
  String get name => 'Tunnel';
  @override
  String get defaultPalette => 'synthwave';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.45),
        ParamSpec('segments', 'Segments', min: 2, max: 10, defaultValue: 4),
        ParamSpec('spin', 'Spin', min: -1, max: 1, defaultValue: 0.3),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Tunnel();
}

class _Tunnel extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final m = max(1.0, min(w, h) / 2);
    // The vanishing point drifts so it feels like flying through a bendy tube.
    final cx = w / 2 + sin(t * 0.7) * w * 0.12;
    final cy = h / 2 + cos(t * 0.53) * h * 0.12;
    final segs = p['segments'].roundToDouble();
    final travel = t * (0.2 + p['speed'] * 2.5);
    final spin = t * p['spin'] * 1.5;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        final r = sqrt(dx * dx + dy * dy) / m + 0.001;
        final a = atan2(dy, dx) + spin;
        final depth = 0.5 / r + travel;
        final s = sin(depth * 2 * pi) * sin(a * segs);
        final check = 0.5 + 0.5 * (2 / (1 + exp(-6 * s)) - 1);
        final fog = pow(_clamp01(r * 1.4), 1.3).toDouble();
        final c = pal.at(depth * 0.25 + check * 0.3);
        out.set(x, y, scaleColor(c, fog * (0.25 + 0.75 * check)));
      }
    }
  }
}
