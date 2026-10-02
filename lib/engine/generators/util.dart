import 'dart:math';
import 'dart:typed_data';

import '../frame.dart';

// Shared helpers for the library-v2 generators.

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

double smoothstep(double a, double b, double x) {
  final t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

int maxColor(int a, int b) =>
    (max((a >> 16) & 0xFF, (b >> 16) & 0xFF) << 16) |
    (max((a >> 8) & 0xFF, (b >> 8) & 0xFF) << 8) |
    max(a & 0xFF, b & 0xFF);

int mixColor(int a, int b, double t) {
  if (t <= 0) return a;
  if (t >= 1) return b;
  int ch(int s) {
    final x = (a >> s) & 0xFF, y = (b >> s) & 0xFF;
    return (x + (y - x) * t).round();
  }

  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

int luma(int c) =>
    (((c >> 16) & 0xFF) * 3 + ((c >> 8) & 0xFF) * 6 + (c & 0xFF)) ~/ 10;

/// Adds [color] at a sub-pixel position spread over the 4 nearest pixels.
void splat(Frame f, double px, double py, int color, [double gain = 1]) {
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

/// Like [splat] but max-blends, so overdrawing a path never washes to white.
void splatMax(Frame f, double px, double py, int color) {
  final fx = px - 0.5, fy = py - 0.5;
  final x0 = fx.floor(), y0 = fy.floor();
  final wx = fx - x0, wy = fy - y0;
  void put(int x, int y, double w) {
    if (x < 0 || y < 0 || x >= f.width || y >= f.height || w <= 0.05) return;
    f.set(x, y, maxColor(f.get(x, y), scaleColor(color, min(1.0, w * 1.6))));
  }

  put(x0, y0, (1 - wx) * (1 - wy));
  put(x0 + 1, y0, wx * (1 - wy));
  put(x0, y0 + 1, (1 - wx) * wy);
  put(x0 + 1, y0 + 1, wx * wy);
}

/// Additive anti-aliased line, used for wireframes and bolts.
void line(Frame f, double x0, double y0, double x1, double y1, int color,
    [double gain = 1]) {
  final len = sqrt(pow(x1 - x0, 2) + pow(y1 - y0, 2));
  final n = max(1, (len * 2).ceil());
  for (var i = 0; i <= n; i++) {
    final t = i / n;
    splat(f, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, color, gain * 0.6);
  }
}

/// Soft round blob drawn with max-blend, radius in pixels.
void disc(Frame f, double cx, double cy, double r, int color,
    {double soft = 1}) {
  for (var y = (cy - r - soft).floor(); y <= (cy + r + soft).ceil(); y++) {
    for (var x = (cx - r - soft).floor(); x <= (cx + r + soft).ceil(); x++) {
      if (x < 0 || y < 0 || x >= f.width || y >= f.height) continue;
      final d = sqrt(pow(x + 0.5 - cx, 2) + pow(y + 0.5 - cy, 2));
      final a = clamp01((r + soft * 0.5 - d) / soft);
      if (a > 0) f.set(x, y, maxColor(f.get(x, y), scaleColor(color, a)));
    }
  }
}

/// Fixed-timestep accumulator; clamps long stalls so physics never bursts.
class FixedStep {
  FixedStep(this.step);

  final double step;
  double _acc = 0;

  int advance(double dt) {
    _acc = min(_acc + dt, 0.25);
    final n = (_acc / step).floor();
    _acc -= n * step;
    return n;
  }
}

/// Seeded 3D value noise with quintic smoothing, in 0..1.
class ValueNoise {
  ValueNoise(Random r)
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

  double fbm(double x, double y, double z, [int octaves = 3]) {
    var sum = 0.0, amp = 0.55, norm = 0.0, f = 1.0;
    for (var i = 0; i < octaves; i++) {
      sum += at(x * f + i * 17.3, y * f + i * 9.1, z * (1 + i * 0.4)) * amp;
      norm += amp;
      amp *= 0.5;
      f *= 2.03;
    }
    return sum / norm;
  }
}

/// A float buffer with fade + palette output, for trail-style effects that
/// must stay recolourable.
class Heat {
  Heat(this.w, this.h) : v = Float64List(w * h);

  final int w, h;
  final Float64List v;

  void fade(double k) {
    for (var i = 0; i < v.length; i++) {
      v[i] *= k;
    }
  }

  void add(double x, double y, double amount) {
    final fx = x - 0.5, fy = y - 0.5;
    final x0 = fx.floor(), y0 = fy.floor();
    final wx = fx - x0, wy = fy - y0;
    void put(int px, int py, double wgt) {
      if (px < 0 || py < 0 || px >= w || py >= h) return;
      final i = py * w + px;
      v[i] = min(1.0, v[i] + amount * wgt);
    }

    put(x0, y0, (1 - wx) * (1 - wy));
    put(x0 + 1, y0, wx * (1 - wy));
    put(x0, y0 + 1, (1 - wx) * wy);
    put(x0 + 1, y0 + 1, wx * wy);
  }
}

/// The base unit of a matrix: 16 px on a 16x16, scales with the short side.
double unit(Frame f) => max(1.0, min(f.width, f.height) / 16);
