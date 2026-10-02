import 'dart:math';
import 'dart:typed_data';

import '../frame.dart';
import '../generator.dart';
import '../palette.dart';

// Stateful effects: they simulate something frame to frame and keep their own
// buffer so trails survive regardless of what the caller does with `out`.

class Fire extends Generator {
  @override
  String get id => 'fire';
  @override
  String get name => 'Fire';
  @override
  String get defaultPalette => 'lava';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('cooling', 'Cooling', defaultValue: 0.45),
        ParamSpec('sparking', 'Sparks', defaultValue: 0.6),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Fire(width, height, Random(seed));
}

class _Fire extends EffectInstance {
  _Fire(this.w, this.h, this._rnd) : _heat = Float64List(w * h);

  final int w, h;
  final Random _rnd;
  final Float64List _heat;
  double _acc = 0;

  double _at(int x, int y) =>
      (x < 0 || x >= w || y >= h) ? 0 : _heat[y * w + x];

  void _step(Params p) {
    final cooling = 0.02 + p['cooling'] * 0.12 * 16 / h;
    // Cells cool faster the higher they are, so flames taper off.
    for (var y = 0; y < h; y++) {
      final k = 1 + (h - 1 - y) / max(1, h - 1);
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        _heat[i] = max(0, _heat[i] - _rnd.nextDouble() * cooling * k);
      }
    }
    // Heat rises: each cell averages the cells below it.
    for (var y = 0; y < h - 1; y++) {
      for (var x = 0; x < w; x++) {
        _heat[y * w + x] = (_at(x, y + 1) * 2 +
                _at(x - 1, y + 1) +
                _at(x + 1, y + 1) +
                _at(x, y + 2)) /
            5.3;
      }
    }
    for (var x = 0; x < w; x++) {
      if (_rnd.nextDouble() < 0.3 + p['sparking'] * 0.6) {
        final i = (h - 1) * w + x;
        _heat[i] = min(1, _heat[i] + 0.5 + _rnd.nextDouble() * 0.5);
      }
    }
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    // Simulate at a fixed 40 Hz so the look doesn't depend on frame rate.
    _acc += dt;
    while (_acc > 1 / 40) {
      _step(p);
      _acc -= 1 / 40;
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        out.set(x, y, pal.at(min(0.996, _heat[y * w + x] * 0.95)));
      }
    }
  }
}

class DigitalRain extends Generator {
  @override
  String get id => 'rain';
  @override
  String get name => 'Digital Rain';
  @override
  String get defaultPalette => 'matrix';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
        ParamSpec('density', 'Density', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Rain(width, height, Random(seed));
}

class _Rain extends EffectInstance {
  _Rain(int w, int h, this._rnd)
      : _buf = Frame(w, h),
        _y = List.filled(w, -1),
        _v = List.filled(w, 0);

  final Random _rnd;
  final Frame _buf;
  final List<double> _y, _v;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    _buf.fade(pow(0.82, dt * 30).toDouble());
    for (var x = 0; x < _buf.width; x++) {
      if (_y[x] < 0) {
        if (_rnd.nextDouble() < dt * (0.3 + p['density'] * 3)) {
          _y[x] = 0;
          _v[x] = (6 + _rnd.nextDouble() * 10) * (0.3 + p['speed'] * 1.5);
        }
        continue;
      }
      _y[x] += _v[x] * dt;
      if (_y[x] >= _buf.height) {
        _y[x] = -1;
      } else {
        _buf.set(x, _y[x].floor(), pal.at(0.97));
      }
    }
    // Repaint the trail with the palette so recolouring works.
    for (var y = 0; y < _buf.height; y++) {
      for (var x = 0; x < _buf.width; x++) {
        final c = _buf.get(x, y);
        final lum = max((c >> 16) & 0xFF, max((c >> 8) & 0xFF, c & 0xFF)) / 255;
        out.set(x, y, lum < 0.02 ? 0 : scaleColor(pal.at(lum * 0.97), lum));
      }
    }
  }
}

class Life extends Generator {
  @override
  String get id => 'life';
  @override
  String get name => 'Game of Life';
  @override
  String get defaultPalette => 'neon';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.4),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Life(width, height, Random(seed));
}

class _Life extends EffectInstance {
  _Life(this.w, this.h, this._rnd)
      : _cells = Uint8List(w * h),
        _age = Uint16List(w * h) {
    _seed();
  }

  final int w, h;
  final Random _rnd;
  Uint8List _cells;
  final Uint16List _age;
  double _acc = 0;
  int _lastPop = -1, _stable = 0, _gen = 0;

  void _seed() {
    for (var i = 0; i < _cells.length; i++) {
      _cells[i] = _rnd.nextDouble() < 0.35 ? 1 : 0;
      _age[i] = 0;
    }
    _gen = 0;
  }

  void _step() {
    final next = Uint8List(w * h);
    var pop = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            n += _cells[((y + dy) % h + h) % h * w + ((x + dx) % w + w) % w];
          }
        }
        final i = y * w + x;
        final alive = _cells[i] == 1 ? (n == 2 || n == 3) : n == 3;
        next[i] = alive ? 1 : 0;
        _age[i] = alive ? min(_age[i] + 1, 999) : 0;
        if (alive) pop++;
      }
    }
    _cells = next;
    _stable = pop == _lastPop ? _stable + 1 : 0;
    _lastPop = pop;
    // Restart when the board dies out, freezes, or gets stuck oscillating.
    if (pop < w * h * 0.04 || _stable > 12 || ++_gen > 400) _seed();
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    _acc += dt;
    final interval = 0.6 - p['speed'] * 0.55;
    if (_acc >= interval) {
      _acc = 0;
      _step();
    }
    for (var i = 0; i < _cells.length; i++) {
      final c = _cells[i] == 1 ? pal.at(min(0.99, _age[i] / 30)) : 0;
      out.set(i % w, i ~/ w, c);
    }
  }
}

class Starfield extends Generator {
  @override
  String get id => 'starfield';
  @override
  String get name => 'Warp Speed';
  @override
  String get defaultPalette => 'ice';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('speed', 'Speed', defaultValue: 0.5),
        ParamSpec('stars', 'Stars', min: 10, max: 80, defaultValue: 35),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Starfield(width, height, Random(seed));
}

class _Starfield extends EffectInstance {
  _Starfield(int w, int h, this._rnd) : _buf = Frame(w, h);

  final Random _rnd;
  final Frame _buf;
  final _stars = <List<double>>[]; // [x, y, z, hue]

  List<double> _spawn([double? z]) => [
        _rnd.nextDouble() * 2 - 1,
        _rnd.nextDouble() * 2 - 1,
        z ?? 1.0,
        _rnd.nextDouble(),
      ];

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final count = p['stars'].round();
    while (_stars.length < count) {
      _stars.add(_spawn(_rnd.nextDouble()));
    }
    if (_stars.length > count) _stars.removeRange(count, _stars.length);

    _buf.fade(pow(0.55, dt * 30).toDouble());
    final cx = _buf.width / 2, cy = _buf.height / 2;
    for (var i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      s[2] -= dt * (0.15 + p['speed'] * 1.2);
      final px = cx + s[0] / s[2] * cx, py = cy + s[1] / s[2] * cy;
      if (s[2] <= 0.02 ||
          px < 0 ||
          py < 0 ||
          px >= _buf.width ||
          py >= _buf.height) {
        _stars[i] = _spawn();
        continue;
      }
      final c = scaleColor(pal.at(0.5 + s[3] * 0.49), min(1, 1.2 - s[2]));
      _buf.set(px.floor(), py.floor(), addColors(_buf.get(px.floor(), py.floor()), c));
    }
    out.rgb.setAll(0, _buf.rgb);
  }
}

class Twinkle extends Generator {
  @override
  String get id => 'twinkle';
  @override
  String get name => 'Twinkle';
  @override
  String get defaultPalette => 'neon';
  @override
  List<ParamSpec> get params => const [
        ParamSpec('density', 'Density', defaultValue: 0.4),
        ParamSpec('fade', 'Fade', defaultValue: 0.5),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _Twinkle(width, height, Random(seed));
}

class _Twinkle extends EffectInstance {
  _Twinkle(int w, int h, this._rnd) : _buf = Frame(w, h);

  final Random _rnd;
  final Frame _buf;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    _buf.fade(pow(0.75 + p['fade'] * 0.22, dt * 30).toDouble());
    final spawns = _buf.pixelCount * dt * (0.05 + p['density'] * 0.6);
    var n = spawns.floor() + (_rnd.nextDouble() < spawns % 1 ? 1 : 0);
    while (n-- > 0) {
      _buf.set(_rnd.nextInt(_buf.width), _rnd.nextInt(_buf.height),
          pal.at(_rnd.nextDouble()));
    }
    out.rgb.setAll(0, _buf.rgb);
  }
}
