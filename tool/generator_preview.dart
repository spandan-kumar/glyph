// Renders generator frames to a PNG contact sheet for visual review.
//
//   dart run tool/generator_preview.dart [ids,comma,separated|all] [WxH] [out.png]
import 'dart:io';

import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final ids = args.isEmpty || args[0] == 'all'
      ? generators.map((g) => g.id).toList()
      : args[0].split(',');
  final size = (args.length > 1 ? args[1] : '16x16').split('x').map(int.parse).toList();
  final outPath = args.length > 2 ? args[2] : 'build/generator_preview.png';
  final w = size[0], h = size[1];
  const cols = 8, cell = 8, gap = 4;
  final times = [for (var i = 0; i < cols; i++) 1.5 + i * 0.5];
  final sheet = img.Image(
      width: cols * (w * cell + gap) + gap, height: ids.length * (h * cell + gap) + gap);
  img.fill(sheet, color: img.ColorRgb8(40, 40, 48));
  for (var row = 0; row < ids.length; row++) {
    final g = findGenerator(ids[row]);
    if (g == null) {
      stderr.writeln('unknown generator ${ids[row]}');
      continue;
    }
    final inst = g.create(w, h, 7);
    final f = Frame(w, h);
    final params = Params.defaultsFor(g);
    final pal = paletteById(g.defaultPalette);
    var t = 0.0, col = 0;
    const dt = 1 / 30;
    while (col < cols) {
      inst.render(f, t, dt, params, pal);
      t += dt;
      if (t >= times[col]) {
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final c = f.get(x, y);
            final ox = gap + col * (w * cell + gap) + x * cell;
            final oy = gap + row * (h * cell + gap) + y * cell;
            img.fillRect(sheet,
                x1: ox, y1: oy, x2: ox + cell - 2, y2: oy + cell - 2,
                color: img.ColorRgb8((c >> 16) & 255, (c >> 8) & 255, c & 255));
          }
        }
        col++;
      }
    }
  }
  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(sheet));
  stdout.writeln('wrote $outPath (${ids.length} generators)');
}
