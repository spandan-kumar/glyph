import 'dart:math';

import '../frame.dart';
import '../generator.dart';
import '../palette.dart';

// Field effects: each pixel's colour is a pure function of (x, y, t), so they
// scale to any matrix size and loop cleanly.

class Plasma extends Generator {
  @override
  String get id => 'plasma';
  @override
  String get name => 'Plasma';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.4),
        ParamSpec('scale', 'Scale', defaultValue: 0.4),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Plasma();
}

class _Plasma extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final sp = 0.3 + p['speed'] * 3;
    final s = (0.12 + p['scale'] * 0.6) * 16 / out.width;
    final cx = out.width / 2, cy = out.height / 2;
    final tt = t * sp;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final dx = x - cx, dy = y - cy;
        final v = sin(x * s + tt) +
            sin(y * s * 0.8 - tt * 1.3) +
            sin((x + y) * s * 0.6 + tt * 0.7) +
            sin(sqrt(dx * dx + dy * dy) * s * 1.2 - tt);
        out.set(x, y, pal.at(v / 8 + 0.5 + t * 0.03));
      }
    }
  }
}

class Swirl extends Generator {
  @override
  String get id => 'swirl';
  @override
  String get name => 'Vortex';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.4),
        ParamSpec('arms', 'Arms', min: 1, max: 6, defaultValue: 2),
        ParamSpec('twist', 'Twist', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) => _Swirl();
}

class _Swirl extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final cx = (out.width - 1) / 2, cy = (out.height - 1) / 2;
    final arms = p['arms'].roundToDouble();
    final twist = p['twist'] * 3;
    final sp = 0.1 + p['speed'] * 1.5;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final dx = x - cx, dy = y - cy;
        final a = atan2(dy, dx) / (2 * pi);
        final r = sqrt(dx * dx + dy * dy) / out.width;
        out.set(x, y, pal.at(a * arms + r * twist - t * sp));
      }
    }
  }
}

class Metaballs extends Generator {
  @override
  String get id => 'metaballs';
  @override
  String get name => 'Lava Lamp';
  @override
  String get defaultPalette => 'sunset';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.35),
        ParamSpec('count', 'Blobs', min: 2, max: 6, defaultValue: 4),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Metaballs(Random(seed));
}

class _Metaballs extends EffectInstance {
  _Metaballs(Random r)
      : _phase = List.generate(6, (_) => (r.nextDouble() * 6, r.nextDouble() * 6));

  final List<(double, double)> _phase;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final n = p['count'].round();
    final sp = 0.2 + p['speed'] * 1.5;
    final w = out.width, h = out.height;
    final radius = w * 0.18;
    final balls = [
      for (var i = 0; i < n; i++)
        (
          w / 2 + sin(t * sp * (0.7 + i * 0.13) + _phase[i].$1) * w * 0.38,
          h / 2 + cos(t * sp * (0.5 + i * 0.17) + _phase[i].$2) * h * 0.38,
        ),
    ];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var field = 0.0;
        for (final b in balls) {
          final dx = x - b.$1, dy = y - b.$2;
          field += radius * radius / (dx * dx + dy * dy + 0.5);
        }
        if (field < 0.6) {
          out.set(x, y, scaleColor(pal.at(0.02), field / 0.6 * 0.3));
        } else {
          out.set(x, y, pal.at(min(0.98, 0.25 + field * 0.15)));
        }
      }
    }
  }
}

class Ripples extends Generator {
  @override
  String get id => 'ripples';
  @override
  String get name => 'Raindrops';
  @override
  String get defaultPalette => 'ocean';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('rate', 'Drops', defaultValue: 0.4),
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Ripples(Random(seed));
}

class _Ripples extends EffectInstance {
  _Ripples(this._rnd);

  final Random _rnd;
  final _drops = <(double x, double y, double born, double hue)>[];
  double _nextDrop = 0;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    const life = 2.2;
    final speed = (0.3 + p['speed'] * 1.2) * out.width / 2;
    if (t >= _nextDrop) {
      _drops.add((
        _rnd.nextDouble() * out.width,
        _rnd.nextDouble() * out.height,
        t,
        _rnd.nextDouble(),
      ));
      _nextDrop = t + (1.2 - p['rate']) * (0.3 + _rnd.nextDouble() * 0.8);
    }
    _drops.removeWhere((d) => t - d.$3 > life);

    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        var c = scaleColor(pal.at(0.1), 0.08);
        for (final d in _drops) {
          final age = t - d.$3;
          final dist = sqrt(pow(x - d.$1, 2) + pow(y - d.$2, 2));
          final ring = exp(-pow(dist - age * speed, 2) * 0.9);
          final k = ring * (1 - age / life);
          if (k > 0.02) c = addColors(c, scaleColor(pal.at(d.$4), k));
        }
        out.set(x, y, c);
      }
    }
  }
}
