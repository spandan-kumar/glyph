import 'dart:math';
import 'dart:typed_data';

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import 'audio_engine.dart';

/// A generator that draws from live [AudioFeatures]. Not part of the library
/// registry: each instance is bound to the engine it was built with.
abstract class AudioVisualizer extends Generator {
  AudioVisualizer(this.feed);

  final AudioFeed feed;

  /// One-line description for the picker.
  String get blurb;
}

List<AudioVisualizer> audioVisualizers(AudioFeed feed) => [
  SpectrumBars(feed),
  MirroredSpectrum(feed),
  Waveform(feed),
  BeatPulse(feed),
  BassFire(feed),
  Spectrogram(feed),
  Starburst(feed),
  VuMeter(feed),
  RadialSpectrum(feed),
];

/// Shared plumbing: crossfades to a gentle synthetic "idle music" when the
/// room is silent (so the matrix never goes black), and turns the engine's
/// beat counter into per-frame beat events.
abstract class AudioEffect extends EffectInstance {
  AudioEffect(this.feed, this.w, this.h, int seed) : rnd = Random(seed);

  final AudioFeed feed;
  final int w, h;
  final Random rnd;

  late AudioFeatures live;

  /// 0 = live sound, 1 = idle animation.
  double idle = 1;
  bool beat = false;
  double beatStrength = 0;

  /// 1 on a beat, decaying; handy for flashes.
  double pulse = 0;
  double t = 0;

  int? _seenBeats;
  int _idleBeat = 0;

  static const _idlePeriod = 1.6;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    this.t = t;
    live = feed.latest;
    final quiet = live.silent || live.bands.isEmpty;
    idle += ((quiet ? 1.0 : 0.0) - idle) * (1 - exp(-dt / 0.6));
    beat = false;
    final seen = _seenBeats;
    if (seen != null && live.beatCount != seen && !quiet) {
      beat = true;
      beatStrength = live.beatStrength;
    }
    _seenBeats = live.beatCount;
    final ib = (t / _idlePeriod).floor();
    if (ib != _idleBeat) {
      _idleBeat = ib;
      if (idle > 0.5 && !beat) {
        beat = true;
        beatStrength = 0.35;
      }
    }
    pulse = beat ? max(pulse * exp(-dt * 5), beatStrength) : pulse * exp(-dt * 5);
    draw(out, dt, p, pal);
  }

  void draw(Frame out, double dt, Params p, Palette pal);

  double _mix(double a, double b) => a + (b - a) * idle;

  double _idleBand(double u) =>
      0.1 + 0.12 * (0.5 + 0.5 * sin(t * 1.1 + u * 5)) * (0.6 + 0.4 * sin(t * 0.37 + u * 2.3));

  double band(double u) => idle >= 0.999 ? _idleBand(u) : _mix(live.band(u), _idleBand(u));
  double get level => _mix(live.level, 0.15 + 0.05 * sin(t * 0.9));
  double get bass => _mix(live.bass, 0.16 + 0.08 * sin(t * 1.3));
  double get mid => _mix(live.mid, 0.14 + 0.06 * sin(t * 0.8 + 1));
  double get treble => _mix(live.treble, 0.1 + 0.05 * sin(t * 1.7 + 2));
  double wave(double u) =>
      _mix(live.waveAt(u), 0.22 * sin(2 * pi * (u * 1.5) + t * 1.8) * (0.7 + 0.3 * sin(t * 0.5)));
}

double _c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

int _mixColor(int a, int b, double t) => rgb(
  (((a >> 16) & 0xFF) + ((((b >> 16) & 0xFF) - ((a >> 16) & 0xFF)) * t)).round(),
  (((a >> 8) & 0xFF) + ((((b >> 8) & 0xFF) - ((a >> 8) & 0xFF)) * t)).round(),
  ((a & 0xFF) + (((b & 0xFF) - (a & 0xFF)) * t)).round(),
);

/// Float RGB canvas for additive effects; clamps once on output.
class _Canvas {
  _Canvas(this.w, this.h) : px = Float64List(w * h * 3);

  final int w, h;
  final Float64List px;

  void clear() => px.fillRange(0, px.length, 0);

  void fade(double f) {
    for (var i = 0; i < px.length; i++) {
      px[i] *= f;
    }
  }

  void add(int x, int y, int color, double a) {
    if (x < 0 || y < 0 || x >= w || y >= h || a <= 0) return;
    final i = (y * w + x) * 3;
    px[i] += ((color >> 16) & 0xFF) * a;
    px[i + 1] += ((color >> 8) & 0xFF) * a;
    px[i + 2] += (color & 0xFF) * a;
  }

  /// Bilinear splat so sub-pixel motion stays smooth on tiny matrices.
  void splat(double x, double y, int color, double a) {
    final x0 = (x - 0.5).floor(), y0 = (y - 0.5).floor();
    final fx = x - 0.5 - x0, fy = y - 0.5 - y0;
    add(x0, y0, color, a * (1 - fx) * (1 - fy));
    add(x0 + 1, y0, color, a * fx * (1 - fy));
    add(x0, y0 + 1, color, a * (1 - fx) * fy);
    add(x0 + 1, y0 + 1, color, a * fx * fy);
  }

  void writeTo(Frame out) {
    for (var i = 0; i < w * h; i++) {
      out.rgb[i * 3] = px[i * 3].clamp(0, 255).toInt();
      out.rgb[i * 3 + 1] = px[i * 3 + 1].clamp(0, 255).toInt();
      out.rgb[i * 3 + 2] = px[i * 3 + 2].clamp(0, 255).toInt();
    }
  }
}

// ---- Spectrum bars ---------------------------------------------------------

class SpectrumBars extends AudioVisualizer {
  SpectrumBars(super.feed);
  @override
  String get id => 'audio_bars';
  @override
  String get name => 'Spectrum';
  @override
  String get blurb => 'Bars with falling peaks';
  @override
  String get defaultPalette => 'rainbow';
  @override
  List<ParamSpec> get params => const [ParamSpec('fall', 'Peak fall', defaultValue: 0.5)];
  @override
  EffectInstance create(int width, int height, int seed) => _Bars(feed, width, height, seed);
}

class _Bars extends AudioEffect {
  _Bars(super.feed, super.w, super.h, super.seed)
    : _peak = Float64List(w),
      _hold = Float64List(w),
      _vel = Float64List(w);

  final Float64List _peak, _hold, _vel;

  @override
  void draw(Frame out, double dt, Params p, Palette pal) {
    out.fill(0);
    for (var x = 0; x < w; x++) {
      final hgt = band((x + 0.5) / w) * h;
      final col = pal.at(x / max(1, w) * 0.85);
      for (var r = 0; r < h; r++) {
        final a = _c01(hgt - r);
        if (a <= 0) break;
        // Slightly brighter towards the top of each bar.
        out.set(x, h - 1 - r, scaleColor(col, a * (0.45 + 0.55 * (r + 1) / h)));
      }
      if (hgt >= _peak[x]) {
        _peak[x] = hgt;
        _hold[x] = 0.3;
        _vel[x] = 0;
      } else if (_hold[x] > 0) {
        _hold[x] -= dt;
      } else {
        _vel[x] += dt * (10 + p['fall'] * 60);
        _peak[x] = max(hgt, _peak[x] - _vel[x] * dt);
      }
      if (_peak[x] >= 1 && h > 2) {
        final y = h - _peak[x].ceil();
        out.set(x, max(0, y), _mixColor(col, 0xFFFFFF, 0.55));
      }
    }
  }
}

// ---- Mirrored spectrum -----------------------------------------------------

class MirroredSpectrum extends AudioVisualizer {
  MirroredSpectrum(super.feed);
  @override
  String get id => 'audio_mirror';
  @override
  String get name => 'Mirror';
  @override
  String get blurb => 'Bass in the middle, symmetric';
  @override
  String get defaultPalette => 'neon';
  @override
  EffectInstance create(int width, int height, int seed) => _Mirror(feed, width, height, seed);
}

class _Mirror extends AudioEffect {
  _Mirror(super.feed, super.w, super.h, super.seed);

  @override
  void draw(Frame out, double dt, Params p, Palette pal) {
    final cx = (w - 1) / 2, cy = h / 2;
    final bg = pulse * 0.12;
    for (var x = 0; x < w; x++) {
      final u = w == 1 ? 0.0 : (x - cx).abs() / (w / 2);
      final half = band(u) * h / 2;
      final col = pal.at(u * 0.7 + t * 0.03);
      for (var y = 0; y < h; y++) {
        final d = ((y + 0.5) - cy).abs();
        final a = _c01(half + 0.5 - d);
        final tip = half > 0 ? _c01(d / max(half, 0.5)) : 0.0;
        out.set(
          x,
          y,
          a > 0 ? scaleColor(_mixColor(col, 0xFFFFFF, tip * 0.25), a) : scaleColor(col, bg),
        );
      }
    }
  }
}

// ---- Waveform --------------------------------------------------------------

class Waveform extends AudioVisualizer {
  Waveform(super.feed);
  @override
  String get id => 'audio_wave';
  @override
  String get name => 'Waveform';
  @override
  String get blurb => 'Oscilloscope with trails';
  @override
  String get defaultPalette => 'synthwave';
  @override
  List<ParamSpec> get params => const [ParamSpec('trail', 'Trail', defaultValue: 0.5)];
  @override
  EffectInstance create(int width, int height, int seed) => _Wave(feed, width, height, seed);
}

class _Wave extends AudioEffect {
  _Wave(super.feed, super.w, super.h, super.seed) : _c = _Canvas(w, h);

  final _Canvas _c;

  @override
  void draw(Frame out, double dt, Params p, Palette pal) {
    _c.fade(pow(0.02 + p['trail'] * 0.5, dt * 10).toDouble());
    final cy = h / 2, amp = h * 0.46;
    double yAt(int x) => cy - wave((x + 0.5) / w) * amp;
    var prev = yAt(0);
    for (var x = 0; x < w; x++) {
      final y = yAt(x);
      final col = pal.at(x / max(1, w) * 0.4 + t * 0.05 + level * 0.3);
      // Join to the previous column so steep edges stay continuous.
      final lo = min(prev, y), hi = max(prev, y);
      for (var py = 0; py < h; py++) {
        final c = py + 0.5;
        final d = c < lo ? lo - c : (c > hi ? c - hi : 0.0);
        final a = _c01(1 - d);
        if (a > 0) _c.add(x, py, col, a * a * 0.9);
      }
      prev = y;
    }
    _c.writeTo(out);
  }
}

// ---- Beat pulse ------------------------------------------------------------

class BeatPulse extends AudioVisualizer {
  BeatPulse(super.feed);
  @override
  String get id => 'audio_pulse';
  @override
  String get name => 'Beat rings';
  @override
  String get blurb => 'Rings burst on every beat';
  @override
  String get defaultPalette => 'galaxy';
  @override
  List<ParamSpec> get params => const [ParamSpec('speed', 'Speed', defaultValue: 0.5)];
  @override
  EffectInstance create(int width, int height, int seed) => _Pulse(feed, width, height, seed);
}

class _Ring {
  _Ring(this.strength, this.hue);
  double r = 0;
  final double strength, hue;
}

class _Pulse extends AudioEffect {
  _Pulse(super.feed, super.w, super.h, super.seed) : _c = _Canvas(w, h);

  final _Canvas _c;
  final _rings = <_Ring>[];
  double _hue = 0;

  @override
  void draw(Frame out, double dt, Params p, Palette pal) {
    final cx = w / 2, cy = h / 2;
    final maxR = sqrt(cx * cx + cy * cy) + 1;
    if (beat) {
      _hue = (_hue + 0.13) % 1;
      _rings.add(_Ring(beatStrength, _hue));
      if (_rings.length > 12) _rings.removeAt(0);
    }
    final speed = maxR * (0.6 + p['speed'] * 1.6);
    for (final r in _rings) {
      r.r += dt * speed;
    }
    _rings.removeWhere((r) => r.r > maxR + 1.5);
    _c.clear();
    final glow = bass * 0.5 + pulse * 0.4;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        final d = sqrt(dx * dx + dy * dy);
        final core = _c01(1 - d / max(1.0, maxR * 0.35));
        _c.add(x, y, pal.at(_hue + 0.5), core * core * glow);
        for (final r in _rings) {
          final e = d - r.r;
          final a = exp(-e * e / 0.7) * (0.35 + 0.65 * r.strength) * _c01(1 - r.r / maxR);
          if (a > 0.01) _c.add(x, y, pal.at(r.hue + d * 0.02), a);
        }
      }
    }
    _c.writeTo(out);
  }
}

// ---- Bass fire -------------------------------------------------------------

class BassFire extends AudioVisualizer {
  BassFire(super.feed);
  @override
  String get id => 'audio_fire';
  @override
  String get name => 'Bass fire';
  @override
  String get blurb => 'Flames fed by the low end';
  @override
  String get defaultPalette => 'lava';
  @override
  EffectInstance create(int width, int height, int seed) => _BassFire(feed, width, height, seed);
}

class _BassFire extends AudioEffect {
  _BassFire(super.feed, super.w, super.h, super.seed) : _heat = Float64List(w * h);

  final Float64List _heat;
  double _acc = 0;

  double _at(int x, int y) => (x < 0 || x >= w || y >= h) ? 0 : _heat[y * w + x];

  void _step(double fuel, bool burst) {
    final cooling = (0.03 + (1 - fuel) * 0.12) * 16 / max(4, h);
    for (var y = 0; y < h; y++) {
      final k = 1 + (h - 1 - y) / max(1, h - 1);
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        _heat[i] = max(0, _heat[i] - rnd.nextDouble() * cooling * k);
      }
    }
    for (var y = 0; y < h - 1; y++) {
      for (var x = 0; x < w; x++) {
        _heat[y * w + x] =
            (_at(x, y + 1) * 2 + _at(x - 1, y + 1) + _at(x + 1, y + 1) + _at(x, y + 2)) / 5.3;
      }
    }
    for (var x = 0; x < w; x++) {
      final i = (h - 1) * w + x;
      if (burst) {
        _heat[i] = 1;
      } else if (rnd.nextDouble() < 0.15 + fuel * 0.85) {
        _heat[i] = min(1, _heat[i] + 0.25 + fuel * 0.75 * rnd.nextDouble());
      }
    }
  }

  @override
  void draw(Frame out, double dt, Params p, Palette pal) {
    final fuel = _c01(bass * 0.8 + level * 0.3);
    var burst = beat && beatStrength > 0.3;
    _acc += dt;
    while (_acc > 1 / 40) {
      _step(fuel, burst);
      burst = false;
      _acc -= 1 / 40;
    }
    for (var i = 0; i < w * h; i++) {
      out.set(i % w, i ~/ w, pal.at(min(0.996, _heat[i] * 0.95)));
    }
  }
}

// ---- Spectrogram -----------------------------------------------------------

class Spectrogram extends AudioVisualizer {
  Spectrogram(super.feed);
  @override
  String get id => 'audio_spectrogram';
  @override
  String get name => 'Waterfall';
  @override
  String get blurb => 'Spectrogram flowing down';
  @override
  String get defaultPalette => 'galaxy';
  @override
  List<ParamSpec> get params => const [ParamSpec('speed', 'Speed', defaultValue: 0.5)];
  @override
  EffectInstance create(int width, int height, int seed) => _Spectrogram(feed, width, height, seed);
}

class _Spectrogram extends AudioEffect {
  _Spectrogram(super.feed, super.w, super.h, super.seed) : _rows = Float64List(w * h);

  final Float64List _rows;
  double _acc = 0;

  @override
  void draw(Frame out, double dt, Params p, Palette pal) {
    final step = 1 / (8 + p['speed'] * 30);
    _acc += dt;
    if (_acc >= step) {
      _acc %= step;
      _rows.setRange(w, w * h, _rows);
    }
    // The newest row tracks the bands live between shifts.
    for (var x = 0; x < w; x++) {
      _rows[x] = band((x + 0.5) / w);
    }
    for (var y = 0; y < h; y++) {
      final age = 1 - y / max(1, h) * 0.5;
      for (var x = 0; x < w; x++) {
        final v = _rows[y * w + x];
        out.set(x, y, scaleColor(pal.at(0.08 + v * 0.85), _c01(v * 1.3) * age));
      }
    }
  }
}

// ---- Starburst -------------------------------------------------------------

class Starburst extends AudioVisualizer {
  Starburst(super.feed);
  @override
  String get id => 'audio_starburst';
  @override
  String get name => 'Starburst';
  @override
  String get blurb => 'Sparks fly on beats';
  @override
  String get defaultPalette => 'festive';
  @override
  EffectInstance create(int width, int height, int seed) => _Starburst(feed, width, height, seed);
}

class _Spark {
  _Spark(this.x, this.y, this.vx, this.vy, this.life, this.hue);
  double x, y, vx, vy, life;
  final double hue;
}

class _Starburst extends AudioEffect {
  _Starburst(super.feed, super.w, super.h, super.seed) : _c = _Canvas(w, h);

  final _Canvas _c;
  final _sparks = <_Spark>[];

  @override
  void draw(Frame out, double dt, Params p, Palette pal) {
    final scale = max(w, h) / 16;
    if (beat) {
      final ox = w / 2 + (rnd.nextDouble() - 0.5) * w * 0.4;
      final oy = h / 2 + (rnd.nextDouble() - 0.5) * h * 0.4;
      final hue = rnd.nextDouble();
      final n = ((6 + beatStrength * 18) * scale).round().clamp(4, 80);
      for (var i = 0; i < n; i++) {
        final a = 2 * pi * i / n + rnd.nextDouble() * 0.3;
        final v = (5 + beatStrength * 12 + rnd.nextDouble() * 4) * scale;
        _sparks.add(
          _Spark(
            ox,
            oy,
            cos(a) * v,
            sin(a) * v,
            0.6 + rnd.nextDouble() * 0.6,
            hue + rnd.nextDouble() * 0.15,
          ),
        );
      }
      if (_sparks.length > 300) _sparks.removeRange(0, _sparks.length - 300);
    }
    _c.fade(pow(0.4, dt * 10).toDouble());
    for (final s in _sparks) {
      s.life -= dt;
      s.vx *= exp(-dt * 2.5);
      s.vy = s.vy * exp(-dt * 2.5) + dt * 3 * scale;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      _c.splat(s.x, s.y, pal.at(s.hue), _c01(s.life / 0.6) * 1.1);
    }
    _sparks.removeWhere((s) => s.life <= 0 || s.x < -2 || s.y < -2 || s.x > w + 2 || s.y > h + 2);
    // Treble twinkles between beats.
    final twinkles = treble * dt * w * h * 0.6;
    for (var i = 0; i < twinkles.floor() + (rnd.nextDouble() < twinkles % 1 ? 1 : 0); i++) {
      _c.add(rnd.nextInt(w), rnd.nextInt(h), pal.at(rnd.nextDouble()), 0.5 + treble * 0.5);
    }
    _c.writeTo(out);
  }
}

// ---- VU meter --------------------------------------------------------------

class VuMeter extends AudioVisualizer {
  VuMeter(super.feed);
  @override
  String get id => 'audio_vu';
  @override
  String get name => 'VU meter';
  @override
  String get blurb => 'Low and high meters with peak hold';
  @override
  String get defaultPalette => 'rainbow';
  @override
  EffectInstance create(int width, int height, int seed) => _Vu(feed, width, height, seed);
}

class _Vu extends AudioEffect {
  _Vu(super.feed, super.w, super.h, super.seed);

  final _v = [0.0, 0.0], _peak = [0.0, 0.0], _hold = [0.0, 0.0];

  @override
  void draw(Frame out, double dt, Params p, Palette pal) {
    // Lay meters along the longer side.
    final vertical = h >= w;
    final across = vertical ? w : h, along = vertical ? h : w;
    final two = across >= 4;
    final targets = two
        ? [_c01(bass * 0.7 + level * 0.3), _c01(max(mid, treble) * 0.8 + level * 0.2)]
        : [level];
    for (var m = 0; m < targets.length; m++) {
      final tgt = targets[m];
      _v[m] = tgt + (_v[m] - tgt) * exp(-dt / (tgt > _v[m] ? 0.05 : 0.35));
      if (_v[m] >= _peak[m]) {
        _peak[m] = _v[m];
        _hold[m] = 0.8;
      } else if ((_hold[m] -= dt) < 0) {
        _peak[m] = max(_v[m], _peak[m] - dt * 0.6);
      }
    }
    final gap = two && across >= 6 ? 1 : 0;
    final width = two ? (across - gap) / 2 : across.toDouble();
    for (var a = 0; a < across; a++) {
      final m = two ? (a < width ? 0 : (a >= width + gap ? 1 : -1)) : 0;
      for (var s = 0; s < along; s++) {
        final frac = (s + 0.5) / along;
        // Green → amber → red on the default rainbow.
        final col = pal.at(0.33 * (1 - frac));
        int c;
        if (m < 0) {
          c = 0;
        } else {
          final lit = _c01(_v[m] * along - s);
          final peak = (_peak[m] * along).ceil() - 1 == s && _peak[m] > 0.05;
          c = peak ? _mixColor(col, 0xFFFFFF, 0.4) : scaleColor(col, max(0.06, lit));
        }
        final x = vertical ? a : s, y = vertical ? h - 1 - s : a;
        out.set(x, y, c);
      }
    }
  }
}

// ---- Radial spectrum -------------------------------------------------------

class RadialSpectrum extends AudioVisualizer {
  RadialSpectrum(super.feed);
  @override
  String get id => 'audio_radial';
  @override
  String get name => 'Radial';
  @override
  String get blurb => 'Spectrum wrapped in a circle';
  @override
  String get defaultPalette => 'aurora';
  @override
  EffectInstance create(int width, int height, int seed) => _Radial(feed, width, height, seed);
}

class _Radial extends AudioEffect {
  _Radial(super.feed, super.w, super.h, super.seed);

  double _spin = 0;

  @override
  void draw(Frame out, double dt, Params p, Palette pal) {
    _spin += dt * (0.2 + level * 0.8);
    final cx = w / 2, cy = h / 2;
    final maxR = max(1.0, min(cx, cy));
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        final r = sqrt(dx * dx + dy * dy) / maxR;
        // Mirror the angle so the ring is seamless; bass at the top.
        var ang = (atan2(dx, -dy) + _spin) % (2 * pi);
        if (ang > pi) ang = 2 * pi - ang;
        final u = ang / pi;
        final reach = 0.3 + band(u) * 0.75;
        final a = _c01((reach - r) * maxR + 0.5);
        final core = _c01(1 - r / 0.3) * (0.15 + pulse * 0.6);
        final col = pal.at(u * 0.8 + t * 0.04);
        out.set(
          x,
          y,
          addColors(scaleColor(col, a * _c01(0.35 + r)), scaleColor(pal.at(0.9), core)),
        );
      }
    }
  }
}
