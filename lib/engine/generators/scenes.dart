import 'dart:math';
import 'dart:typed_data';

import '../frame.dart';
import '../generator.dart';
import '../palette.dart';
import 'util.dart';

// Library-v2 scenes: little landscapes and skies. Positions are fractions of
// the matrix so a 16x16 and a 32x8 show the same picture.

class Sky extends Generator {
  @override
  String get id => 'sky';
  @override
  String get name => 'Day & Night';
  @override
  String get defaultPalette => 'sunset';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Day length', defaultValue: 0.3),
        ParamSpec('start', 'Start time', defaultValue: 0.2),
        ParamSpec('stars', 'Stars', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Sky(width, height, Random(seed));
}

class _Sky extends EffectInstance {
  _Sky(int w, int h, Random r)
      : _stars = Float64List.fromList(
            List.generate(w * h, (_) => r.nextDouble() < 0.09 ? r.nextDouble() : -1)),
        _hills = Float64List.fromList(List.generate(w, (x) {
          final u = x / max(1, w);
          return 0.13 + 0.05 * sin(u * 7 + 1) + 0.03 * sin(u * 17 + 4);
        }));

  final Float64List _stars, _hills;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final cycle = 60 - p['speed'] * 50; // seconds per day
    final ph = (p['start'] + t / cycle) % 1;
    final sunA = ph * 2 * pi;
    final elev = sin(sunA); // 1 at noon, -1 at midnight
    final sx = w * (0.5 - 0.42 * cos(sunA)), sy = h * (0.72 - 0.6 * elev);
    final mx = w * (0.5 + 0.42 * cos(sunA)), my = h * (0.72 + 0.6 * elev);
    final day = smoothstep(-0.05, 0.35, elev);
    final golden = exp(-pow(elev / 0.22, 2).toDouble());
    final night = smoothstep(0.05, -0.25, elev);
    final r = max(0.7, min(w, h) * 0.12);
    for (var y = 0; y < h; y++) {
      final v = (y + 0.5) / h;
      final topDay = 0x1F5FD0, horDay = 0x8FD3FF;
      final topNight = 0x02030C, horNight = 0x0B1030;
      final top = mixColor(mixColor(topNight, topDay, day), scaleColor(pal.at(0.2), 0.8), golden * 0.6);
      final hor = mixColor(mixColor(horNight, horDay, day), pal.at(0.62), golden * 0.9);
      final sky = mixColor(top, hor, v * v);
      for (var x = 0; x < w; x++) {
        var c = sky;
        final s = _stars[y * w + x];
        if (s >= 0 && night > 0) {
          final tw = 0.5 + 0.5 * sin(t * 2 + s * 40);
          c = maxColor(c, scaleColor(0xFFF6E0, night * p['stars'] * (0.25 + 0.6 * tw) * s));
        }
        final ds = sqrt(pow(x + 0.5 - sx, 2) + pow(y + 0.5 - sy, 2));
        final sunC = mixColor(pal.at(0.78), 0xFFF7D6, day);
        c = addColors(c, scaleColor(sunC, clamp01(r * 3 - ds) / (r * 3) * 0.35));
        if (ds < r + 0.5) c = mixColor(c, sunC, clamp01(r + 0.5 - ds));
        final dm = sqrt(pow(x + 0.5 - mx, 2) + pow(y + 0.5 - my, 2));
        if (dm < r * 0.8 + 0.5) {
          c = mixColor(c, scaleColor(0xE8ECFF, 0.4 + 0.6 * night), clamp01(r * 0.8 + 0.5 - dm) * night);
        }
        // Rolling hills in silhouette, lit a little by day.
        if (1 - v < _hills[x]) {
          c = scaleColor(mixColor(0x0A1A10, 0x2E6B2E, day), 0.4 + 0.6 * (day + golden * 0.3).clamp(0, 1));
        }
        out.set(x, y, c);
      }
    }
  }
}

class Clouds extends Generator {
  @override
  String get id => 'clouds';
  @override
  String get name => 'Drifting Clouds';
  @override
  String get defaultPalette => 'ocean';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Wind', defaultValue: 0.35),
        ParamSpec('cover', 'Cover', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Clouds(ValueNoise(Random(seed)));
}

class _Clouds extends EffectInstance {
  _Clouds(this._n);

  final ValueNoise _n;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final s = 2.4 / max(8, min(w, h));
    final drift = t * (0.2 + p['speed'] * 2.2);
    final cover = 0.62 - p['cover'] * 0.3;
    final skyTop = scaleColor(pal.at(0.38), 0.9), skyLow = pal.at(0.62);
    final light = mixColor(pal.at(0.85), 0xFFFFFF, 0.6);
    for (var y = 0; y < h; y++) {
      final v = (y + 0.5) / h;
      final sky = mixColor(skyTop, skyLow, v);
      for (var x = 0; x < w; x++) {
        final nx = (x + drift) * s, ny = y * s * 1.6;
        final d = _n.fbm(nx, ny, t * 0.05, 2);
        final k = smoothstep(cover, cover + 0.18, d);
        // Darker undersides: sample the density a little above.
        final above = _n.fbm(nx, (y - 1.2) * s * 1.6, t * 0.05, 2);
        final shade = 0.62 + 0.38 * smoothstep(cover - 0.05, cover + 0.25, above);
        out.set(x, y, mixColor(sky, scaleColor(light, shade), k));
      }
    }
  }
}

class OceanWaves extends Generator {
  @override
  String get id => 'waves';
  @override
  String get name => 'Ocean Waves';
  @override
  String get defaultPalette => 'ocean';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.4),
        ParamSpec('swell', 'Swell', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Waves();
}

class _Waves extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final sp = 0.4 + p['speed'] * 2.5;
    final amp = 0.03 + p['swell'] * 0.07;
    final skyA = scaleColor(pal.at(0.82), 0.75), skyB = scaleColor(pal.at(0.6), 0.5);
    const layers = 4;
    for (var x = 0; x < w; x++) {
      final u = (x + 0.5) / w * 16 / max(8, min(w, h)) * (w / max(1, h)).clamp(0.5, 4);
      final surf = <double>[];
      for (var l = 0; l < layers; l++) {
        final base = 0.38 + l * 0.15;
        final k = 1.0 + l * 0.35;
        final a = amp * (0.6 + l * 0.35);
        final ph = t * sp * (0.5 + l * 0.25);
        // Sharpened sine: peaky crests and flat troughs like real swell.
        final s = sin(u * 5 * k + ph + l * 1.7);
        final crest = -(pow((s + 1) / 2, 2.2) * 2 - 1);
        surf.add(base + a * crest + a * 0.3 * sin(u * 11 * k - ph * 1.3));
      }
      for (var y = 0; y < h; y++) {
        final v = (y + 0.5) / h;
        var c = mixColor(skyA, skyB, v / 0.4);
        for (var l = 0; l < layers; l++) {
          final d = v - surf[l];
          if (d < -0.5 / h) continue;
          final depth = clamp01(d * 3);
          final water = mixColor(pal.at(0.68 - l * 0.08), scaleColor(pal.at(0.35), 0.5), depth);
          final foam = clamp01(1 - (d * h).abs() * 0.9);
          c = mixColor(water, 0xE6FBFF, foam * (0.5 + 0.12 * l));
        }
        out.set(x, y, c);
      }
    }
  }
}

class WindowRain extends Generator {
  @override
  String get id => 'windowrain';
  @override
  String get name => 'Rainy Window';
  @override
  String get defaultPalette => 'cyberpunk';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('rain', 'Rain', defaultValue: 0.5),
        ParamSpec('lights', 'City lights', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _WindowRain(width, height, Random(seed));
}

class _WindowRain extends EffectInstance {
  _WindowRain(this.w, this.h, this._rnd)
      : _wet = Float64List(w * h),
        _lights = [
          for (var i = 0; i < 9; i++)
            [_rnd.nextDouble(), _rnd.nextDouble(), _rnd.nextDouble(), _rnd.nextDouble()],
        ];

  final int w, h;
  final Random _rnd;
  final Float64List _wet; // static droplets 0..1
  final List<List<double>> _lights; // x y hue phase
  final _runs = <List<double>>[]; // x y speed pause
  final _clock = FixedStep(1 / 30);

  void _tick(Params p) {
    final rain = p['rain'];
    if (_rnd.nextDouble() < 0.1 + rain * 0.5) {
      final i = _rnd.nextInt(w * h);
      _wet[i] = min(1, _wet[i] + 0.5 + _rnd.nextDouble() * 0.5);
    }
    for (var i = 0; i < _wet.length; i++) {
      _wet[i] *= 0.988;
    }
    if (_runs.length < 1 + rain * 4 && _rnd.nextDouble() < 0.02 + rain * 0.05) {
      _runs.add([_rnd.nextDouble() * w, -1, 0, 0]);
    }
    for (final r in _runs) {
      // Drops stick, then lurch downward, wiping a clear trail.
      if (r[3] > 0) {
        r[3] -= 1 / 30;
        continue;
      }
      r[2] = min(h * 1.2, r[2] + h * 0.08);
      r[1] += r[2] / 30;
      r[0] += (_rnd.nextDouble() - 0.5) * 0.15;
      if (_rnd.nextDouble() < 0.05) {
        r[3] = 0.1 + _rnd.nextDouble() * 0.4;
        r[2] = 0;
      }
      final xi = r[0].floor(), yi = r[1].floor();
      if (xi >= 0 && xi < w && yi >= 0 && yi < h) {
        _wet[yi * w + xi] = _rnd.nextDouble() < 0.15 ? 0.6 : 0;
      }
    }
    _runs.removeWhere((r) => r[1] > h + 1);
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    for (var i = _clock.advance(dt); i > 0; i--) {
      _tick(p);
    }
    final m = min(w, h).toDouble();
    final lights = p['lights'];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // Out-of-focus city behind the glass.
        var c = scaleColor(pal.at(0.05), 0.25 + 0.15 * (y / h));
        for (final l in _lights) {
          final lx = l[0] * w, ly = (0.3 + l[1] * 0.7) * h;
          final d = sqrt(pow(x + 0.5 - lx, 2) + pow(y + 0.5 - ly, 2)) / (m * 0.22);
          final k = exp(-d * d) * lights * (0.55 + 0.25 * sin(t * 0.5 + l[3] * 9));
          if (k > 0.01) c = addColors(c, scaleColor(pal.at(0.2 + l[2] * 0.6), k));
        }
        final wet = _wet[y * w + x];
        // Droplets refract a brighter, cooler slice of the scene.
        if (wet > 0.05) c = mixColor(c, addColors(c, scaleColor(pal.at(0.78), 0.4)), wet * 0.8);
        out.set(x, y, c);
      }
    }
    for (final r in _runs) {
      splat(out, r[0], r[1], scaleColor(pal.at(0.85), 0.9), 1.3);
    }
  }
}

class Lightning extends Generator {
  @override
  String get id => 'lightning';
  @override
  String get name => 'Thunderstorm';
  @override
  String get defaultPalette => 'arctic';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('rate', 'Strikes', defaultValue: 0.5),
        ParamSpec('rain', 'Rain', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Lightning(width, height, Random(seed));
}

class _Lightning extends EffectInstance {
  _Lightning(this.w, this.h, this._rnd)
      : _bolt = Float64List(w * h),
        _drops = List.generate(max(2, w * h ~/ 10), (_) => [_rnd.nextDouble() * w, _rnd.nextDouble() * h, 0.6 + _rnd.nextDouble() * 0.4]),
        _noise = ValueNoise(_rnd);

  final int w, h;
  final Random _rnd;
  final Float64List _bolt;
  final List<List<double>> _drops;
  final ValueNoise _noise;
  double _flash = 0, _next = 1.0, _time = 0, _restrike = -1;

  void _strike() {
    var x = w * (0.2 + _rnd.nextDouble() * 0.6), y = 0.0;
    final branches = <(double, double, int)>[];
    void walk(double x0, double y0, int depth) {
      var px = x0, py = y0;
      final stop = depth == 0 ? h.toDouble() : y0 + h * (0.15 + _rnd.nextDouble() * 0.3);
      while (py < stop) {
        final nx = px + (_rnd.nextDouble() - 0.5) * 2.2;
        final ny = py + 0.6 + _rnd.nextDouble() * 0.9;
        final steps = 4;
        for (var s = 0; s <= steps; s++) {
          final ix = (px + (nx - px) * s / steps).floor(), iy = (py + (ny - py) * s / steps).floor();
          if (ix >= 0 && ix < w && iy >= 0 && iy < h) {
            _bolt[iy * w + ix] = depth == 0 ? 1.0 : 0.55;
          }
        }
        px = nx;
        py = ny;
        if (depth < 2 && _rnd.nextDouble() < 0.12) branches.add((px, py, depth + 1));
      }
    }

    walk(x, y, 0);
    for (final b in List.of(branches)) {
      walk(b.$1, b.$2, b.$3);
    }
    _flash = 1;
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    _time += dt;
    if (_time >= _next) {
      _strike();
      _restrike = _rnd.nextDouble() < 0.6 ? _time + 0.12 : -1;
      _next = _time + (5 - p['rate'] * 4.2) * (0.5 + _rnd.nextDouble());
    }
    if (_restrike > 0 && _time >= _restrike) {
      _flash = 0.8;
      for (var i = 0; i < _bolt.length; i++) {
        if (_bolt[i] > 0) _bolt[i] = max(_bolt[i], 0.8);
      }
      _restrike = -1;
    }
    final k = pow(0.04, dt).toDouble();
    _flash *= k;
    for (var i = 0; i < _bolt.length; i++) {
      _bolt[i] *= pow(0.02, dt).toDouble();
    }
    final cloudC = pal.at(0.35);
    for (var y = 0; y < h; y++) {
      final v = (y + 0.5) / h;
      for (var x = 0; x < w; x++) {
        final n = _noise.fbm(x * 0.25, y * 0.35, t * 0.15);
        final cloud = clamp01((0.75 - v) * 1.6) * (0.4 + 0.6 * n);
        var c = scaleColor(cloudC, 0.08 + cloud * (0.45 + _flash * 0.55));
        c = addColors(c, scaleColor(pal.at(0.6), _flash * 0.12));
        final b = _bolt[y * w + x];
        if (b > 0.02) c = maxColor(c, scaleColor(mixColor(pal.at(0.85), 0xFFFFFF, 0.6), b));
        out.set(x, y, c);
      }
    }
    final rain = p['rain'];
    final n = (_drops.length * rain).round();
    for (var i = 0; i < n; i++) {
      final d = _drops[i];
      d[1] += dt * h * 1.6 * d[2];
      d[0] -= dt * w * 0.15;
      if (d[1] > h) {
        d[1] -= h + 1;
        d[0] = _rnd.nextDouble() * (w + 2);
      }
      if (d[0] < 0) d[0] += w;
      splat(out, d[0], d[1], scaleColor(pal.at(0.75), 0.55 * d[2]), 1);
    }
  }
}

class MeteorShower extends Generator {
  @override
  String get id => 'meteors';
  @override
  String get name => 'Meteor Shower';
  @override
  String get defaultPalette => 'galaxy';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('rate', 'Meteors', defaultValue: 0.5),
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
        ParamSpec('tail', 'Tail', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Meteors(width, height, Random(seed));
}

class _Meteors extends EffectInstance {
  _Meteors(this.w, this.h, this._rnd)
      : _heat = Heat(w, h),
        _stars = Float64List.fromList(List.generate(w * h, (_) => _rnd.nextDouble() < 0.08 ? _rnd.nextDouble() : -1));

  final int w, h;
  final Random _rnd;
  final Heat _heat;
  final Float64List _stars;
  final _m = <List<double>>[]; // x y vx vy life hue
  double _next = 0;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    if (t >= _next) {
      final sp = (0.6 + p['speed'] * 1.6) * max(w, h);
      final a = 2.3 + (_rnd.nextDouble() - 0.5) * 0.4; // heading down-left
      _m.add([
        w * (0.3 + _rnd.nextDouble() * 0.9),
        -_rnd.nextDouble() * h * 0.2,
        cos(a) * sp,
        sin(a) * sp,
        0.5 + _rnd.nextDouble() * 0.6,
        _rnd.nextDouble(),
      ]);
      _next = t + (1.6 - p['rate'] * 1.4) * (0.3 + _rnd.nextDouble());
    }
    _heat.fade(pow(0.6 + p['tail'] * 0.37, dt * 30).toDouble());
    final sub = 4;
    for (final m in _m) {
      for (var s = 0; s < sub; s++) {
        m[0] += m[2] * dt / sub;
        m[1] += m[3] * dt / sub;
        _heat.add(m[0], m[1], 0.5 * min(1.0, m[4] * 2));
      }
      m[4] -= dt;
    }
    _m.removeWhere((m) => m[4] <= 0 || m[1] > h + 2 || m[0] < -2);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final v = _heat.v[i];
        var c = scaleColor(pal.at(0.15), 0.06);
        final s = _stars[i];
        if (s >= 0) c = maxColor(c, scaleColor(pal.at(0.95), 0.12 + 0.2 * (0.5 + 0.5 * sin(t * 1.5 + s * 30))));
        if (v > 0.01) c = maxColor(c, scaleColor(pal.at(0.55 + v * 0.44), min(1.0, v * 1.4)));
        out.set(x, y, c);
      }
    }
  }
}

class Orbits extends Generator {
  @override
  String get id => 'orbits';
  @override
  String get name => 'Solar System';
  @override
  String get defaultPalette => 'galaxy';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('planets', 'Planets', min: 1, max: 5, defaultValue: 4),
        ParamSpec('speed', 'Speed', defaultValue: 0.4),
        ParamSpec('tilt', 'Tilt', defaultValue: 0.55),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Orbits(Random(seed));
}

class _Orbits extends EffectInstance {
  _Orbits(Random r) : _ph = List.generate(5, (_) => r.nextDouble() * 2 * pi);

  final List<double> _ph;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final cx = w / 2, cy = h / 2;
    final rx = w * 0.46, ry = h * 0.46;
    final squash = 1 - p['tilt'] * 0.75;
    final n = p['planets'].round().clamp(1, 5);
    final sp = 0.2 + p['speed'] * 1.5;
    final sunR = max(0.6, min(w, h) * 0.11);
    out.fill(0);
    final bodies = <(double, double, double, double, int)>[]; // x y z r color
    for (var i = 0; i < n; i++) {
      final a = 0.32 + 0.68 * (i + 1) / n;
      final omega = sp * pow(a, -1.5) * 0.6;
      final ang = t * omega + _ph[i];
      // Faint orbit path.
      for (var k = 0; k < 48; k++) {
        final q = k / 48 * 2 * pi;
        splat(out, cx + cos(q) * rx * a, cy + sin(q) * ry * a * squash,
            scaleColor(pal.at(0.35), 0.06));
      }
      final x = cx + cos(ang) * rx * a, y = cy + sin(ang) * ry * a * squash;
      final pr = max(0.5, min(w, h) * (0.04 + 0.03 * ((i * 7) % 3)));
      bodies.add((x, y, sin(ang), pr, pal.at(0.25 + i / n * 0.7)));
    }
    void drawBody((double, double, double, double, int) b) {
      disc(out, b.$1, b.$2, b.$4 * (0.85 + 0.15 * b.$3), scaleColor(b.$5, 0.6 + 0.4 * (b.$3 * 0.5 + 0.5)));
    }

    for (final b in bodies.where((b) => b.$3 < 0)) {
      drawBody(b);
    }
    // The sun, with a pulsing corona.
    final corona = 0.5 + 0.15 * sin(t * 2);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final d = sqrt(pow(x + 0.5 - cx, 2) + pow(y + 0.5 - cy, 2));
        final glow = exp(-pow(d / (sunR * 2.2), 2)) * corona;
        if (d < sunR + 0.5) {
          out.set(x, y, mixColor(out.get(x, y), 0xFFE9A0, clamp01(sunR + 0.5 - d)));
        } else if (glow > 0.02) {
          out.set(x, y, addColors(out.get(x, y), scaleColor(0xFF8A1E, glow)));
        }
      }
    }
    for (final b in bodies.where((b) => b.$3 >= 0)) {
      drawBody(b);
    }
  }
}

class BlackHole extends Generator {
  @override
  String get id => 'blackhole';
  @override
  String get name => 'Black Hole';
  @override
  String get defaultPalette => 'ember';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Spin', defaultValue: 0.45),
        ParamSpec('tilt', 'Tilt', defaultValue: 0.6),
        ParamSpec('size', 'Size', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _BlackHole(width, height, Random(seed));
}

class _BlackHole extends EffectInstance {
  _BlackHole(int w, int h, Random r)
      : _stars = Float64List.fromList(List.generate(w * h, (_) => r.nextDouble() < 0.06 ? r.nextDouble() : -1));

  final Float64List _stars;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final m = max(1.0, min(w, h) / 2);
    final cx = w / 2, cy = h / 2;
    final hr = 0.18 + p['size'] * 0.16; // event horizon, in half-sizes
    final squash = 1 + p['tilt'] * 3;
    final spin = t * (0.6 + p['speed'] * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final u = (x + 0.5 - cx) / m, v = (y + 0.5 - cy) / m;
        final r = sqrt(u * u + v * v);
        // Disc seen at an angle: an ellipse in screen space.
        final dr = sqrt(u * u + pow(v * squash, 2));
        final da = atan2(v * squash, u);
        var c = 0;
        final s = _stars[y * w + x];
        if (s >= 0) c = scaleColor(0xFFFFFF, 0.1 + 0.15 * s);
        if (dr > hr * 1.25 && dr < 1.0) {
          final omega = spin / pow(dr, 1.5);
          final swirl = 0.55 + 0.45 * sin(da * 3 - omega + log(dr) * 6);
          final doppler = 0.65 + 0.35 * cos(da); // approaching side is brighter
          final k = (1 - smoothstep(0.45, 1.0, dr)) * swirl * doppler;
          final front = v > 0 || r > hr * 1.4;
          if (front) c = maxColor(c, scaleColor(pal.at(0.55 + 0.4 * (1 - dr)), k));
        }
        // Lensed far side of the disc, bent up over the top of the hole.
        final ring = exp(-pow((r - hr * 1.35) / 0.07, 2).toDouble());
        c = maxColor(c, scaleColor(pal.at(0.9), ring * (0.55 + 0.25 * sin(atan2(v, u) * 2 + spin))));
        if (r < hr) c = 0;
        out.set(x, y, c);
      }
    }
  }
}

class Borealis extends Generator {
  @override
  String get id => 'borealis';
  @override
  String get name => 'Northern Lights';
  @override
  String get defaultPalette => 'aurora';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.35),
        ParamSpec('activity', 'Activity', defaultValue: 0.55),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Borealis(width, height, Random(seed));
}

class _Borealis extends EffectInstance {
  _Borealis(int w, int h, Random r)
      : _n = ValueNoise(r),
        _stars = Float64List.fromList(List.generate(w * h, (_) => r.nextDouble() < 0.07 ? r.nextDouble() : -1)),
        _trees = Float64List.fromList(List.generate(w, (x) => 0.08 + r.nextDouble() * 0.12 + ((x % 3 == 1) ? 0.06 : 0)));

  final ValueNoise _n;
  final Float64List _stars, _trees;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final tt = t * (0.1 + p['speed'] * 0.9);
    final act = p['activity'];
    final aspect = w / max(1, h);
    for (var x = 0; x < w; x++) {
      final u = (x + 0.5) / w * aspect;
      // Ribbon: its lower edge snakes across the sky; rays shoot upward.
      final edge = 0.5 + 0.18 * sin(u * 3.1 + tt * 0.7) + 0.08 * sin(u * 7.3 - tt * 1.3);
      final ray = _n.at(u * 6, tt * 1.5, 0) * (0.5 + act) + _n.at(u * 15, tt * 3, 5) * act * 0.5;
      final height = 0.15 + ray * 0.45;
      for (var y = 0; y < h; y++) {
        final v = (y + 0.5) / h;
        var c = mixColor(0x01020A, 0x061028, v);
        final s = _stars[y * w + x];
        if (s >= 0) c = maxColor(c, scaleColor(0xDDE6FF, 0.15 + 0.25 * (0.5 + 0.5 * sin(t * 1.3 + s * 50))));
        final d = edge - v; // >0 above the edge
        if (d > -1.5 / h && d < height) {
          final k = d < 0 ? clamp01(1 + d * h) : pow(1 - d / height, 1.4).toDouble();
          final col = pal.at(0.35 + clamp01(d / height) * 0.5);
          c = addColors(c, scaleColor(col, k * (0.35 + ray * 0.9)));
        }
        if (1 - v < _trees[x]) c = 0x010302;
        out.set(x, y, c);
      }
    }
  }
}

class Fireflies extends Generator {
  @override
  String get id => 'fireflies';
  @override
  String get name => 'Fireflies';
  @override
  String get defaultPalette => 'forest';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('count', 'Fireflies', min: 2, max: 24, defaultValue: 10),
        ParamSpec('speed', 'Pace', defaultValue: 0.4),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Fireflies(width, height, Random(seed));
}

class _Fireflies extends EffectInstance {
  _Fireflies(this.w, this.h, this._rnd) : _n = ValueNoise(_rnd);

  final int w, h;
  final Random _rnd;
  final ValueNoise _n;
  final _flies = <List<double>>[]; // x y seed period phase

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final count = p['count'].round().clamp(2, 24);
    while (_flies.length < count) {
      _flies.add([_rnd.nextDouble() * w, _rnd.nextDouble() * h * 0.85, _rnd.nextDouble() * 100, 2 + _rnd.nextDouble() * 3, _rnd.nextDouble()]);
    }
    if (_flies.length > count) _flies.removeRange(count, _flies.length);
    final sp = (0.3 + p['speed'] * 1.5) * min(w, h) / 8;
    for (var y = 0; y < h; y++) {
      final v = (y + 0.5) / h;
      for (var x = 0; x < w; x++) {
        var c = scaleColor(pal.at(0.15), 0.04 + 0.08 * v);
        // Grass tips along the bottom.
        final grass = 0.1 + 0.06 * sin(x * 2.3) + 0.04 * sin(x * 5.1 + 1);
        if (1 - v < grass) c = scaleColor(pal.at(0.2), 0.18);
        out.set(x, y, c);
      }
    }
    for (final f in _flies) {
      final a = _n.at(f[2], t * 0.25, 0) * 4 * pi;
      f[0] = (f[0] + cos(a) * sp * dt) % w;
      f[1] = (f[1] + sin(a) * sp * dt * 0.6).clamp(0.5, h * 0.92);
      final ph = (t / f[3] + f[4]) % 1;
      final glow = ph < 0.35 ? sin(ph / 0.35 * pi) : 0.0;
      if (glow > 0.02) {
        splat(out, f[0], f[1], scaleColor(pal.at(0.72), glow), 2.4);
        final halo = scaleColor(pal.at(0.6), glow * 0.3);
        for (final (dx, dy) in const [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)]) {
          splat(out, f[0] + dx, f[1] + dy, halo);
        }
      }
    }
  }
}

class Candle extends Generator {
  @override
  String get id => 'candle';
  @override
  String get name => 'Candlelight';
  @override
  String get defaultPalette => 'ember';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('count', 'Candles', min: 1, max: 3, defaultValue: 1),
        ParamSpec('flicker', 'Flicker', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Candle(ValueNoise(Random(seed)));
}

class _Candle extends EffectInstance {
  _Candle(this._n);

  final ValueNoise _n;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final n = p['count'].round().clamp(1, 3);
    final fl = p['flicker'];
    final slot = w / n;
    final unitW = min(slot, h * 0.6);
    out.fill(0);
    for (var i = 0; i < n; i++) {
      final cx = slot * (i + 0.5);
      final bodyW = max(1.0, unitW * 0.32);
      final bodyTop = h * (0.55 + 0.1 * ((i + 1) % 2));
      final sway = (_n.at(t * 1.5 + i * 10, 0, 0) - 0.5) * fl * unitW * 0.2;
      final gust = 0.8 + 0.4 * _n.at(t * 4 + i * 7, 3, 0) * fl + (1 - fl) * 0.2;
      final fh = h * 0.32 * gust;
      final fw = max(0.7, unitW * 0.16);
      final baseY = bodyTop - 0.4;
      // Warm glow on the surroundings.
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final fx = x + 0.5, fy = y + 0.5;
          final gd = sqrt(pow(fx - cx, 2) + pow(fy - (baseY - fh * 0.4), 2)) / (unitW * 0.9);
          var c = out.get(x, y);
          c = addColors(c, scaleColor(pal.at(0.55), exp(-gd * gd * 2) * 0.22 * gust));
          // Wax body with a lit rim near the flame.
          if (fy > bodyTop && (fx - cx).abs() < bodyW) {
            final lit = 0.35 + 0.4 * clamp01(1 - (fy - bodyTop) / (h * 0.5));
            c = scaleColor(0xF2E4CC, lit * (1 - (fx - cx).abs() / bodyW * 0.35));
          }
          // Teardrop flame, bending with the sway near its tip.
          final q = (baseY - fy) / fh; // 0 at the wick, 1 at the tip
          if (q > -0.12 && q < 1) {
            final off = sway * q * q;
            final width = fw * (q < 0.25 ? sqrt(max(0, q + 0.12) / 0.37) : (1 - q) / 0.75);
            final dx = (fx - cx - off).abs();
            final k = clamp01(width + 0.5 - dx);
            if (k > 0) {
              final heat = clamp01(1 - q * 0.9 - dx / (fw + 0.5) * 0.5);
              c = mixColor(c, pal.at(0.5 + heat * 0.48), k);
            }
          }
          out.set(x, y, c);
        }
      }
    }
  }
}

class Magma extends Generator {
  @override
  String get id => 'magma';
  @override
  String get name => 'Magma Flow';
  @override
  String get defaultPalette => 'lava';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Flow', defaultValue: 0.35),
        ParamSpec('crust', 'Crust', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Magma(ValueNoise(Random(seed)));
}

class _Magma extends EffectInstance {
  _Magma(this._n);

  final ValueNoise _n;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final s = 1.7 / max(8, min(w, h));
    final flow = t * (0.1 + p['speed'] * 0.8);
    final crust = 0.06 + (1 - p['crust']) * 0.12;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final nx = x * s, ny = y * s - flow;
        final warp = _n.at(nx * 0.7, ny * 0.7, t * 0.05) - 0.5;
        final a = _n.fbm(nx + warp * 1.5, ny + warp, t * 0.08, 2);
        final b = _n.fbm(nx * 1.3 + 40, ny * 1.3 + warp, t * 0.08 + 9, 2);
        // Two noise fields cross along thin lines: those are the cracks.
        final crack = 1 - smoothstep(0, crust, (a - b).abs());
        final pulse = 0.85 + 0.15 * sin(t * 1.3 + x * 0.3 + y * 0.2);
        final rock = 0.05 + 0.12 * _n.at(nx * 2, ny * 2, 1);
        out.set(x, y, pal.at(min(0.99, rock + crack * 0.85 * pulse)));
      }
    }
  }
}
