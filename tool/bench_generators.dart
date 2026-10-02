// Prints the average render cost of every generator.
//
//   dart run tool/bench_generators.dart [WxH]
import 'dart:io';

import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';

void main(List<String> args) {
  final s = (args.isEmpty ? '32x32' : args[0]).split('x').map(int.parse).toList();
  final rows = <(String, double)>[];
  for (final g in generators) {
    final inst = g.create(s[0], s[1], 1);
    final f = Frame(s[0], s[1]);
    final p = Params.defaultsFor(g);
    final pal = paletteById(g.defaultPalette);
    const n = 200;
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      inst.render(f, i / 30, 1 / 30, p, pal);
    }
    rows.add((g.id, sw.elapsedMicroseconds / n / 1000));
  }
  rows.sort((a, b) => b.$2.compareTo(a.$2));
  for (final (id, ms) in rows) {
    stdout.writeln('${id.padRight(14)} ${ms.toStringAsFixed(3)} ms');
  }
}
