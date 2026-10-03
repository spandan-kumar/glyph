import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../frame.dart';
import '../generator.dart';
import '../palette.dart';

/// Pixel-art loops authored as text. A pack file looks like:
///
/// ```json
/// {
///   "pack": "faces", "category": "Emoji",
///   "colors": {"Y": "#FFC83D", "K": "#2A1A0A", "1": "p:0.7", "2": "c:0.2"},
///   "parts": {"face": ["....YYYY....", ...]},
///   "sprites": [{
///     "id": "smile", "title": "Smiley", "tags": ["happy"],
///     "palette": "sunset", "motion": "bounce", "ms": 250,
///     "frames": [
///       {"base": "face", "patch": [{"at": [0, 4], "rows": ["    KK    KK    "]}]},
///       {"base": 0, "patch": [...], "shift": [0, -1], "flip": "h"},
///       ["................", ...]
///     ],
///     "seq": [0, 0, 1, 0]
///   }]
/// }
/// ```
///
/// `.` is transparent. In patches `.` and space keep the pixel underneath and
/// `_` clears it.
/// Colours: `#RRGGBB`; `p:v[*k]` a palette entry (recolourable); `c:v[*k]`
/// a palette entry that cycles over time; `t:#RRGGBB` a twinkling colour.
/// A trailing `!` on a palette colour boosts it to full brightness, so text
/// stays readable on palettes with dark stretches.
/// `ms` is a number or one duration per sequence step.

enum SpriteMotion { still, bounce, float, sway, scroll, pulse, shake }

const spriteMotionNames = ['still', 'bounce', 'float', 'sway', 'scroll', 'pulse', 'shake'];

class _Ink {
  const _Ink(this.kind, this.rgb, this.v, this.k, [this.vivid = false]);

  final int kind; // 0 fixed, 1 palette, 2 cycling palette, 3 twinkle
  final int rgb;
  final double v, k;
  final bool vivid;

  static _Ink parse(String s) {
    if (s.startsWith('#')) return _Ink(0, int.parse(s.substring(1), radix: 16), 0, 1);
    if (s.startsWith('t:#')) return _Ink(3, int.parse(s.substring(3), radix: 16), 0, 1);
    final kind = switch (s[0]) { 'p' => 1, 'c' => 2, _ => throw FormatException('bad colour $s') };
    final vivid = s.endsWith('!');
    final body = s.substring(2, vivid ? s.length - 1 : s.length).split('*');
    return _Ink(kind, 0, double.parse(body[0]), body.length > 1 ? double.parse(body[1]) : 1, vivid);
  }
}

/// A decoded sprite: frames of ink indices (-1 = transparent).
class Sprite {
  Sprite._({
    required this.id,
    required this.title,
    required this.category,
    required this.tags,
    required this.palette,
    required this.motion,
    required this.width,
    required this.height,
    required this.backdrop,
    required List<Int16List> frames,
    required List<_Ink> inks,
    required this.seq,
    required this.ms,
    required this.pack,
    this.source,
  })  : _frames = frames, // ignore: prefer_initializing_formals
        _inks = inks; // ignore: prefer_initializing_formals

  final String id, title, category, palette, pack;
  final List<String> tags;
  final SpriteMotion motion;
  final int width, height;
  final double backdrop;
  final List<Int16List> _frames;
  final List<_Ink> _inks;
  final List<int> seq;
  final List<int> ms;

  /// Provenance for drawings based on public-domain works: work, year,
  /// creator, basis, jurisdiction and a user-facing notice.
  final Map<String, dynamic>? source;

  String? get notice => source?['notice'] as String?;

  int get frameCount => _frames.length;

  /// Much wider than tall: scrolling text and friezes.
  bool get isBanner => width >= height * 2;
  int get loopMs => ms.fold(0, (a, b) => a + b);
  bool get recolourable => _inks.any((i) => i.kind == 1 || i.kind == 2);

  /// Sequence step index at [ms] into the loop.
  int stepAt(double timeMs) {
    var m = timeMs % loopMs;
    for (var i = 0; i < ms.length; i++) {
      if (m < ms[i]) return i;
      m -= ms[i];
    }
    return ms.length - 1;
  }

  /// Resolves frame [f] to ARGB (alpha 0 or 255) for [pal] at time [t].
  void resolve(int f, Palette pal, double t, Uint32List out) {
    final inks = Uint32List(_inks.length);
    for (var i = 0; i < _inks.length; i++) {
      final ink = _inks[i];
      var c = switch (ink.kind) {
        0 => ink.rgb,
        1 => pal.at(ink.v),
        2 => pal.at(ink.v + t * 0.25),
        _ => scaleColor(ink.rgb, 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 5 + i * 2.3))),
      };
      if (ink.vivid) c = _vivid(c);
      if (ink.k != 1) c = scaleColor(c, ink.k);
      inks[i] = 0xFF000000 | c;
    }
    final src = _frames[f];
    for (var i = 0; i < src.length; i++) {
      final k = src[i];
      out[i] = k < 0 ? 0 : inks[k];
    }
  }

  static int _vivid(int c) {
    final m = max((c >> 16) & 0xFF, max((c >> 8) & 0xFF, c & 0xFF));
    if (m < 24) return 0xFFFFFF;
    // Lift to full brightness and wash dark colours slightly towards white.
    final k = 255 / m;
    int ch(int v) => min(255, (v * k * 0.85 + 255 * 0.15).round());
    return (ch((c >> 16) & 0xFF) << 16) | (ch((c >> 8) & 0xFF) << 8) | ch(c & 0xFF);
  }

  /// Raw ink grid, for tests and tools.
  List<int> frameAt(int f) => _frames[f];

  static List<Sprite> parsePack(String json) =>
      parsePackJson(jsonDecode(json) as Map<String, dynamic>);

  static List<Sprite> parsePackJson(Map<String, dynamic> pack) {
    final packId = pack['pack'] as String? ?? 'pack';
    final packColors = (pack['colors'] as Map? ?? const {}).cast<String, String>();
    final parts = <String, List<String>>{
      for (final e in (pack['parts'] as Map? ?? const {}).entries)
        e.key as String: [for (final r in e.value as List) r as String],
    };
    return [
      for (final s in pack['sprites'] as List)
        _parseSprite(s as Map<String, dynamic>, packId, pack['category'] as String? ?? 'Pixel Art',
            packColors, parts),
    ];
  }

  static Sprite _parseSprite(Map<String, dynamic> j, String packId, String category,
      Map<String, String> packColors, Map<String, List<String>> parts) {
    final id = j['id'] as String;
    final colors = {...packColors, ...(j['colors'] as Map? ?? const {}).cast<String, String>()};
    final rowsFrames = <List<String>>[];
    for (final spec in j['frames'] as List) {
      rowsFrames.add(_buildFrame(spec, rowsFrames, parts, id));
    }
    if (rowsFrames.isEmpty) throw FormatException('$id: no frames');
    final h = rowsFrames.first.length, w = rowsFrames.first.first.length;
    final inkIndex = <String, int>{};
    final inks = <_Ink>[];
    final frames = <Int16List>[];
    for (final rows in rowsFrames) {
      if (rows.length != h || rows.any((r) => r.length != w)) {
        throw FormatException('$id: frames must all be ${w}x$h');
      }
      final f = Int16List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final ch = rows[y][x];
          if (ch == '.' || ch == ' ' || ch == '_') {
            f[y * w + x] = -1;
            continue;
          }
          f[y * w + x] = inkIndex.putIfAbsent(ch, () {
            final def = colors[ch];
            if (def == null) throw FormatException('$id: no colour for "$ch"');
            inks.add(_Ink.parse(def));
            return inks.length - 1;
          });
        }
      }
      frames.add(f);
    }
    final seq = [for (final s in (j['seq'] as List? ?? List.generate(frames.length, (i) => i))) s as int];
    if (seq.any((s) => s < 0 || s >= frames.length)) throw FormatException('$id: bad seq');
    final msRaw = j['ms'] ?? 200;
    final ms = msRaw is List
        ? [for (final m in msRaw) (m as num).toInt().clamp(20, 10000)]
        : List.filled(seq.length, (msRaw as num).toInt().clamp(20, 10000));
    if (ms.length != seq.length) throw FormatException('$id: ms must match seq');
    final motionName = j['motion'] as String? ?? 'still';
    final motion = SpriteMotion.values[max(0, spriteMotionNames.indexOf(motionName))];
    return Sprite._(
      id: id,
      title: j['title'] as String? ?? id,
      category: j['category'] as String? ?? category,
      tags: [for (final t in (j['tags'] as List? ?? const [])) t as String],
      palette: j['palette'] as String? ?? 'rainbow',
      motion: motion,
      width: w,
      height: h,
      backdrop: (j['backdrop'] as num?)?.toDouble() ?? 0,
      frames: frames,
      inks: inks,
      seq: seq,
      ms: ms,
      pack: packId,
      source: (j['source'] as Map?)?.cast<String, dynamic>(),
    );
  }

  static List<String> _buildFrame(Object? spec, List<List<String>> built,
      Map<String, List<String>> parts, String id) {
    if (spec is List) return [for (final r in spec) r as String];
    if (spec is! Map) throw FormatException('$id: bad frame');
    final base = spec['base'];
    var rows = switch (base) {
      int i when i >= 0 && i < built.length => List.of(built[i]),
      String name when parts.containsKey(name) => List.of(parts[name]!),
      _ => throw FormatException('$id: unknown base $base'),
    };
    for (final p in (spec['patch'] as List? ?? const [])) {
      final at = p['at'] as List;
      final px = at[0] as int, py = at[1] as int;
      final prow = [for (final r in p['rows'] as List) r as String];
      for (var dy = 0; dy < prow.length; dy++) {
        final y = py + dy;
        if (y < 0 || y >= rows.length) continue;
        final chars = rows[y].split('');
        for (var dx = 0; dx < prow[dy].length; dx++) {
          final x = px + dx;
          final ch = prow[dy][dx];
          if (ch == ' ' || ch == '.' || x < 0 || x >= chars.length) continue;
          chars[x] = ch == '_' ? '.' : ch;
        }
        rows[y] = chars.join();
      }
    }
    final shift = spec['shift'] as List?;
    if (shift != null) {
      final sx = shift[0] as int, sy = shift[1] as int;
      final w = rows.first.length, h = rows.length;
      rows = [
        for (var y = 0; y < h; y++)
          String.fromCharCodes([
            for (var x = 0; x < w; x++)
              (x - sx >= 0 && x - sx < w && y - sy >= 0 && y - sy < h)
                  ? rows[y - sy].codeUnitAt(x - sx)
                  : 46,
          ]),
      ];
    }
    switch (spec['flip']) {
      case 'h':
        rows = [for (final r in rows) r.split('').reversed.join()];
      case 'v':
        rows = rows.reversed.toList();
    }
    return rows;
  }
}

/// Plays a [Sprite] centred and scaled to the matrix. Params: `speed`
/// scales playback, `motion` picks a movement (see [SpriteMotion]), and
/// `backdrop` fills transparent pixels with a soft palette glow.
class SpriteGenerator extends Generator {
  SpriteGenerator(this.sprite);

  final Sprite sprite;

  static const prefix = 'sprite:';

  @override
  String get id => '$prefix${sprite.id}';
  @override
  String get name => sprite.title;
  @override
  String get defaultPalette => sprite.palette;
  @override
  List<ParamSpec> get params => [
        const ParamSpec('speed', 'Speed', min: 0.25, max: 3, defaultValue: 1),
        ParamSpec('motion', 'Motion', min: 0, max: 6, defaultValue: sprite.motion.index.toDouble()),
        ParamSpec('backdrop', 'Backdrop', defaultValue: sprite.backdrop),
      ];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _SpriteInstance(sprite, width, height, Random(seed));

  /// Seconds of effect time after which the sprite repeats exactly on a
  /// [width]×[height] matrix: a common multiple of its frame sequence, its
  /// motion and any colour-cycling inks, divided by the `speed` param. Null
  /// when that is longer than [maxSeconds] even without the colour cycle.
  /// Twinkling inks, the slow backdrop drift and shake's random jitter have
  /// no practical period and are ignored.
  double? loopSeconds(Params p, int width, int height, {double maxSeconds = 12}) {
    final speed = p['speed'].clamp(0.05, 10).toDouble();
    final motion = SpriteMotion.values[p['motion'].round().clamp(0, 6)];
    // Periods as exact fractions of a second (numerator, denominator).
    // A sequence that shows one frame throughout (scrolling text) has no
    // period of its own.
    final seq = {...sprite.seq}.length > 1 ? _Ratio(sprite.loopMs, 1000) : null;
    final move = switch (motion) {
      SpriteMotion.bounce => _Ratio(7, 10), // |sin(t·π/0.7)|
      SpriteMotion.float => _Ratio(13, 5),
      SpriteMotion.sway => _Ratio(11, 5),
      SpriteMotion.pulse => _Ratio(11, 10),
      SpriteMotion.scroll => () {
          // travel px at max(4, 0.45·w) px/s, as in render().
          final travel = width + _fit(sprite, width, height).$2 + 2;
          return width * 0.45 > 4 ? _Ratio(20 * travel, 9 * width) : _Ratio(travel, 4);
        }(),
      SpriteMotion.still || SpriteMotion.shake => null,
    };
    final cycles = sprite._inks.any((i) => i.kind == 2); // pal.at(v + t/4)
    for (final parts in [
      [?seq, ?move, if (cycles) _Ratio(4, 1)],
      [?seq, ?move],
    ]) {
      if (parts.isEmpty) continue;
      final l = parts.reduce((a, b) => a.lcm(b));
      final s = l.seconds / speed;
      if (s.isFinite && s <= maxSeconds) return s;
    }
    return null;
  }
}

/// A positive rational number of seconds, for exact loop lengths.
class _Ratio {
  _Ratio(int n, int d) : this._(n ~/ _gcd(n, d), d ~/ _gcd(n, d));
  const _Ratio._(this.n, this.d);

  final int n, d;

  static int _gcd(int a, int b) => b == 0 ? a.abs() : _gcd(b, a % b);

  /// Least common multiple: lcm(a/b, c/d) = lcm(a, c) / gcd(b, d).
  _Ratio lcm(_Ratio o) {
    final g = _gcd(n, o.n);
    // Past ~2^40 the loop is far too long to bake anyway.
    if (n ~/ g > (1 << 40) ~/ max(1, o.n)) return const _Ratio._(1 << 40, 1);
    return _Ratio(n ~/ g * o.n, _gcd(d, o.d));
  }

  double get seconds => n / d;
}

/// Integer upscale (0 when shrinking) and drawn size of [s] on a w×h matrix.
(int, int, int) _fit(Sprite s, int w, int h) {
  // Wide banners (scrolling text) fit by height and scroll across.
  final fit = s.isBanner ? h / s.height : min(w / s.width, h / s.height);
  if (fit >= 1) {
    final k = fit.floor();
    return (k, s.width * k, s.height * k);
  }
  return (0, max(1, (s.width * fit).round()), max(1, (s.height * fit).round()));
}

class _SpriteInstance extends EffectInstance {
  _SpriteInstance(this.s, this.w, this.h, this._rnd)
      : _src = Uint32List(s.width * s.height) {
    final (k, fw, fh) = _fit(s, w, h);
    _scale = k;
    dw = fw;
    dh = fh;
    _img = Uint32List(dw * dh);
  }

  final Sprite s;
  final int w, h;
  final Random _rnd;
  final Uint32List _src;
  late Uint32List _img;
  late int dw, dh;
  int _scale = 0; // integer upscale, or 0 when area-downsampling
  double _ms = 0, _t = 0;
  int _jx = 0, _jy = 0;
  double _nextJitter = 0;

  void _scaleInto() {
    if (_scale > 0) {
      for (var y = 0; y < dh; y++) {
        final sy = y ~/ _scale;
        for (var x = 0; x < dw; x++) {
          _img[y * dw + x] = _src[sy * s.width + x ~/ _scale];
        }
      }
      return;
    }
    // Area-average, so a 16x16 drawing still reads at 8x8.
    for (var y = 0; y < dh; y++) {
      final y0 = y * s.height / dh, y1 = (y + 1) * s.height / dh;
      for (var x = 0; x < dw; x++) {
        final x0 = x * s.width / dw, x1 = (x + 1) * s.width / dw;
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0, total = 0.0;
        for (var sy = y0.floor(); sy < y1.ceil() && sy < s.height; sy++) {
          final wy = min(y1, sy + 1.0) - max(y0, sy.toDouble());
          for (var sx = x0.floor(); sx < x1.ceil() && sx < s.width; sx++) {
            final wgt = wy * (min(x1, sx + 1.0) - max(x0, sx.toDouble()));
            total += wgt;
            final c = _src[sy * s.width + sx];
            if (c == 0) continue;
            a += wgt;
            r += ((c >> 16) & 0xFF) * wgt;
            g += ((c >> 8) & 0xFF) * wgt;
            b += (c & 0xFF) * wgt;
          }
        }
        // Mostly-empty cells fade rather than vanish, so thin lines and
        // single-pixel stars survive the shrink as dim pixels.
        final k = min(1.0, a / total / 0.5);
        _img[y * dw + x] = k < 0.05
            ? 0
            : 0xFF000000 | rgb((r / a * k).round(), (g / a * k).round(), (b / a * k).round());
      }
    }
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final speed = p['speed'].clamp(0.05, 10);
    _ms += dt * 1000 * speed;
    _t += dt * speed;
    s.resolve(s.seq[s.stepAt(_ms)], pal, _t, _src);
    _scaleInto();

    final motion = SpriteMotion.values[p['motion'].round().clamp(0, 6)];
    final amp = max(1, (min(w, h) * 0.07).round());
    var ox = (w - dw) / 2, oy = (h - dh) / 2;
    var zoom = 1.0;
    switch (motion) {
      case SpriteMotion.still:
        break;
      case SpriteMotion.bounce:
        oy -= (sin(_t * pi / 0.7).abs() * amp * 1.5).roundToDouble();
        oy += amp * 0.5;
      case SpriteMotion.float:
        oy += (sin(_t * 2 * pi / 2.6) * amp).roundToDouble();
      case SpriteMotion.sway:
        ox += (sin(_t * 2 * pi / 2.2) * amp).roundToDouble();
      case SpriteMotion.scroll:
        final travel = w + dw + 2;
        ox = w - ((_t * max(4.0, w * 0.45)) % travel).floorToDouble();
      case SpriteMotion.pulse:
        zoom = 1 + 0.09 * sin(_t * 2 * pi / 1.1);
      case SpriteMotion.shake:
        if (_t >= _nextJitter) {
          _jx = _rnd.nextInt(3) - 1;
          _jy = _rnd.nextInt(3) - 1;
          _nextJitter = _t + 0.08;
        }
        ox += _jx;
        oy += _jy;
    }

    final back = p['backdrop'];
    final cx = ox + dw / 2, cy = oy + dh / 2;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // Map the output pixel back into the scaled image (zoom about centre).
        final ix = ((x + 0.5 - cx) / zoom + dw / 2).floor();
        final iy = ((y + 0.5 - cy) / zoom + dh / 2).floor();
        var c = 0;
        if (ix >= 0 && iy >= 0 && ix < dw && iy < dh) c = _img[iy * dw + ix];
        if (c == 0) {
          out.set(x, y, back <= 0.01 ? 0 : scaleColor(pal.at(0.15 + 0.35 * y / h + _t * 0.02), back * 0.35));
        } else {
          out.set(x, y, c & 0xFFFFFF);
        }
      }
    }
  }
}
