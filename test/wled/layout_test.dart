import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/wled/layout.dart';

/// A frame whose blue channel holds each pixel's logical index.
Frame indexed(int w, int h) {
  final f = Frame(w, h);
  for (var i = 0; i < w * h; i++) {
    f.set(i % w, i ~/ w, i);
  }
  return f;
}

/// Logical pixel index at each LED position.
List<int> ledOrder(MatrixLayout l, Frame f) {
  final out = l.apply(f);
  return [for (var i = 0; i < f.pixelCount; i++) out[i * 3 + 2]];
}

void main() {
  final f3 = indexed(3, 3);

  test('identity passes the frame buffer through', () {
    const l = MatrixLayout();
    expect(l.isIdentity, isTrue);
    expect(identical(l.apply(f3), f3.rgb), isTrue);
    expect(ledOrder(const MatrixLayout(rotation: 4), f3), [0, 1, 2, 3, 4, 5, 6, 7, 8]);
  });

  test('serpentine reverses odd rows', () {
    expect(ledOrder(const MatrixLayout(serpentine: true), f3),
        [0, 1, 2, 5, 4, 3, 6, 7, 8]);
    expect(ledOrder(const MatrixLayout(serpentine: true), indexed(4, 2)),
        [0, 1, 2, 3, 7, 6, 5, 4]);
  });

  test('flips', () {
    expect(ledOrder(const MatrixLayout(flipX: true), f3), [2, 1, 0, 5, 4, 3, 8, 7, 6]);
    expect(ledOrder(const MatrixLayout(flipY: true), f3), [6, 7, 8, 3, 4, 5, 0, 1, 2]);
    expect(ledOrder(const MatrixLayout(flipX: true, flipY: true), f3),
        ledOrder(const MatrixLayout(rotation: 2), f3));
  });

  test('rotation turns clockwise on square matrices', () {
    expect(ledOrder(const MatrixLayout(rotation: 1), f3), [6, 3, 0, 7, 4, 1, 8, 5, 2]);
    expect(ledOrder(const MatrixLayout(rotation: 2), f3), [8, 7, 6, 5, 4, 3, 2, 1, 0]);
    expect(ledOrder(const MatrixLayout(rotation: 3), f3), [2, 5, 8, 1, 4, 7, 0, 3, 6]);
    expect(ledOrder(const MatrixLayout(rotation: -1), f3),
        ledOrder(const MatrixLayout(rotation: 3), f3));
  });

  test('quarter turns are ignored on non-square matrices, half turns work', () {
    final f = indexed(3, 2);
    expect(ledOrder(const MatrixLayout(rotation: 1), f), [0, 1, 2, 3, 4, 5]);
    expect(ledOrder(const MatrixLayout(rotation: 2), f), [5, 4, 3, 2, 1, 0]);
  });

  test('keeps full RGB and reuses its buffer', () {
    final f = Frame(2, 2)..set(0, 0, 0x112233);
    const l = MatrixLayout(flipX: true);
    final a = l.apply(f);
    expect(a.sublist(3, 6), [0x11, 0x22, 0x33]);
    expect(identical(l.apply(f), a), isTrue);
    expect(l.apply(Frame(3, 3)).length, 27); // size change reallocates
  });

  test('json round trip', () {
    const l = MatrixLayout(rotation: 3, flipY: true, serpentine: true);
    expect(MatrixLayout.fromJson(l.toJson()), l);
    expect(MatrixLayout.fromJson({}), const MatrixLayout());
  });
}
