// Renders a sample of catalog items (one frame each, at 2.5 s) to a PNG grid,
// for eyeballing palettes and params in bulk.
//
//   dart run tool/catalog_preview.dart [regex on id/category] [out.png]
import 'dart:io';

import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/catalog.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final sw = Stopwatch()..start();
  final catalog = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync());
  final filter = RegExp(args.isEmpty ? '.' : args[0]);
  final items = catalog.items.where((i) => filter.hasMatch(i.id) || filter.hasMatch(i.category)).take(120).toList();
  const cols = 12, cell = 5, gap = 6, n = 16;
  final rows = (items.length / cols).ceil();
  final sheet = img.Image(width: cols * (n * cell + gap) + gap, height: rows * (n * cell + gap) + gap);
  img.fill(sheet, color: img.ColorRgb8(36, 36, 44));
  for (var k = 0; k < items.length; k++) {
    final i = items[k];
    final g = generatorById(i.generatorId);
    final inst = g.create(n, n, i.id.hashCode);
    final f = Frame(n, n);
    final p = Params.defaultsFor(g, i.params);
    final pal = paletteById(i.paletteId);
    for (var s = 0; s < 75; s++) {
      inst.render(f, s / 30 * (i.speed ?? 1), 1 / 30 * (i.speed ?? 1), p, pal);
    }
    final ox = gap + (k % cols) * (n * cell + gap), oy = gap + (k ~/ cols) * (n * cell + gap);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final c = f.get(x, y);
        img.fillRect(sheet, x1: ox + x * cell, y1: oy + y * cell, x2: ox + x * cell + cell - 2, y2: oy + y * cell + cell - 2,
            color: img.ColorRgb8((c >> 16) & 255, (c >> 8) & 255, c & 255));
      }
    }
  }
  final out = args.length > 1 ? args[1] : 'build/catalog_preview.png';
  File(out)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(sheet));
  stdout.writeln('$out: ${items.length} items in ${sw.elapsedMilliseconds} ms');
}
