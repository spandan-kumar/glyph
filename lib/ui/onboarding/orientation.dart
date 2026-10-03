/// Works out the matrix layout from two plain questions: which way an
/// up-arrow points on the matrix, and whether an "L" looks mirrored.
library;

import '../../engine/frame.dart';
import '../../wled/layout.dart';

/// Where the arrow pointed on the real matrix.
enum ArrowSeen { up, right, down, left }

/// The layout that shows pictures the right way round, given what the user
/// saw while [current] was in use. A matrix that is wired rotated or
/// mirrored applies one of the eight turns/flips of a square to everything
/// we send; [seen] and [mirrored] identify which one, and the result undoes
/// it. Zig-zag wiring ([MatrixLayout.serpentine]) is kept as it was.
///
/// Returns null when no layout can fix it: quarter turns only exist for
/// square matrices, so a sideways arrow on a non-square one has to be fixed
/// in the matrix's own settings.
MatrixLayout? correctedLayout(
  MatrixLayout current,
  ArrowSeen seen, {
  required bool mirrored,
  bool square = true,
}) {
  final (w, h) = square ? (5, 5) : (5, 3);
  final base = current.copyWith(serpentine: false);
  final sent = layoutPermutation(base, w, h);
  for (final device in _deviceMaps(w, h, square)) {
    final seenAs = _compose(device, sent);
    if (_arrow(seenAs, w, h) != seen || _isMirrored(seenAs, w, h) != mirrored) continue;
    for (final candidate in _candidates(square)) {
      if (_isIdentity(_compose(device, layoutPermutation(candidate, w, h)))) {
        return candidate.copyWith(serpentine: current.serpentine);
      }
    }
  }
  return null;
}

/// Where each logical pixel of a [w]×[h] frame lands in LED order under
/// [layout], computed with the layout's own [MatrixLayout.apply].
List<int> layoutPermutation(MatrixLayout layout, int w, int h) {
  final f = Frame(w, h);
  for (var i = 0; i < w * h; i++) {
    f.set(i % w, i ~/ w, i + 1);
  }
  final out = layout.apply(f);
  final perm = List<int>.filled(w * h, 0);
  for (var d = 0; d < w * h; d++) {
    final v = (out[d * 3] << 16) | (out[d * 3 + 1] << 8) | out[d * 3 + 2];
    perm[v - 1] = d;
  }
  return perm;
}

/// What a matrix wired with [device] (LED index → physical position) shows
/// for the arrow and the L when sent through [layout]. For tests and for
/// simulating answers.
(ArrowSeen, bool) simulateAnswers(List<int> device, MatrixLayout layout, int w, int h) {
  final c = _compose(device, layoutPermutation(layout.copyWith(serpentine: false), w, h));
  return (_arrow(c, w, h), _isMirrored(c, w, h));
}

/// Every way a [w]×[h] matrix can be wired turned or flipped: LED index →
/// physical index. Only half-turns and flips keep a non-square shape.
List<List<int>> deviceMaps(int w, int h) => _deviceMaps(w, h, w == h);

List<List<int>> _deviceMaps(int w, int h, bool square) {
  final out = <List<int>>[];
  for (final q in square ? const [0, 1, 2, 3] : const [0, 2]) {
    for (final flip in const [false, true]) {
      final m = List<int>.filled(w * h, 0);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var (px, py) = switch (q) {
            1 => (w - 1 - y, x),
            2 => (w - 1 - x, h - 1 - y),
            3 => (y, h - 1 - x),
            _ => (x, y),
          };
          if (flip) px = w - 1 - px;
          m[y * w + x] = py * w + px;
        }
      }
      out.add(m);
    }
  }
  return out;
}

Iterable<MatrixLayout> _candidates(bool square) sync* {
  for (final q in square ? const [0, 1, 2, 3] : const [0, 2]) {
    for (final fx in const [false, true]) {
      yield MatrixLayout(rotation: q, flipX: fx);
    }
  }
}

List<int> _compose(List<int> outer, List<int> inner) => [for (final i in inner) outer[i]];

bool _isIdentity(List<int> p) {
  for (var i = 0; i < p.length; i++) {
    if (p[i] != i) return false;
  }
  return true;
}

(int, int) _at(List<int> p, int x, int y, int w) {
  final i = p[y * w + x];
  return (i % w, i ~/ w);
}

ArrowSeen _arrow(List<int> p, int w, int h) {
  final cx = w ~/ 2, cy = h ~/ 2;
  final (ax, ay) = _at(p, cx, cy, w);
  final (ux, uy) = _at(p, cx, cy - 1, w);
  return switch ((ux - ax, uy - ay)) {
    (0, < 0) => ArrowSeen.up,
    (> 0, 0) => ArrowSeen.right,
    (0, > 0) => ArrowSeen.down,
    _ => ArrowSeen.left,
  };
}

bool _isMirrored(List<int> p, int w, int h) {
  final cx = w ~/ 2, cy = h ~/ 2;
  final (ax, ay) = _at(p, cx, cy, w);
  final (ux, uy) = _at(p, cx, cy - 1, w);
  final (rx, ry) = _at(p, cx + 1, cy, w);
  final cross = (rx - ax) * (uy - ay) - (ry - ay) * (ux - ax);
  // Unchanged: right = (1, 0), up = (0, -1) → cross = -1.
  return cross > 0;
}
