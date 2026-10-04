// Draws the GitHub social preview (docs/media/social_preview.png, 1280×640):
// the amber dot "g", the name in LED letters, and a row of real library
// animations as little LED panels.
//
//   dart run tool/make_social.dart
//
// Upload it in the repo's Settings → Social preview.
import 'dart:convert';
import 'dart:io';

import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/features/text/fonts.dart';
import 'package:image/image.dart' as img;

const _w = 1280, _h = 640, _ss = 2;
const _bg = 0xFF0B0A09, _off = 0xFF1D1A17, _amber = 0xFFFFB547, _grey = 0xFF8C857B;

img.ColorRgba8 _c(int argb) => img.ColorRgba8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, 0xFF);

void _dot(img.Image im, double x, double y, double r, int color) =>
    img.fillCircle(im, x: (x * _ss).round(), y: (y * _ss).round(), radius: (r * _ss).round(), color: _c(color), antialias: true);

/// [text] in LED dots, top-left at ([x], [y]), [cell] px per LED.
double _ledText(img.Image im, String text, BitmapFont font, double x, double y, double cell, int color) {
  var cx = x;
  for (final r in text.runes) {
    final g = font.glyph(r);
    for (var gy = 0; gy < font.capHeight; gy++) {
      for (var gx = 0; gx < g.width; gx++) {
        if (gy < g.rows.length && g.on(gx, gy)) _dot(im, cx + (gx + 0.5) * cell, y + (gy + 0.5) * cell, cell * 0.38, color);
      }
    }
    cx += (g.width + font.spacing) * cell;
  }
  return cx;
}

/// One library item rendered [t] seconds in, drawn as a 16×16 LED panel.
void _panel(img.Image im, Map<String, dynamic> item, double x, double y, double size) {
  final g = generatorById(item['generator'] as String);
  final params = Params.defaultsFor(g, {
    for (final e in ((item['params'] as Map?) ?? {}).entries) e.key as String: (e.value as num).toDouble(),
  });
  final pal = paletteById((item['palette'] as String?) ?? g.defaultPalette);
  final fx = g.create(16, 16, 7);
  final f = Frame(16, 16);
  for (var i = 0; i <= 90; i++) {
    fx.render(f, i / 30, 1 / 30, params, pal);
  }
  final cell = size / 16;
  img.fillRect(im,
      x1: ((x - 6) * _ss).round(), y1: ((y - 6) * _ss).round(), x2: ((x + size + 6) * _ss).round(), y2: ((y + size + 6) * _ss).round(),
      color: _c(0xFF131210), radius: 3 * _ss);
  for (var py = 0; py < 16; py++) {
    for (var px = 0; px < 16; px++) {
      final c = f.get(px, py);
      _dot(im, x + (px + 0.5) * cell, y + (py + 0.5) * cell, cell * 0.4, c == 0 ? _off : 0xFF000000 | c);
    }
  }
}

void main() {
  final im = img.Image(width: _w * _ss, height: _h * _ss, numChannels: 4);
  img.fill(im, color: _c(_bg));

  // The icon's "g", large, on the left.
  const g = ['.###.', '#...#', '#...#', '.####', '....#', '#...#', '.###.'];
  const pitch = 30.0, gx = 110.0, gy = 70.0;
  for (var r = 0; r < g.length; r++) {
    for (var c = 0; c < 5; c++) {
      if (g[r][c] == '#') _dot(im, gx + c * pitch, gy + r * pitch, 11, _amber);
    }
  }

  _ledText(im, 'GLYPH', classicFont, 330, 70, 15, 0xFFF3EFE8);
  _ledText(im, 'YOUR LED MATRIX, ALIVE', tinyFont, 334, 205, 7, _amber);
  _ledText(im, 'FREE  OPEN SOURCE  NO ACCOUNT', tinyFont, 334, 262, 5, _grey);

  // A shelf of real animations from the library.
  final catalog = jsonDecode(File('assets/catalog/catalog.json').readAsStringSync()) as Map<String, dynamic>;
  final items = (catalog['items'] as List).cast<Map<String, dynamic>>();
  const picks = ['ocean-plasma', 'kitty-bounce', 'campfire', 'the-starry-night', 'steamboat-whistle-1928', 'retro-tunnel'];
  final chosen = [
    for (final id in picks) ...items.where((i) => i['id'] == id),
    ...items.where((i) => !picks.contains(i['id'])),
  ].take(6).toList();
  const size = 160.0, gap = 38.0, top = 380.0;
  final left = (_w - (6 * size + 5 * gap)) / 2;
  for (var i = 0; i < chosen.length; i++) {
    _panel(im, chosen[i], left + i * (size + gap), top, size);
  }

  final out = img.copyResize(im, width: _w, height: _h, interpolation: img.Interpolation.average);
  File('docs/media/social_preview.png').writeAsBytesSync(img.encodePng(out));
  stdout.writeln('wrote docs/media/social_preview.png (${chosen.map((i) => i['id']).join(', ')})');
}
