import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/setup_frames.dart';

Frame flipX(Frame f) {
  final o = Frame(f.width, f.height);
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      o.set(f.width - 1 - x, y, f.get(x, y));
    }
  }
  return o;
}

Frame flipY(Frame f) {
  final o = Frame(f.width, f.height);
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      o.set(x, f.height - 1 - y, f.get(x, y));
    }
  }
  return o;
}

Frame turn(Frame f) {
  // Quarter turn clockwise (square only).
  final o = Frame(f.height, f.width);
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      o.set(f.height - 1 - y, x, f.get(x, y));
    }
  }
  return o;
}

Frame transpose(Frame f) {
  final o = Frame(f.height, f.width);
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      o.set(y, x, f.get(x, y));
    }
  }
  return o;
}

void main() {
  test('litLeds lights only the given LEDs', () {
    final b = litLeds(10, [0, 3, 99, -1]);
    expect(b.length, 30);
    expect(b.sublist(0, 3), everyElement(greaterThan(0)));
    expect(b[0], 96);
    expect(b[0], greaterThan(b[2]), reason: 'warm white');
    expect(b.sublist(3, 9), everyElement(0));
    expect(b.sublist(9, 12), [96, (96 * 0.78).round(), (96 * 0.4).round()]);
    expect(b.sublist(12), everyElement(0));
    expect(litLeds(4, [1], level: 200)[3], 200);
  });

  group('cornerCheckFrame', () {
    const sizes = [(8, 8), (16, 16), (32, 8), (8, 32), (16, 32), (32, 32), (5, 5), (4, 4)];

    test('is lit with the block in the top left corner', () {
      for (final (w, h) in sizes) {
        final f = cornerCheckFrame(w, h);
        expect(f.get(0, 0), isNot(0), reason: '${w}x$h corner');
        expect(f.rgb.any((v) => v != 0), isTrue);
      }
    });

    test('no mirror or rotation looks like the original', () {
      for (final (w, h) in sizes) {
        final f = cornerCheckFrame(w, h);
        final variants = <String, Frame>{
          'flipX': flipX(f),
          'flipY': flipY(f),
          'rotate180': flipX(flipY(f)),
          if (w == h) ...{
            'rotate90': turn(f),
            'rotate270': turn(turn(turn(f))),
            'transpose': transpose(f),
            'antitranspose': turn(transpose(turn(f))),
          },
        };
        variants.forEach((name, v) {
          expect(v.width, f.width);
          expect(v.rgb, isNot(equals(f.rgb)), reason: '${w}x$h $name');
        });
      }
    });

    test('the arrow points up: more lit width near its head than at its tip row', () {
      final f = cornerCheckFrame(16, 16);
      int litIn(int y) => [for (var x = 3; x < 13; x++) f.get(x, y)].where((c) => c != 0).length;
      final rows = [for (var y = 0; y < 16; y++) litIn(y)];
      final top = rows.indexWhere((n) => n > 0);
      expect(rows[top], lessThan(rows[top + 2]), reason: 'tip is narrower than the head');
    });
  });
}
