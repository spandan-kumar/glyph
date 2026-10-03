import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/onboarding/orientation.dart';
import 'package:glyph/ui/onboarding/setup_clips.dart';
import 'package:glyph/wled/layout.dart';

void main() {
  group('correctedLayout', () {
    const id = MatrixLayout.identity;

    test('maps plain answers to the layout that undoes them', () {
      expect(correctedLayout(id, ArrowSeen.up, mirrored: false), id);
      // The matrix turned things clockwise, so we turn them back.
      expect(correctedLayout(id, ArrowSeen.right, mirrored: false), const MatrixLayout(rotation: 3));
      expect(correctedLayout(id, ArrowSeen.left, mirrored: false), const MatrixLayout(rotation: 1));
      expect(correctedLayout(id, ArrowSeen.down, mirrored: false), const MatrixLayout(rotation: 2));
      expect(correctedLayout(id, ArrowSeen.up, mirrored: true), const MatrixLayout(flipX: true));
      // Upside down and mirrored = flipped top to bottom.
      expect(
        correctedLayout(id, ArrowSeen.down, mirrored: true),
        const MatrixLayout(rotation: 2, flipX: true),
      );
    });

    test('keeps zig-zag wiring as it was', () {
      final l = correctedLayout(const MatrixLayout(serpentine: true), ArrowSeen.down, mirrored: false);
      expect(l, const MatrixLayout(rotation: 2, serpentine: true));
    });

    test('works from any starting layout, for every way a square matrix can be wired', () {
      const n = 5;
      final starts = [
        for (final q in [0, 1, 2, 3])
          for (final fx in [false, true])
            for (final fy in [false, true]) MatrixLayout(rotation: q, flipX: fx, flipY: fy),
      ];
      for (final device in deviceMaps(n, n)) {
        for (final start in starts) {
          final (seen, mirrored) = simulateAnswers(device, start, n, n);
          final fixed = correctedLayout(start, seen, mirrored: mirrored);
          expect(fixed, isNotNull);
          expect(simulateAnswers(device, fixed!, n, n), (ArrowSeen.up, false),
              reason: 'start $start → $fixed');
        }
      }
    });

    test('the arrow alone (assuming not mirrored) leaves the arrow pointing up or down', () {
      for (final device in deviceMaps(5, 5)) {
        final (seen, _) = simulateAnswers(device, MatrixLayout.identity, 5, 5);
        final step1 = correctedLayout(MatrixLayout.identity, seen, mirrored: false)!;
        final (after, _) = simulateAnswers(device, step1, 5, 5);
        expect(after, anyOf(ArrowSeen.up, ArrowSeen.down));
      }
    });

    test('non-square matrices can only be fixed by half-turns and flips', () {
      expect(correctedLayout(id, ArrowSeen.right, mirrored: false, square: false), isNull);
      expect(
        correctedLayout(id, ArrowSeen.down, mirrored: false, square: false),
        const MatrixLayout(rotation: 2),
      );
      for (final device in deviceMaps(5, 3)) {
        final (seen, mirrored) = simulateAnswers(device, id, 5, 3);
        final fixed = correctedLayout(id, seen, mirrored: mirrored, square: false)!;
        expect(simulateAnswers(device, fixed, 5, 3), (ArrowSeen.up, false));
      }
    });
  });

  group('setup clips', () {
    test('are drawn at the matrix size', () {
      for (final (w, h) in [(16, 16), (32, 32), (32, 8), (8, 8), (20, 12)]) {
        for (final clip in [helloClip(w, h), arrowClip(w, h), letterClip(w, h)]) {
          expect((clip.width, clip.height), (w, h));
          expect(clip.frames.every((f) => f.width == w && f.height == h), isTrue);
          expect(clip.frames.any((f) => f.rgb.any((b) => b > 0)), isTrue);
        }
      }
    });

    test('hello loops in about two seconds and moves', () {
      final c = helloClip(16, 16);
      expect(c.totalMs, inInclusiveRange(1500, 2500));
      expect(c.frames[0].rgb, isNot(equals(c.frames[2].rgb)));
    });

    test('the arrow points up: its tip is on the top rows', () {
      final f = arrowClip(16, 16).frames.first;
      bool lit(int x, int y) => f.get(x, y) != 0;
      final topLit = [for (var x = 0; x < 16; x++) if (lit(x, 1)) x];
      final bottomLit = [for (var x = 0; x < 16; x++) if (lit(x, 14)) x];
      expect(topLit, [7, 8]);
      expect(bottomLit.length, greaterThan(2));
      expect(bottomLit.length, lessThan(8));
    });
  });
}
