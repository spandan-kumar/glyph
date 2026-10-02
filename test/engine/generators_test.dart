import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';

bool _lit(Frame f) => f.rgb.any((v) => v > 8);

void main() {
  test('generator ids are unique and default palettes exist', () {
    final ids = generators.map((g) => g.id).toList();
    expect(ids.toSet().length, ids.length);
    final paletteIds = palettes.map((p) => p.id).toSet();
    expect(paletteIds.length, palettes.length);
    for (final g in generators) {
      expect(paletteIds, contains(g.defaultPalette), reason: g.id);
      for (final s in g.params) {
        expect(s.min, lessThan(s.max), reason: '${g.id}.${s.key}');
        expect(s.defaultValue, inInclusiveRange(s.min, s.max),
            reason: '${g.id}.${s.key}');
      }
    }
  });

  const sizes = [(16, 16), (8, 32), (32, 8), (5, 3), (1, 1)];
  for (final g in generators) {
    for (final (w, h) in sizes) {
      test('${g.id} renders at ${w}x$h', () {
        final pal = paletteById(g.defaultPalette);
        final effect = g.create(w, h, 7);
        final out = Frame(w, h);
        final params = Params.defaultsFor(g);
        const dt = 1 / 30;
        var litAfterWarmup = false;
        for (var i = 0; i < 200; i++) {
          effect.render(out, i * dt, dt, params, pal);
          if (i >= 45 && _lit(out)) litAfterWarmup = true;
        }
        // 1x1 only has to survive; a single LED can legitimately be dark.
        if (w * h > 1) expect(litAfterWarmup, isTrue, reason: 'all black');
      });
    }

    test('${g.id} survives extreme params and frame hiccups', () {
      final effect = g.create(16, 16, 3);
      final out = Frame(16, 16);
      final pal = paletteById(g.defaultPalette);
      for (final pick in [(ParamSpec s) => s.min, (ParamSpec s) => s.max]) {
        final params = Params({for (final s in g.params) s.key: pick(s)});
        var t = 0.0;
        for (var i = 0; i < 60; i++) {
          // Mix normal frames, a zero-length frame and a long stall.
          final dt = i == 10 ? 0.0 : (i == 20 ? 3.0 : 1 / 30);
          t += dt;
          effect.render(out, t, dt, params, pal);
        }
      }
    });
  }

  test('new palettes are appended after the original eight', () {
    expect(palettes.take(8).map((p) => p.id).toList(),
        ['rainbow', 'sunset', 'ocean', 'lava', 'forest', 'neon', 'ice', 'matrix']);
  });
}
