import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/text/fonts.dart';

void main() {
  final printable = [for (var c = 0x20; c < 0x7F; c++) c];

  for (final f in textFonts) {
    group(f.name, () {
      test('has a glyph for every printable ASCII char', () {
        for (final c in printable) {
          final direct = f.has(c) || (c >= 0x61 && c <= 0x7A && f.has(c - 32));
          expect(direct, isTrue, reason: '${f.id} missing ${String.fromCharCode(c)}');
        }
      });

      test('glyphs are well formed', () {
        for (final r in f.runes) {
          final g = f.glyph(r);
          final ch = String.fromCharCode(r);
          expect(g.rows.length, f.height, reason: ch);
          expect(g.width, inInclusiveRange(1, 8), reason: ch);
          for (final row in g.rows) {
            expect(row >> g.width, 0, reason: '$ch draws outside its width');
          }
          if (r != 0x20) expect(g.rows.any((x) => x != 0), isTrue, reason: '$ch is blank');
        }
        expect(f.glyph(0x20).rows.every((x) => x == 0), isTrue);
      });

      test('digits share one width and fit the cap height', () {
        final widths = {for (var d = 0x30; d <= 0x39; d++) if (d != 0x31) f.glyph(d).width};
        expect(widths.length, 1);
        for (var d = 0x30; d <= 0x39; d++) {
          final rows = f.glyph(d).rows;
          for (var y = f.capHeight; y < f.height; y++) {
            expect(rows[y], 0, reason: 'digit ${String.fromCharCode(d)} below cap height');
          }
        }
      });

      test('has the extra symbols', () {
        for (final s in ['♥', '★', '°', '✓', '←', '→', '↑', '↓']) {
          expect(f.has(s.runes.single), isTrue, reason: s);
        }
      });
    });
  }

  test('measure adds 1px spacing between glyphs', () {
    final f = classicFont;
    expect(f.measure(''), 0);
    expect(f.measure('A'), f.glyph(0x41).width);
    expect(f.measure('AB'), f.glyph(0x41).width + f.glyph(0x42).width + 1);
    expect(f.measure('12:05'), 23); // narrow '1'
    expect(tinyFont.measure('12:05'), 17);
  });

  test('unknown characters fall back to ?, lowercase tiny to caps', () {
    expect(classicFont.glyph('€'.runes.single), same(classicFont.glyph(0x3F)));
    expect(tinyFont.glyph(0x61), same(tinyFont.glyph(0x41)));
  });

  test('bold is wider than classic', () {
    expect(boldFont.measure('HELLO'), greaterThan(classicFont.measure('HELLO')));
    expect(fontFallbacks('bold'), [boldFont, classicFont, tinyFont]);
    expect(fontFallbacks('tiny'), [tinyFont]);
  });
}
