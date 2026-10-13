// Renders deterministic samples through Glyph's player at both device sizes.
// dart run tool/pipplee_preview.dart [output directory]
import 'dart:io';
import 'dart:typed_data';

import 'package:glyph/engine/clip_asset.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/library/pipplee_collection.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final output = args.isEmpty ? 'build/pipplee/preview' : args.first;
  Directory(output).createSync(recursive: true);
  final collection = parsePippleeCollection(
    File(pippleeIndexAsset).readAsStringSync(),
  );
  final samples = [
    ...collection.items.take(6),
    for (final size in ['8x8', '32x8', '8x32', '32x16', '32x32', '64x64'])
      collection.items.firstWhere((item) => item.tags.contains(size)),
  ];
  final generators = [
    for (final item in samples)
      () {
        final generator = ClipAssetLibrary.byId(item.generatorId)!;
        final bytes = File(
          'catalog_assets/pipplee/${generator.asset.sha256}.clip.gz',
        ).readAsBytesSync();
        return generator.loaded(
          decodeClipAsset(
            Uint8List.fromList(gzip.decode(bytes)),
            generator.asset,
          ),
        );
      }(),
  ];
  final instances = [
    for (final g in generators) [g.create(16, 16, 1), g.create(32, 32, 1)],
  ];
  const cols = 3, tileWidth = 300, tileHeight = 184;
  final encoder = img.GifEncoder(repeat: 0);
  for (var step = 0; step < 30; step++) {
    final sheet = img.Image(width: cols * tileWidth, height: 4 * tileHeight);
    img.fill(sheet, color: img.ColorRgb8(11, 10, 9));
    for (var i = 0; i < samples.length; i++) {
      final x = i % cols * tileWidth, y = i ~/ cols * tileHeight;
      img.drawString(
        sheet,
        samples[i].title,
        font: img.arial14,
        x: x + 12,
        y: y + 8,
        color: img.ColorRgb8(232, 225, 218),
      );
      for (var view = 0; view < 2; view++) {
        final n = view == 0 ? 16 : 32, cell = view == 0 ? 6 : 4;
        final frame = Frame(n, n);
        final g = generators[i];
        instances[i][view].render(
          frame,
          step / 10,
          0.1,
          Params.defaultsFor(g),
          paletteById(g.defaultPalette),
        );
        final x0 = x + (view == 0 ? 12 : 136), y0 = y + 34;
        for (var py = 0; py < n; py++) {
          for (var px = 0; px < n; px++) {
            final c = frame.get(px, py);
            img.fillRect(
              sheet,
              x1: x0 + px * cell,
              y1: y0 + py * cell,
              x2: x0 + (px + 1) * cell - 2,
              y2: y0 + (py + 1) * cell - 2,
              color: img.ColorRgb8(c >> 16, (c >> 8) & 255, c & 255),
            );
          }
        }
        img.drawString(
          sheet,
          '${n}x$n',
          font: img.arial14,
          x: x0,
          y: y + 164,
          color: img.ColorRgb8(165, 157, 149),
        );
      }
    }
    if (step == 7) {
      File('$output/samples.png').writeAsBytesSync(img.encodePng(sheet));
    }
    encoder.addFrame(sheet, duration: 10);
  }
  File('$output/samples.gif').writeAsBytesSync(encoder.finish()!);
  stdout.writeln('$output: ${samples.length} samples at 16×16 and 32×32');
}
