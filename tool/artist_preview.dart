// Renders the CC0 collection through Glyph's actual player at 16x16 and 32x32.
// dart run tool/artist_preview.dart [output directory]
import 'dart:io';

import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/engine/palette.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final out = args.isEmpty ? 'build/artist_preview' : args.first;
  Directory(out).createSync(recursive: true);
  final sprites = SpriteLibrary.all
      .where((g) => g.sprite.source?['license'] == 'CC0-1.0')
      .toList();
  const cols = 3, tileW = 300, tileH = 184;
  final rows = (sprites.length / cols).ceil();
  final encoder = img.GifEncoder(repeat: 0);
  final featuredEncoder = img.GifEncoder(repeat: 0);
  final featuredIndices = [
    for (final id in [
      'bubble-laughing',
      'bubble-cute',
      'bubble-headblown',
      'living-flame',
      'copper-parrot',
      'jelly-squish',
    ])
      sprites.indexWhere((g) => g.id == 'sprite:$id'),
  ];
  final instances = [
    for (final g in sprites) [g.create(16, 16, 1), g.create(32, 32, 1)],
  ];
  // Six seconds includes whole flame and bird cycles and multiple expressions.
  for (var step = 0; step < 60; step++) {
    final sheet = img.Image(width: cols * tileW, height: rows * tileH);
    img.fill(sheet, color: img.ColorRgb8(15, 15, 20));
    for (var k = 0; k < sprites.length; k++) {
      final g = sprites[k];
      final ox = k % cols * tileW, oy = k ~/ cols * tileH;
      img.drawString(
        sheet,
        g.name,
        font: img.arial14,
        x: ox + 12,
        y: oy + 8,
        color: img.ColorRgb8(235, 235, 240),
      );
      for (var view = 0; view < 2; view++) {
        final n = view == 0 ? 16 : 32, cell = view == 0 ? 6 : 4;
        final px = Frame(n, n);
        instances[k][view].render(
          px,
          step / 10,
          0.1,
          Params.defaultsFor(g),
          paletteById(g.defaultPalette),
        );
        final x0 = ox + (view == 0 ? 12 : 136), y0 = oy + 34;
        for (var y = 0; y < n; y++) {
          for (var x = 0; x < n; x++) {
            final c = px.get(x, y);
            img.fillRect(
              sheet,
              x1: x0 + x * cell,
              y1: y0 + y * cell,
              x2: x0 + (x + 1) * cell - 2,
              y2: y0 + (y + 1) * cell - 2,
              color: img.ColorRgb8((c >> 16) & 255, (c >> 8) & 255, c & 255),
            );
          }
        }
        img.drawString(
          sheet,
          '${n}x$n',
          font: img.arial14,
          x: x0,
          y: oy + 164,
          color: img.ColorRgb8(160, 160, 175),
        );
      }
    }
    encoder.addFrame(sheet, duration: 10);
    final featured = img.Image(width: cols * tileW, height: 2 * tileH);
    for (var i = 0; i < featuredIndices.length; i++) {
      final k = featuredIndices[i];
      img.compositeImage(
        featured,
        sheet,
        srcX: k % cols * tileW,
        srcY: k ~/ cols * tileH,
        srcW: tileW,
        srcH: tileH,
        dstW: tileW,
        dstH: tileH,
        dstX: i % cols * tileW,
        dstY: i ~/ cols * tileH,
      );
    }
    featuredEncoder.addFrame(featured, duration: 10);
    if (step == 7) {
      File('$out/collection.png').writeAsBytesSync(img.encodePng(sheet));
      File('$out/highlights.png').writeAsBytesSync(img.encodePng(featured));
    }
  }
  File('$out/collection.gif').writeAsBytesSync(encoder.finish()!);
  File('$out/highlights.gif').writeAsBytesSync(featuredEncoder.finish()!);
  stdout.writeln('$out: ${sprites.length} animations at both device sizes');
}
