import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/generators/sprite.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';

bool _lit(Frame f) => f.rgb.any((v) => v > 8);

Map<String, dynamic> _pack(List<Map<String, dynamic>> sprites, {Map<String, String>? colors, Map<String, List<String>>? parts}) => {
      'pack': 'test',
      'category': 'Test',
      'colors': colors ?? {'R': '#FF0000', 'G': '#00FF00', 'P': 'p:0.5', 'C': 'c:0.25!', 'T': 't:#FFFFFF'},
      'parts': ?parts,
      'sprites': sprites,
    };

void main() {
  group('format', () {
    test('full frames, patches, shift, flip, seq and timing', () {
      final s = Sprite.parsePackJson(_pack([
        {
          'id': 'demo',
          'title': 'Demo',
          'tags': ['x'],
          'motion': 'bounce',
          'ms': [100, 300, 50],
          'frames': [
            ['R...', '....', '....', '...G'],
            {'base': 0, 'patch': [{'at': [1, 1], 'rows': ['GG', ' _']}]},
            {'base': 0, 'shift': [1, 0], 'flip': 'v'},
          ],
          'seq': [0, 1, 2],
        }
      ]))
          .single;
      expect(s.width, 4);
      expect(s.height, 4);
      expect(s.frameCount, 3);
      expect(s.motion, SpriteMotion.bounce);
      expect(s.category, 'Test');
      expect(s.loopMs, 450);
      expect(s.stepAt(0), 0);
      expect(s.stepAt(150), 1);
      expect(s.stepAt(420), 2);
      expect(s.stepAt(460), 0); // loops
      // Frame 1: patch painted G at (1,1),(2,1); '_' cleared (2,2) (already clear).
      final f1 = s.frameAt(1);
      expect(f1[1 * 4 + 1], isNot(-1));
      expect(f1[1 * 4 + 2], isNot(-1));
      expect(f1[0], isNot(-1), reason: 'base pixel kept');
      // Frame 2: shifted right by 1 then flipped vertically.
      final f2 = s.frameAt(2);
      expect(f2[3 * 4 + 1], isNot(-1), reason: 'R moved to (1,3)');
      expect(f2[0], -1);
    });

    test('parts are shared bases', () {
      final s = Sprite.parsePackJson(_pack([
        {'id': 'p', 'frames': [{'base': 'dot', 'patch': [{'at': [0, 0], 'rows': ['.R']}]}]}
      ], parts: {
        'dot': ['G.', '..']
      }))
          .single;
      final f = s.frameAt(0);
      expect(f[0], isNot(-1), reason: '"." in a patch keeps the pixel');
      expect(f[1], isNot(-1));
      expect(f[2], -1);
    });

    test('palette, cycling, vivid and twinkle inks resolve', () {
      final s = Sprite.parsePackJson(_pack([
        {'id': 'inks', 'frames': [['PCT']]}
      ]))
          .single;
      expect(s.recolourable, isTrue);
      final out = Uint32ListLike(3);
      s.resolve(0, paletteById('ocean'), 0, out.data);
      expect(out.data[0] & 0xFFFFFF, paletteById('ocean').at(0.5));
      expect(out.data.every((c) => c >> 24 == 0xFF), isTrue);
      final a = List.of(out.data);
      s.resolve(0, paletteById('ocean'), 1.3, out.data);
      expect(out.data[1], isNot(a[1]), reason: 'cycling ink moves with time');
      final vivid = out.data[1] & 0xFFFFFF;
      final peak = [(vivid >> 16) & 255, (vivid >> 8) & 255, vivid & 255].reduce((m, v) => v > m ? v : m);
      expect(peak, greaterThan(230));
    });

    test('errors are reported, not silently drawn', () {
      expect(() => Sprite.parsePackJson(_pack([{'id': 'a', 'frames': [['X']]}])), throwsFormatException);
      expect(() => Sprite.parsePackJson(_pack([{'id': 'a', 'frames': [['R', 'RR']]}])), throwsFormatException);
      expect(() => Sprite.parsePackJson(_pack([{'id': 'a', 'frames': [['R']], 'seq': [3]}])), throwsFormatException);
      expect(() => Sprite.parsePackJson(_pack([{'id': 'a', 'frames': [['R']], 'ms': [1, 2]}])), throwsFormatException);
      expect(() => Sprite.parsePackJson(_pack([{'id': 'a', 'frames': [{'base': 'nope'}]}])), throwsFormatException);
    });

    test('banners fit by height', () {
      final s = Sprite.parsePackJson(_pack([
        {'id': 'b', 'motion': 'scroll', 'frames': [['RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR', 'RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR', 'RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR', 'RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR']]}
      ]))
          .single;
      expect(s.isBanner, isTrue);
      final g = SpriteGenerator(s);
      final f = Frame(16, 16);
      g.create(16, 16, 1).render(f, 0.5, 0.5, Params.defaultsFor(g), paletteById('rainbow'));
      // Scaled x4 to 16 px tall: the whole column under the banner is lit.
      var litRows = 0;
      for (var y = 0; y < 16; y++) {
        if (List.generate(16, (x) => f.get(x, y)).any((c) => c != 0)) litRows++;
      }
      expect(litRows, 16);
    });
  });

  group('bundled packs', () {
    final packs = Directory('assets/catalog/sprites').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();

    test('compiled data matches the JSON sources (run tool/build_sprites.dart)', () {
      final fromFiles = {for (final f in packs) for (final s in Sprite.parsePack(f.readAsStringSync())) s.id};
      final compiled = {for (final g in SpriteLibrary.all) g.sprite.id};
      expect(compiled, fromFiles);
      final gen = File('lib/engine/generators/sprite_data.g.dart').readAsStringSync();
      for (final f in packs) {
        expect(gen.contains(jsonEncode(jsonDecode(f.readAsStringSync()))), isTrue,
            reason: '${f.path} changed; run dart run tool/build_sprites.dart');
      }
    });

    test('at least 150 sprites, unique ids, real palettes, 2+ sizes', () {
      final all = spriteGenerators;
      expect(all.length, greaterThanOrEqualTo(150));
      expect(all.map((g) => g.id).toSet().length, all.length);
      final ids = palettes.map((p) => p.id).toSet();
      final sizes = <String>{};
      for (final g in all) {
        expect(ids, contains(g.defaultPalette), reason: g.id);
        expect(g.sprite.title.trim(), isNotEmpty);
        expect(g.sprite.tags, isNotEmpty, reason: g.id);
        // Story loops (classics) run longer than icon loops.
        expect(g.sprite.frameCount, inInclusiveRange(1, 48), reason: g.id);
        sizes.add('${g.sprite.width}x${g.sprite.height}');
        expect(findGenerator(g.id), same(g));
      }
      expect(sizes, containsAll(['16x16', '8x8']));
    });

    const sizes = [(16, 16), (8, 32), (32, 8), (5, 3), (1, 1)];
    test('every sprite renders at every size and shows something', () {
      for (final g in spriteGenerators) {
        for (final (w, h) in sizes) {
          final inst = g.create(w, h, 3);
          final out = Frame(w, h);
          final p = Params.defaultsFor(g);
          final pal = paletteById(g.defaultPalette);
          var lit = false;
          for (var i = 0; i < 200; i++) {
            inst.render(out, i / 30, 1 / 30, p, pal);
            if (i >= 45 && _lit(out)) lit = true;
          }
          if (w * h > 1) expect(lit, isTrue, reason: '${g.id} blank at ${w}x$h');
        }
      }
    });

    test('every motion and extreme params survive hiccups', () {
      for (final g in spriteGenerators.take(40)) {
        for (var m = 0; m <= 6; m++) {
          final inst = g.create(16, 16, 1);
          final out = Frame(16, 16);
          final p = Params({'speed': m.isEven ? 0.25 : 3, 'motion': m.toDouble(), 'backdrop': 1});
          var t = 0.0;
          for (var i = 0; i < 40; i++) {
            final dt = i == 10 ? 0.0 : (i == 20 ? 3.0 : 1 / 30);
            t += dt;
            inst.render(out, t, dt, p, paletteById('neon'));
          }
        }
      }
    });
  });
}

/// Tiny holder so the test reads clearly.
class Uint32ListLike {
  Uint32ListLike(int n) : data = Uint32List(n);
  final Uint32List data;
}
