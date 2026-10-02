import 'dart:math';
import 'dart:typed_data';

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../../engine/registry.dart';
import 'fonts.dart';
import 'text_settings.dart';

/// Rasterised text: each pixel holds the index of the character that lit it
/// (counting across all lines), or -1.
class TextMask {
  TextMask._(this.width, this.height, this.chars)
      : idx = Int16List(max(1, width * height))..fillRange(0, max(1, width * height), -1);

  /// One line in [font], full cell height.
  factory TextMask.line(BitmapFont font, String text) => TextMask.lines(font, [text]);

  /// Lines stacked with [gap] rows between them, each centred horizontally.
  /// With [trim] each line only takes the rows its glyphs use, which keeps
  /// stacked digits tight.
  factory TextMask.lines(BitmapFont font, List<String> lines,
      {int gap = 1, bool trim = false}) {
    final rowSpans = [
      for (final l in lines) trim ? _inkRows(font, l) : (0, font.height),
    ];
    final w = lines.fold<int>(0, (m, l) => max(m, font.measure(l)));
    final int h = rowSpans.fold<int>(0, (a, s) => a + s.$2 - s.$1) + gap * max(0, lines.length - 1);
    final chars = [for (final l in lines) ...l.runes];
    final m = TextMask._(w, h, chars);
    var y0 = 0, ci = 0;
    for (var li = 0; li < lines.length; li++) {
      final (top, bottom) = rowSpans[li];
      var x = (w - font.measure(lines[li])) ~/ 2;
      for (final r in lines[li].runes) {
        final g = font.glyph(r);
        for (var y = top; y < bottom; y++) {
          for (var gx = 0; gx < g.width; gx++) {
            if (g.on(gx, y)) m.idx[(y0 + y - top) * w + x + gx] = ci;
          }
        }
        x += g.width + font.spacing;
        ci++;
      }
      y0 += bottom - top + gap;
    }
    return m;
  }

  final int width;
  final int height;
  final Int16List idx;

  /// Runes in index order, so painters can treat e.g. ':' specially.
  final List<int> chars;

  int at(int x, int y) =>
      x < 0 || y < 0 || x >= width || y >= height ? -1 : idx[y * width + x];

  bool get isBlank => !idx.any((v) => v >= 0);

  static (int, int) _inkRows(BitmapFont font, String text) {
    var top = font.height, bottom = 0;
    for (final r in text.runes) {
      final g = font.glyph(r);
      for (var y = 0; y < font.height; y++) {
        if (g.rows[y] != 0) {
          top = min(top, y);
          bottom = max(bottom, y + 1);
        }
      }
    }
    return top >= bottom ? (0, font.capHeight) : (top, bottom);
  }
}

/// Colour for a lit pixel at screen ([x], [y]); [u] is the position across
/// the text (0..1) and [ch] the character index. Returning -1 skips it.
typedef Colorizer = int Function(int x, int y, double u, int ch);

/// Draws [m] at ([ox], [oy]) with each mask pixel as a [scale]² block.
/// Outline and shadow are drawn in [fxColor] under the text.
void paintMask(Frame out, TextMask m, int ox, int oy, int scale, Colorizer color,
    {String effect = 'none', int fxColor = 0x000000}) {
  final x0 = max(0, (-ox - 2) ~/ scale), x1 = min(m.width, (out.width - ox) ~/ scale + 2);
  final y0 = max(0, (-oy - 2) ~/ scale), y1 = min(m.height, (out.height - oy) ~/ scale + 2);
  if (x1 <= x0 || y1 <= y0) return;

  void block(int px, int py, int w, int h, int c) {
    for (var y = py; y < py + h; y++) {
      for (var x = px; x < px + w; x++) {
        out.set(x, y, c);
      }
    }
  }

  if (effect == 'outline' || effect == 'shadow') {
    for (var my = y0; my < y1; my++) {
      for (var mx = x0; mx < x1; mx++) {
        if (m.idx[my * m.width + mx] < 0) continue;
        final px = ox + mx * scale, py = oy + my * scale;
        if (effect == 'outline') {
          block(px - 1, py - 1, scale + 2, scale + 2, fxColor);
        } else {
          block(px + 1, py + 1, scale, scale, fxColor);
        }
      }
    }
  }
  final inv = m.width <= 1 ? 0.0 : 1 / (m.width - 1);
  for (var my = y0; my < y1; my++) {
    for (var mx = x0; mx < x1; mx++) {
      final ch = m.idx[my * m.width + mx];
      if (ch < 0) continue;
      final px = ox + mx * scale, py = oy + my * scale;
      final c = color(px, py, mx * inv, ch);
      if (c < 0) continue;
      block(px, py, scale, scale, c);
    }
  }
}

final _rainbow = paletteById('rainbow');

/// Turns [TextSettings] colour options into a [Colorizer] for time [t].
Colorizer textColorizer(TextSettings s, int width, double t) {
  final pal = paletteById(s.palette);
  return switch (s.colorMode) {
    'gradient' => (x, y, u, ch) => pal.at(u * 0.85),
    'rainbow' => (x, y, u, ch) => _rainbow.at(ch * 0.11 + t * 0.15),
    'animated' => (x, y, u, ch) => pal.at((x + y * 0.5) / max(8, width) * 0.6 - t * 0.25),
    _ => (x, y, u, ch) => s.color & 0xFFFFFF,
  };
}

/// Integer glyph scale for a font on a matrix [height] tall.
int autoScale(BitmapFont font, int height, bool large) =>
    large ? max(1, (height + 1) ~/ (font.height + 1)) : 1;

/// First font of [fallbacks] whose cell fits [height], else the smallest.
BitmapFont fontForHeight(List<BitmapFont> fallbacks, int height) =>
    fallbacks.firstWhere((f) => f.capHeight <= height, orElse: () => fallbacks.last);

/// Greedy word wrap to [maxWidth] pixels; words longer than a line are split.
List<String> wrapText(BitmapFont font, String text, int maxWidth) {
  final lines = <String>[];
  for (final para in text.split('\n')) {
    var line = '';
    for (final word in para.split(' ').where((w) => w.isNotEmpty)) {
      final candidate = line.isEmpty ? word : '$line $word';
      if (font.measure(candidate) <= maxWidth) {
        line = candidate;
        continue;
      }
      if (line.isNotEmpty) lines.add(line);
      line = '';
      var rest = word;
      while (font.measure(rest) > maxWidth && rest.runes.length > 1) {
        final runes = rest.runes.toList();
        var n = runes.length - 1;
        while (n > 1 && font.measure(String.fromCharCodes(runes.take(n))) > maxWidth) {
          n--;
        }
        lines.add(String.fromCharCodes(runes.take(n)));
        rest = String.fromCharCodes(runes.skip(n));
      }
      line = rest;
    }
    if (line.isNotEmpty) lines.add(line);
  }
  return lines;
}

class FitChoice {
  const FitChoice(this.font, this.scale, this.lines);

  final BitmapFont font;
  final int scale;
  final List<String> lines;

  int get gap => scale;

  int width() => lines.fold(0, (m, l) => max(m, font.measure(l))) * scale;

  /// Height when lines are trimmed to cap height.
  int height() => lines.length * font.capHeight * scale + (lines.length - 1) * gap;
}

/// Picks the layout for fixed-format text (clock digits, countdowns).
///
/// [groups] are ordered from most to least detailed; each group holds
/// equivalent layouts (e.g. one line vs. stacked). The first group with any
/// layout that fits wins, using its biggest-looking fit; ties keep the
/// earlier font and the earlier layout.
FitChoice? fitText(List<List<List<String>>> groups, List<BitmapFont> fonts, int width,
    int height, {int maxScale = 6}) {
  for (final group in groups) {
    FitChoice? best;
    var bestSize = 0;
    for (final lines in group) {
      for (final font in fonts) {
        for (var s = 1; s <= maxScale; s++) {
          final c = FitChoice(font, s, lines);
          if (c.width() > width || c.height() > height) break;
          final size = font.capHeight * s;
          if (size > bestSize) {
            best = c;
            bestSize = size;
          }
        }
      }
    }
    if (best != null) return best;
  }
  return null;
}

/// A library effect drawn dimmed behind the text, in its own buffer so its
/// trails never smear the letters.
class Backdrop {
  Backdrop(String id, int width, int height, this.dim)
      : _gen = id.isEmpty || !generators.any((g) => g.id == id) ? null : generatorById(id),
        _buf = Frame(width, height) {
    final g = _gen;
    if (g != null) {
      _inst = g.create(width, height, 7);
      _params = Params.defaultsFor(g);
      _pal = paletteById(g.defaultPalette);
    }
  }

  final Generator? _gen;
  final Frame _buf;
  final double dim;
  EffectInstance? _inst;
  Params _params = Params({});
  Palette _pal = palettes.first;

  bool get isEmpty => _gen == null;

  void render(Frame out, double t, double dt) {
    final inst = _inst;
    if (inst == null) {
      out.fill(0);
      return;
    }
    inst.render(_buf, t, dt, _params, _pal);
    final f = dim.clamp(0.0, 1.0);
    for (var i = 0; i < out.rgb.length; i++) {
      out.rgb[i] = (_buf.rgb[i] * f).toInt();
    }
  }
}

/// Moves a mask across the matrix. Distance accumulates from dt, so the mask
/// can be swapped (a ticking clock) without the text jumping.
class Scroller {
  Scroller(this.direction, this.width, this.height);

  /// 'left' | 'right' | 'up'
  final String direction;
  final int width;
  final int height;
  double _pos = 0;

  void advance(double dt, double pps) => _pos += dt * pps;

  /// Top-left of a mask [mw]×[mh] (already scaled) for the current position.
  (int, int) origin(int mw, int mh) {
    if (direction == 'up') {
      final period = mh + height;
      return ((width - mw) ~/ 2, height - (_pos % period).floor());
    }
    final period = mw + width;
    final p = (_pos % period).floor();
    final y = (height - mh) ~/ 2;
    return direction == 'right' ? (p - mw, y) : (width - p, y);
  }
}
