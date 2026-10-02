import 'dart:math';

import '../frame.dart';
import '../generator.dart';
import '../palette.dart';
import 'util.dart';

// Library-v2 pattern effects. Mostly pure functions of (x, y, t) with a little
// seeded state, so they scale to any matrix and never need warm-up.

/// Coordinates normalised so the short side spans -1..1, keeping shapes round
/// on wide matrices.
(double, double) _norm(int x, int y, int w, int h) {
  final m = max(1, min(w, h)) / 2;
  return ((x + 0.5 - w / 2) / m, (y + 0.5 - h / 2) / m);
}

class Kaleidoscope extends Generator {
  @override
  String get id => 'kaleido';
  @override
  String get name => 'Kaleidoscope';
  @override
  String get defaultPalette => 'vaporwave';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.35),
        ParamSpec('segments', 'Mirrors', min: 3, max: 8, defaultValue: 6),
        ParamSpec('zoom', 'Zoom', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Kaleido(Random(seed).nextDouble() * 40);
}

class _Kaleido extends EffectInstance {
  _Kaleido(this._ph);

  final double _ph;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final n = p['segments'].round().clamp(3, 8);
    final wedge = pi / n;
    final tt = t * (0.15 + p['speed'] * 1.4) + _ph;
    final k = 2.2 + p['zoom'] * 5;
    final rot = tt * 0.25;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final (u0, v0) = _norm(x, y, out.width, out.height);
        final r = sqrt(u0 * u0 + v0 * v0);
        var a = atan2(v0, u0) + rot;
        // Fold the angle into one mirrored wedge.
        a = a % (2 * wedge);
        if (a < 0) a += 2 * wedge;
        if (a > wedge) a = 2 * wedge - a;
        final u = r * cos(a) * k, v = r * sin(a) * k;
        final f = sin(u + tt) +
            sin(v * 1.7 - tt * 0.8) +
            sin((u - v) * 0.9 + tt * 1.3) +
            cos(r * k * 0.8 - tt * 1.6);
        final lum = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(f * 1.6), 1.5);
        out.set(x, y, scaleColor(pal.at(f / 8 + r * 0.25 + tt * 0.04), lum));
      }
    }
  }
}

class Voronoi extends Generator {
  @override
  String get id => 'voronoi';
  @override
  String get name => 'Cells';
  @override
  String get defaultPalette => 'tropical';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('count', 'Cells', min: 3, max: 14, defaultValue: 7),
        ParamSpec('speed', 'Speed', defaultValue: 0.35),
        ParamSpec('edges', 'Edges', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Voronoi(Random(seed));
}

class _Voronoi extends EffectInstance {
  _Voronoi(Random r)
      : _seeds = List.generate(
            14, (_) => List.generate(5, (_) => r.nextDouble())); // fx fy px py hue

  final List<List<double>> _seeds;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final n = p['count'].round().clamp(3, 14);
    final sp = 0.1 + p['speed'] * 0.9;
    final pts = [
      for (var i = 0; i < n; i++)
        (
          w * (0.5 + 0.45 * sin(t * sp * (0.5 + _seeds[i][0]) + _seeds[i][2] * 6.3)),
          h * (0.5 + 0.45 * cos(t * sp * (0.4 + _seeds[i][1]) + _seeds[i][3] * 6.3)),
        ),
    ];
    final edge = p['edges'];
    final scale = max(1.0, min(w, h) / 16.0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var d1 = 1e9, d2 = 1e9;
        var best = 0;
        for (var i = 0; i < n; i++) {
          final dx = x + 0.5 - pts[i].$1, dy = y + 0.5 - pts[i].$2;
          final d = sqrt(dx * dx + dy * dy);
          if (d < d1) {
            d2 = d1;
            d1 = d;
            best = i;
          } else if (d < d2) {
            d2 = d;
          }
        }
        final border = smoothstep(0, 1.2 * scale, d2 - d1);
        final shade = 1 - clamp01(d1 / (6 * scale)) * 0.45;
        final c = pal.at(_seeds[best][4] + t * 0.02);
        out.set(x, y, scaleColor(c, shade * (1 - edge * (1 - border))));
      }
    }
  }
}

class Interference extends Generator {
  @override
  String get id => 'interference';
  @override
  String get name => 'Interference';
  @override
  String get defaultPalette => 'ocean';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('sources', 'Sources', min: 2, max: 4, defaultValue: 2),
        ParamSpec('speed', 'Speed', defaultValue: 0.45),
        ParamSpec('wavelength', 'Wavelength', defaultValue: 0.45),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Interference();
}

class _Interference extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final n = p['sources'].round().clamp(2, 4);
    final k = 3 + (1 - p['wavelength']) * 7;
    final om = 1 + p['speed'] * 7;
    final src = [
      for (var i = 0; i < n; i++)
        (
          0.7 * cos(t * 0.23 + i * 2 * pi / n),
          0.7 * sin(t * 0.31 + i * 2 * pi / n),
        ),
    ];
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final (u, v) = _norm(x, y, out.width, out.height);
        var s = 0.0;
        for (final c in src) {
          final d = sqrt(pow(u - c.$1, 2) + pow(v - c.$2, 2));
          s += sin(d * k - t * om);
        }
        s /= n;
        out.set(x, y, scaleColor(pal.at(0.45 + s * 0.4), 0.12 + 0.88 * pow(0.5 + 0.5 * s, 1.6)));
      }
    }
  }
}

class HypnoRings extends Generator {
  @override
  String get id => 'rings';
  @override
  String get name => 'Hypnotic Rings';
  @override
  String get defaultPalette => 'twilight';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.4),
        ParamSpec('density', 'Density', defaultValue: 0.5),
        ParamSpec('twist', 'Spiral', min: 0, max: 4, defaultValue: 0),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Rings();
}

class _Rings extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final k = 1.2 + p['density'] * 2.4;
    final arms = p['twist'].round();
    final sp = 0.2 + p['speed'] * 1.6;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final (u, v) = _norm(x, y, out.width, out.height);
        final r = sqrt(u * u + v * v);
        final a = atan2(v, u) / (2 * pi);
        final ph = r * k + a * arms - t * sp;
        final f = ph - ph.floorToDouble();
        // Hard-edged stripes, softened just enough to not shimmer.
        final band = clamp01(0.5 + 1.6 * cos(2 * pi * f));
        final c = pal.at(ph.floorToDouble() * 0.13 + t * 0.03);
        out.set(x, y, scaleColor(c, 0.08 + 0.92 * band));
      }
    }
  }
}

class OpArt extends Generator {
  @override
  String get id => 'opart';
  @override
  String get name => 'Op-Art Warp';
  @override
  String get defaultPalette => 'mono';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.4),
        ParamSpec('size', 'Squares', defaultValue: 0.5),
        ParamSpec('warp', 'Warp', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _OpArt();
}

class _OpArt extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final k = 3 + (1 - p['size']) * 5;
    final warp = p['warp'] * 0.6;
    final tt = t * (0.2 + p['speed'] * 1.5);
    final ca = pal.at(0.98), cb = pal.at(0.02 + 0.3 * (0.5 + 0.5 * sin(tt * 0.3)));
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final (u0, v0) = _norm(x, y, out.width, out.height);
        final r = sqrt(u0 * u0 + v0 * v0);
        // A bulge that breathes in and out, like a lens over the board.
        final bulge = 1 + warp * sin(tt) * exp(-r * r * 1.5);
        final u = u0 * bulge + warp * 0.3 * sin(v0 * 3 + tt);
        final v = v0 * bulge + warp * 0.3 * sin(u0 * 3 - tt * 0.8);
        final s = sin(u * k + tt * 0.5) * sin(v * k);
        final m = clamp01(0.5 + s * 3);
        out.set(x, y, mixColor(cb, ca, m));
      }
    }
  }
}

class Silk extends Generator {
  @override
  String get id => 'silk';
  @override
  String get name => 'Liquid Silk';
  @override
  String get defaultPalette => 'royal';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.35),
        ParamSpec('scale', 'Scale', defaultValue: 0.45),
        ParamSpec('detail', 'Detail', min: 2, max: 5, defaultValue: 4),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Silk(Random(seed).nextDouble() * 30);
}

class _Silk extends EffectInstance {
  _Silk(this._ph);

  final double _ph;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final s = 1.2 + p['scale'] * 2.5;
    final iters = p['detail'].round().clamp(2, 5);
    final tt = t * (0.15 + p['speed'] * 1.2) + _ph;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final (u0, v0) = _norm(x, y, out.width, out.height);
        var u = u0 * s, v = v0 * s;
        // Iterated sine domain warp: each pass folds the field further.
        for (var i = 1; i <= iters; i++) {
          final nu = u + 0.6 / i * sin(i * v + tt + 0.3 * i);
          final nv = v + 0.6 / i * cos(i * u - tt * 0.8 + 0.5 * i);
          u = nu;
          v = nv;
        }
        final f = 0.5 + 0.25 * (sin(u) + cos(v));
        out.set(x, y, scaleColor(pal.at(f + tt * 0.02), 0.3 + 0.7 * f));
      }
    }
  }
}

class Lattice extends Generator {
  @override
  String get id => 'lattice';
  @override
  String get name => 'Pulse Lattice';
  @override
  String get defaultPalette => 'cyberpunk';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.4),
        ParamSpec('scale', 'Spacing', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Lattice();
}

class _Lattice extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final tt = t * (0.2 + p['speed'] * 1.5);
    final k = 2 + (1 - p['scale']) * 3;
    final rot = tt * 0.2, cr = cos(rot), sr = sin(rot);
    final zoom = 1 + 0.25 * sin(tt * 0.5);
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final (u0, v0) = _norm(x, y, out.width, out.height);
        final u = (u0 * cr - v0 * sr) * k * zoom, v = (u0 * sr + v0 * cr) * k * zoom;
        final r = sqrt(u0 * u0 + v0 * v0);
        final cell = sin(u) * sin(v);
        final pulse = 0.5 + 0.5 * sin(r * 4 - tt * 3);
        final lum = pow(clamp01(cell.abs()), 1.1) * (0.4 + 0.6 * pulse);
        out.set(x, y, scaleColor(pal.at((cell > 0 ? 0.3 : 0.7) + r * 0.15 + tt * 0.03), lum.toDouble()));
      }
    }
  }
}

class Caustics extends Generator {
  @override
  String get id => 'caustics';
  @override
  String get name => 'Pool Caustics';
  @override
  String get defaultPalette => 'arctic';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.35),
        ParamSpec('scale', 'Scale', defaultValue: 0.5),
        ParamSpec('sharp', 'Sharpness', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Caustics();
}

class _Caustics extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final tt = t * (0.2 + p['speed'] * 1.2);
    final k = 2.5 + p['scale'] * 4;
    final sharp = 2 + p['sharp'] * 8;
    final deep = scaleColor(pal.at(0.3), 0.55);
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final (u0, v0) = _norm(x, y, out.width, out.height);
        // Light focuses where three travelling wave fronts cancel out.
        final u = u0 * k, v = v0 * k;
        final w1 = sin(u * 1.0 + v * 0.6 + tt * 1.3);
        final w2 = sin(u * -0.7 + v * 1.1 - tt * 1.1 + sin(u * 0.5 + tt) * 0.8);
        final w3 = sin(u * 0.3 - v * 1.2 + tt * 0.9 + cos(v * 0.6 - tt) * 0.8);
        final m = 1 - (w1 + w2 + w3).abs() / 3;
        final light = pow(clamp01(m), sharp).toDouble();
        out.set(x, y, mixColor(deep, pal.at(0.75 + 0.2 * light), clamp01(light * 1.4)));
      }
    }
  }
}

class Wash extends Generator {
  @override
  String get id => 'wash';
  @override
  String get name => 'Colour Wash';
  @override
  String get defaultPalette => 'rainbow';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.3),
        ParamSpec('bands', 'Bands', min: 0.25, max: 3, defaultValue: 1),
        ParamSpec('spin', 'Spin', min: -1, max: 1, defaultValue: 0.2),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Wash();
}

class _Wash extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final a = t * p['spin'] * 0.6 + 0.6;
    final ca = cos(a), sa = sin(a);
    final bands = p['bands'];
    final shift = t * (0.03 + p['speed'] * 0.4);
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final (u, v) = _norm(x, y, out.width, out.height);
        out.set(x, y, pal.at((u * ca + v * sa) * 0.25 * bands + shift));
      }
    }
  }
}

class Breathe extends Generator {
  @override
  String get id => 'breathe';
  @override
  String get name => 'Breathe';
  @override
  String get defaultPalette => 'twilight';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('rate', 'Breaths/min', min: 3, max: 30, defaultValue: 6),
        ParamSpec('depth', 'Depth', defaultValue: 0.7),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Breathe();
}

class _Breathe extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final ph = t * p['rate'] / 60;
    // Ease in and out like a real breath: slow at full and empty.
    final b = 0.5 - 0.5 * cos(2 * pi * ph);
    final eased = b * b * (3 - 2 * b);
    final depth = p['depth'];
    final lum = 1 - depth + depth * eased;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final (u, v) = _norm(x, y, out.width, out.height);
        final r = sqrt(u * u + v * v);
        final glow = clamp01(1.15 - r * (0.75 - 0.3 * eased));
        out.set(x, y, scaleColor(pal.at(0.5 + 0.2 * sin(ph * 0.9) + r * 0.12), lum * (0.3 + 0.7 * glow)));
      }
    }
  }
}

class Bokeh extends Generator {
  @override
  String get id => 'bokeh';
  @override
  String get name => 'Bokeh';
  @override
  String get defaultPalette => 'gold';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('count', 'Lights', min: 3, max: 16, defaultValue: 8),
        ParamSpec('size', 'Size', defaultValue: 0.5),
        ParamSpec('speed', 'Drift', defaultValue: 0.3),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Bokeh(Random(seed));
}

class _Bokeh extends EffectInstance {
  _Bokeh(Random r)
      : _orbs = List.generate(16, (_) => List.generate(6, (_) => r.nextDouble()));

  final List<List<double>> _orbs; // x y speedx speedy hue phase

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final n = p['count'].round().clamp(3, 16);
    final m = min(w, h).toDouble();
    final sp = 0.02 + p['speed'] * 0.12;
    out.fill(scaleColor(pal.at(0.08), 0.12));
    for (var i = 0; i < n; i++) {
      final o = _orbs[i];
      final x = ((o[0] + t * sp * (o[2] - 0.5)) % 1) * (w + m * 0.4) - m * 0.2;
      final y = ((o[1] - t * sp * (0.3 + o[3] * 0.7)) % 1) * (h + m * 0.4) - m * 0.2;
      final r = m * (0.08 + p['size'] * 0.16) * (0.6 + o[3] * 0.8);
      final pulse = 0.45 + 0.35 * sin(t * (0.6 + o[5]) + o[5] * 9);
      final c = scaleColor(pal.at(0.45 + o[4] * 0.5), pulse);
      for (var py = (y - r - 1).floor(); py <= (y + r + 1).ceil(); py++) {
        for (var px = (x - r - 1).floor(); px <= (x + r + 1).ceil(); px++) {
          if (px < 0 || py < 0 || px >= w || py >= h) continue;
          final d = sqrt(pow(px + 0.5 - x, 2) + pow(py + 0.5 - y, 2));
          // Lens blur: flat disc with a slightly brighter rim.
          final a = clamp01(r + 0.6 - d) * (0.75 + 0.25 * smoothstep(r * 0.4, r, d));
          if (a > 0) out.set(px, py, addColors(out.get(px, py), scaleColor(c, a)));
        }
      }
    }
  }
}

class RetroGrid extends Generator {
  @override
  String get id => 'retrogrid';
  @override
  String get name => 'Retro Horizon';
  @override
  String get defaultPalette => 'synthwave';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.45),
        ParamSpec('sun', 'Sun', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _RetroGrid();
}

class _RetroGrid extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final horizon = h * 0.56;
    final travel = t * (0.4 + p['speed'] * 2.5);
    final sunR = min(w, h) * (0.18 + p['sun'] * 0.2);
    final scx = w / 2, scy = horizon - sunR * 0.15;
    final gridC = pal.at(0.76);
    for (var y = 0; y < h; y++) {
      final fy = y + 0.5;
      for (var x = 0; x < w; x++) {
        final fx = x + 0.5;
        int c;
        if (fy < horizon) {
          final k = fy / horizon;
          c = mixColor(scaleColor(pal.at(0.02), 0.6), scaleColor(pal.at(0.28), 0.8), k * k);
          final d = sqrt(pow(fx - scx, 2) + pow(fy - scy, 2));
          if (d < sunR + 0.5) {
            final sy = (fy - (scy - sunR)) / (2 * sunR);
            // Classic sliced sun: gaps widen towards the bottom.
            final slice = sy > 0.45 && ((sy * 9 - t * 0.6) % 1) < (sy - 0.45) * 1.6;
            if (!slice) {
              c = mixColor(c, mixColor(pal.at(0.6), pal.at(0.44), sy),
                  clamp01(sunR + 0.5 - d));
            }
          } else if (d < sunR * 1.8) {
            c = addColors(c, scaleColor(pal.at(0.5), 0.25 * (1 - (d - sunR) / (sunR * 0.8))));
          }
        } else {
          c = scaleColor(pal.at(0.02), 0.4);
        }
        out.set(x, y, c);
      }
    }
    // Floor grid: rails converge on the vanishing point, cross-bars rush
    // towards the viewer with perspective spacing.
    final span = h - horizon;
    if (span < 1) return;
    void row(double fy, double k) {
      final y0 = (fy - 0.5).floor();
      final wy = fy - 0.5 - y0;
      for (final (yy, wgt) in [(y0, 1 - wy), (y0 + 1, wy)]) {
        if (yy < horizon.floor() || yy >= h) continue;
        for (var x = 0; x < w; x++) {
          out.set(x, yy, mixColor(out.get(x, yy), gridC, clamp01(k * wgt)));
        }
      }
    }

    final phase = travel % 1;
    for (var j = 0; j < 12; j++) {
      final z = j + 1 - phase;
      final depth = 0.9 / z;
      if (depth > 1.05 || depth < 0.18) continue;
      row(horizon + span * depth, clamp01(depth * depth * 1.8));
    }
    final rails = max(2, (w / 8).round());
    for (var k = -rails; k <= rails; k++) {
      final bx = w / 2 + k * w / (rails * 0.9);
      for (var y = horizon.ceil(); y < h; y++) {
        final d = (y + 0.5 - horizon) / span;
        final x = w / 2 + (bx - w / 2) * d;
        final xi = (x - 0.5).floor();
        final wx = x - 0.5 - xi;
        for (final (xx, wgt) in [(xi, 1 - wx), (xi + 1, wx)]) {
          if (xx < 0 || xx >= w) continue;
          out.set(xx, y, mixColor(out.get(xx, y), gridC, clamp01(wgt * d * d * 2)));
        }
      }
    }
  }
}

class Spinner extends Generator {
  @override
  String get id => 'spinner';
  @override
  String get name => 'Loading Spinner';
  @override
  String get defaultPalette => 'neon';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('style', 'Style', min: 0, max: 4, defaultValue: 0),
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Spinner();
}

class _Spinner extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final style = p['style'].round().clamp(0, 4);
    final sp = 0.4 + p['speed'] * 2;
    final tt = t * sp;
    final cx = w / 2, cy = h / 2;
    final m = min(w, h) / 2;
    final R = max(0.8, m * 0.68);
    out.fill(0);
    switch (style) {
      case 0: // arc that grows, shrinks and chases itself
        final head = tt * 2 * pi * 0.6;
        final len = pi * (0.25 + 0.65 * (0.5 + 0.5 * sin(tt * 2.1)));
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
            final d = sqrt(dx * dx + dy * dy);
            final ring = clamp01(1.2 - (d - R).abs() * 1.4 / max(1, m / 8));
            if (ring <= 0) continue;
            var back = (head - atan2(dy, dx)) % (2 * pi);
            if (back < 0) back += 2 * pi;
            if (back < len) {
              out.set(x, y, scaleColor(pal.at(back / len * 0.5 + tt * 0.05), ring * (1 - back / len * 0.5)));
            } else {
              out.set(x, y, scaleColor(pal.at(0.5), ring * 0.08));
            }
          }
        }
      case 1: // ring of dots with a comet tail
        const n = 8;
        for (var i = 0; i < n; i++) {
          final a = i / n * 2 * pi;
          var lag = (tt * n - i) % n;
          if (lag < 0) lag += n;
          final k = max(0.12, 1 - lag / (n * 0.6));
          disc(out, cx + cos(a) * R, cy + sin(a) * R, max(0.5, m * 0.14),
              scaleColor(pal.at(i / n), k));
        }
      case 2: // three bouncing dots
        for (var i = 0; i < 3; i++) {
          final ph = (tt * 1.4 - i * 0.18) % 1;
          final hop = ph < 0.5 ? sin(ph * 2 * pi) : 0.0;
          disc(out, cx + (i - 1) * R * 0.75, cy + R * 0.3 - hop * R * 0.7,
              max(0.5, m * 0.17), pal.at(0.2 + i * 0.3));
        }
      case 3: // expanding pulse rings
        for (var k = 0; k < 3; k++) {
          final ph = (tt * 0.7 + k / 3) % 1;
          final rr = ph * m * 1.05;
          for (var y = 0; y < h; y++) {
            for (var x = 0; x < w; x++) {
              final d = sqrt(pow(x + 0.5 - cx, 2) + pow(y + 0.5 - cy, 2));
              final a = clamp01(1 - (d - rr).abs() * 1.3) * (1 - ph);
              if (a > 0) out.set(x, y, maxColor(out.get(x, y), scaleColor(pal.at(ph), a)));
            }
          }
        }
        disc(out, cx, cy, max(0.5, m * 0.15), pal.at(0.1));
      default: // progress bar with a shimmer, filling and resetting
        final prog = (tt * 0.35) % 1.2;
        final bh = max(1.0, h * 0.2);
        final top = cy - bh / 2;
        final x0 = w * 0.12, x1 = w * 0.88;
        for (var y = 0; y < h; y++) {
          final fy = y + 0.5;
          if (fy < top - 1 || fy > top + bh + 1) continue;
          for (var x = 0; x < w; x++) {
            final fx = x + 0.5;
            final frame = (fy < top || fy > top + bh) && fx > x0 - 1 && fx < x1 + 1;
            if (frame || fx < x0 - 1 || fx > x1 + 1) {
              if (frame) out.set(x, y, scaleColor(pal.at(0.5), 0.3));
              continue;
            }
            final u = (fx - x0) / (x1 - x0);
            if (u <= min(1, prog)) {
              final shimmer = 0.7 + 0.3 * sin(u * 12 - tt * 6);
              out.set(x, y, scaleColor(pal.at(u * 0.6), shimmer));
            } else {
              out.set(x, y, scaleColor(pal.at(0.5), 0.06));
            }
          }
        }
    }
  }
}

class Radar extends Generator {
  @override
  String get id => 'radar';
  @override
  String get name => 'Radar Sweep';
  @override
  String get defaultPalette => 'matrix';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.4),
        ParamSpec('blips', 'Blips', min: 0, max: 10, defaultValue: 5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Radar(Random(seed));
}

class _Radar extends EffectInstance {
  _Radar(this._rnd);

  final Random _rnd;
  final _blips = <List<double>>[]; // angle radius brightness life
  double _last = 0;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final cx = w / 2, cy = h / 2;
    final m = max(1.0, min(w, h) / 2);
    final rev = 0.25 + p['speed'] * 1.0;
    final beam = (t * rev * 2 * pi) % (2 * pi);
    final want = p['blips'].round();
    while (_blips.length < want) {
      _blips.add([_rnd.nextDouble() * 2 * pi, 0.2 + _rnd.nextDouble() * 0.7, 0, 3 + _rnd.nextDouble() * 6]);
    }
    if (_blips.length > want) _blips.removeRange(want, _blips.length);
    for (final b in _blips) {
      // Light up as the beam passes over, then fade.
      var since = (beam - b[0]) % (2 * pi);
      if (since < 0) since += 2 * pi;
      var before = (_last - b[0]) % (2 * pi);
      if (before < 0) before += 2 * pi;
      if (since < before) b[2] = 1;
      b[2] = max(0, b[2] - dt * 0.7);
      b[3] -= dt;
      if (b[3] < 0) {
        b[0] = _rnd.nextDouble() * 2 * pi;
        b[1] = 0.2 + _rnd.nextDouble() * 0.7;
        b[3] = 3 + _rnd.nextDouble() * 6;
      }
    }
    _last = beam;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        final r = sqrt(dx * dx + dy * dy) / m;
        var behind = (beam - atan2(dy, dx)) % (2 * pi);
        if (behind < 0) behind += 2 * pi;
        final trail = r <= 1.05 ? exp(-behind * 2.2) : 0.0;
        final rings = r <= 1.05 && ((r * 3 + 0.5) % 1 - 0.5).abs() * m < 0.3 ? 0.12 : 0.0;
        final cross = (dx.abs() < 0.5 || dy.abs() < 0.5) && r <= 1 ? 0.08 : 0.0;
        final k = max(trail * 0.85, max(rings, cross)) + 0.02 * (r <= 1 ? 1 : 0);
        out.set(x, y, scaleColor(pal.at(0.6 + trail * 0.3), k));
      }
    }
    for (final b in _blips) {
      if (b[2] > 0.02) {
        splat(out, cx + cos(b[0]) * b[1] * m, cy + sin(b[0]) * b[1] * m,
            scaleColor(pal.at(0.97), b[2]), 1.5);
      }
    }
  }
}

class Disco extends Generator {
  @override
  String get id => 'disco';
  @override
  String get name => 'Disco Ball';
  @override
  String get defaultPalette => 'rainbow';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Spin', defaultValue: 0.4),
        ParamSpec('spots', 'Spots', min: 6, max: 60, defaultValue: 40),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Disco(Random(seed));
}

class _Disco extends EffectInstance {
  _Disco(Random r)
      : _spots = List.generate(60, (_) => [r.nextDouble() * 2 * pi, r.nextDouble() * 2 - 1, r.nextDouble()]);

  final List<List<double>> _spots; // longitude, latitude(-1..1), hue
  Frame? _buf;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final buf = _buf ??= Frame(w, h);
    final n = p['spots'].round().clamp(6, 60);
    final rot = t * (0.2 + p['speed'] * 1.6);
    // Short smear so spots read as sweeping light rather than dots.
    buf.fade(pow(0.5, dt * 30).toDouble());
    for (var i = 0; i < n; i++) {
      final s = _spots[i];
      final lon = s[0] + rot;
      final z = cos(lon);
      if (z < 0) continue; // only the half of the ball facing the wall
      final x = w / 2 + sin(lon) * w * 0.62;
      final y = h / 2 + s[1] * h * 0.55;
      final flash = 0.6 + 0.4 * sin(t * 7 + i * 1.7);
      splat(buf, x, y, scaleColor(pal.at(s[2] + t * 0.05), 0.3 + 0.7 * z * flash), 2.4);
    }
    final bg = scaleColor(pal.at(0.6), 0.03);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        out.set(x, y, maxColor(buf.get(x, y), bg));
      }
    }
  }
}
