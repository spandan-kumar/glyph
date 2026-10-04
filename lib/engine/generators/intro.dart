import 'dart:math';

import '../frame.dart';
import '../generator.dart';
import '../palette.dart';

/// The Glyph logo: a blocky arcade "g" with a 3D drop shadow and a spark,
/// on a 16×16 grid: what the device shows when it powers on.
const glyphLogo = [
  '................',
  '................',
  '...#########....',
  '...#########....',
  '...###...###....',
  '...###...###....',
  '...###...###....',
  '...#########....',
  '...#########....',
  '.........###....',
  '.........###....',
  '...#########....',
  '...#########....',
  '................',
  '................',
  '................',
];

/// The arcade drop shadow, one pixel down-right of the letter.
const glyphShadow = 0xFF4A2384;

/// Where the spark twinkles.
const glyphSparkCell = (13, 1);

/// Cells of the drop shadow: down-right of each letter pixel, where the
/// letter itself isn't.
List<(int, int)> glyphShadowCells() => [
      for (var y = 0; y < 15; y++)
        for (var x = 0; x < 15; x++)
          if (glyphLogo[y][x] == '#' && glyphLogo[y + 1][x + 1] != '#') (x + 1, y + 1),
    ];

/// Candy colours, laid across the logo in diagonal bands.
const glyphCandy = [0xFFFFC93C, 0xFFFF8A3D, 0xFFFF4F79, 0xFFB46CFF, 0xFF3CC8FF];
const glyphSpark = 0xFFFFF6DC;

/// Colour of logo pixel (x, y).
int glyphLogoColor(int x, int y) {
  final band = ((x + y - 6) / 16 * glyphCandy.length).floor().clamp(0, glyphCandy.length - 1);
  return glyphCandy[band];
}

/// Glyph's intro: a boot blink, then candy pixels rain down and pile up
/// like sand, pop into the air and spring into the logo, which gets a shine
/// and a twinkling spark. Plays once in [GlyphIntro.duration] seconds and
/// holds the logo afterwards. Deterministic, so the device, the app splash
/// and the icon always match.
class GlyphIntro extends Generator {
  static const duration = 5.0;

  @override
  String get id => 'intro';
  @override
  String get name => 'Glyph intro';

  @override
  EffectInstance create(int width, int height, int seed) => _Intro(width, height);
}

class _Particle {
  _Particle(this.tx, this.ty, this.color, this.spawn, this.x);

  /// Target cell in the logo.
  final double tx, ty;
  final int color;

  /// When it starts falling, and from which column.
  final double spawn;
  double x, y = -1, vx = 0, vy = 0;
  bool resting = false, launched = false;
}

class _Intro extends EffectInstance {
  _Intro(this.w, this.h) {
    _reset();
  }

  final int w, h;
  late List<_Particle> _ps;
  late List<bool> _occupied;
  double _simT = 0, _lastT = -1;

  // Timeline (seconds).
  static const _dropStart = 0.55, _launch = 2.45, _settled = 3.55, _shineEnd = 4.25;

  // Logo placement scales to the matrix (16×16 native).
  late final double _sx = w / 16, _sy = h / 16;

  void _reset() {
    final rnd = Random(7);
    final cells = <(int, int)>[];
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        if (glyphLogo[y][x] == '#') cells.add((x, y));
      }
    }
    // Drop order: shuffled, so the pile is confetti, not a sorted stack.
    final order = List.generate(cells.length, (i) => i)..shuffle(rnd);
    _ps = [
      for (var k = 0; k < order.length; k++)
        () {
          final (x, y) = cells[order[k]];
          return _Particle(
            x * _sx, y * _sy, glyphLogoColor(x, y),
            _dropStart + k * 0.022 + rnd.nextDouble() * 0.05,
            // Columns spread over the width so the pile is wide and low.
            (rnd.nextDouble() * (w - 1)).roundToDouble(),
          );
        }(),
    ];
    _occupied = List.filled(w * h, false);
    _simT = 0;
  }

  bool _occ(int x, int y) => y >= h || x < 0 || x >= w || (y >= 0 && _occupied[y * w + x]);

  void _step(double dt) {
    _simT += dt;
    final t = _simT;
    for (final p in _ps) {
      if (t < p.spawn) continue;
      if (t < _launch) {
        // Falling sand with a little bounce.
        if (p.resting) continue;
        p.vy += 70 * dt;
        final ny = p.y + p.vy * dt;
        final cx = p.x.round();
        final below = ny.floor() + 1;
        if (_occ(cx, below)) {
          // Try to slide off a peak, like sand.
          final dir = (cx + below).isEven ? 1 : -1;
          if (!_occ(cx + dir, below) && !_occ(cx + dir, ny.floor())) {
            p.x += dir;
            p.y = ny.floorToDouble();
            continue;
          }
          if (!_occ(cx - dir, below) && !_occ(cx - dir, ny.floor())) {
            p.x -= dir;
            p.y = ny.floorToDouble();
            continue;
          }
          final restY = (below - 1).clamp(0, h - 1);
          if (p.vy > 9) {
            p.vy = -p.vy * 0.28; // a small bounce
            p.y = restY.toDouble();
            continue;
          }
          p.y = restY.toDouble();
          p.vy = 0;
          p.resting = true;
          _occupied[restY * w + cx] = true;
        } else {
          p.y = ny;
        }
      } else {
        if (!p.launched) {
          // Pop! Everything leaps up, then springs to its place.
          p.launched = true;
          p.vy = -14 - (p.x * 7 % 6);
          p.vx = (p.tx - p.x) * 1.2;
        }
        // Under-damped spring: overshoots a touch, then settles.
        const k = 85.0, c = 9.5;
        p.vx += (k * (p.tx - p.x) - c * p.vx) * dt;
        p.vy += (k * (p.ty - p.y) - c * p.vy) * dt;
        p.x += p.vx * dt;
        p.y += p.vy * dt;
      }
    }
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    if (t < _lastT) _reset();
    _lastT = t;
    // Fixed-step physics, so the device bake and the app match exactly.
    while (_simT + 1 / 120 <= t) {
      _step(1 / 120);
    }

    out.fill(0);
    if (t < _dropStart) {
      // Boot blink: a single pixel waking up in the middle, twice.
      final on = (t > 0.08 && t < 0.2) || (t > 0.32 && t < 0.5);
      if (on) out.set((w / 2).floor(), (h / 2).floor(), glyphSpark);
      return;
    }

    // The 3D shadow drops in under the finished letter as the last beat:
    // it slides from behind the letter (up-left) into place.
    if (t >= _settled - 0.2) {
      final k = ((t - (_settled - 0.2)) / 0.25).clamp(0.0, 1.0);
      final off = 1 - Curves.easeOutBack(k);
      for (final (x, y) in glyphShadowCells()) {
        out.set(((x - off) * _sx).round(), ((y - off) * _sy).round(), _mix(0xFF000000, glyphShadow, k));
      }
    }
    final shine = t > _settled && t < _shineEnd ? (t - _settled) / (_shineEnd - _settled) : -1.0;
    for (final q in _ps) {
      if (t < q.spawn) continue;
      final settled = t >= _settled;
      final x = settled ? q.tx.round() : q.x.round();
      final y = settled ? q.ty.round() : q.y.round();
      var c = q.color;
      if (shine >= 0) {
        // A diagonal highlight sweeps across the finished logo.
        final band = (x + y) / (w + h) - shine * 1.4 + 0.2;
        final k = (1 - (band.abs() * 6)).clamp(0.0, 1.0);
        c = _mix(c, 0xFFFFFFFF, k * 0.75);
      }
      out.set(x, y, c);
    }
    if (t >= _settled) {
      // The spark: pops in, then twinkles.
      final s = t - _settled;
      final tw = 0.55 + 0.45 * sin(s * 7);
      if (s > 0.35) {
        out.set((glyphSparkCell.$1 * _sx).round(), (glyphSparkCell.$2 * _sy).round(), _mix(0xFF000000, glyphSpark, tw));
      }
    }
  }

  static int _mix(int a, int b, double t) {
    int ch(int s) => (((a >> s) & 0xFF) + (((b >> s) & 0xFF) - ((a >> s) & 0xFF)) * t).round();
    return (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }
}

/// Back-out easing without importing Flutter (the engine stays pure Dart).
abstract final class Curves {
  static double easeOutBack(double t) {
    const c1 = 1.70158, c3 = c1 + 1;
    final u = t - 1;
    return 1 + c3 * u * u * u + c1 * u * u;
  }
}
