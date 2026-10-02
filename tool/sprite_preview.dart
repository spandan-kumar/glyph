// Renders sprite packs to PNG sheets for visual review: one row per sprite,
// every frame of its sequence at 16x16 (or native size), then an 8x8
// downscale.
//
//   dart run tool/sprite_preview.dart [pack.json ...] [--out dir] [--only regex]
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/generators/sprite.dart';
import 'package:glyph/engine/palette.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  var outDir = 'build/sprite_preview';
  final files = <String>[];
  RegExp? only;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out') {
      outDir = args[++i];
    } else if (args[i] == '--only') {
      only = RegExp(args[++i]);
    } else {
      files.add(args[i]);
    }
  }
  if (files.isEmpty) {
    files.addAll(Directory('assets/catalog/sprites')
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.json')));
  }
  Directory(outDir).createSync(recursive: true);
  for (final path in files) {
    final sprites = Sprite.parsePack(File(path).readAsStringSync())
        .where((s) => only == null || only.hasMatch(s.id))
        .toList();
    if (sprites.isEmpty) continue;
    const cell = 6, gap = 6;
    final most = sprites.fold(1, (m, s) => max(m, {...s.seq}.length));
    final maxCols = min(9, most + 1);
    final widest = sprites.fold(16, (m, s) => max(m, s.width));
    final sheet = img.Image(width: max(maxCols * (16 * cell + gap), widest * cell + 16 * cell + gap * 2) + gap + 120, height: sprites.length * (16 * cell + gap) + gap);
    img.fill(sheet, color: img.ColorRgb8(36, 36, 44));
    for (var row = 0; row < sprites.length; row++) {
      final s = sprites[row];
      final pal = paletteById(s.palette);
      final buf = Uint32List(s.width * s.height);
      final frames = <int>{...s.seq}.toList();
      var col = 0;
      void blit(Uint32List px, int w, int h, int c) {
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final v = px[y * w + x];
            final ox = gap + c * (max(16, w) * cell + gap) + x * cell, oy = gap + row * (16 * cell + gap) + y * cell;
            if (ox + cell > sheet.width) continue;
            final color = v == 0 ? img.ColorRgb8(8, 8, 12) : img.ColorRgb8((v >> 16) & 255, (v >> 8) & 255, v & 255);
            img.fillRect(sheet, x1: ox, y1: oy, x2: ox + cell - 2, y2: oy + cell - 2, color: color);
          }
        }
      }

      for (final f in frames.take(maxCols - 1)) {
        s.resolve(f, pal, 0.3, buf);
        blit(buf, s.width, s.height, col++);
      }
      // 8x8 downscale through the real generator.
      final g = SpriteGenerator(s);
      final inst = g.create(8, 8, 1);
      final fr = Frame(8, 8);
      inst.render(fr, 0, 0, Params.defaultsFor(g, {'motion': 0}), pal);
      final small = Uint32List(64);
      for (var i = 0; i < 64; i++) {
        final c = fr.get(i % 8, i ~/ 8);
        small[i] = c == 0 ? 0 : 0xFF000000 | c;
      }
      blit(small, 8, 8, maxCols - 1);
      img.drawString(sheet, s.id, font: img.arial14,
          x: maxCols * (16 * cell + gap) + gap, y: gap + row * (16 * cell + gap) + 40,
          color: img.ColorRgb8(220, 220, 230));
    }
    final name = File(path).uri.pathSegments.last.replaceAll('.json', '.png');
    File('$outDir/$name').writeAsBytesSync(img.encodePng(sheet));
    stdout.writeln('$outDir/$name: ${sprites.length} sprites');
  }
}
