import '../../../engine/frame.dart';

// 3×5 digits, one 3-bit row each (MSB = left column).
const _digits = <List<int>>[
  [7, 5, 5, 5, 7],
  [2, 6, 2, 2, 7],
  [7, 1, 7, 4, 7],
  [7, 1, 7, 1, 7],
  [5, 5, 7, 1, 1],
  [7, 4, 7, 1, 7],
  [7, 4, 7, 5, 7],
  [7, 1, 1, 1, 1],
  [7, 5, 7, 5, 7],
  [7, 5, 7, 1, 7],
];

int textWidth(String s, [int scale = 1]) => s.isEmpty ? 0 : (s.length * 4 - 1) * scale;

/// Draws the digits in [s] with the top-left corner at ([x], [y]).
void drawDigits(Frame f, String s, int x, int y, int color, {int scale = 1}) {
  for (var i = 0; i < s.length; i++) {
    final d = s.codeUnitAt(i) - 48;
    if (d < 0 || d > 9) continue;
    final rows = _digits[d];
    for (var r = 0; r < 5; r++) {
      for (var c = 0; c < 3; c++) {
        if ((rows[r] >> (2 - c)) & 1 == 0) continue;
        final px = x + (i * 4 + c) * scale, py = y + r * scale;
        for (var dy = 0; dy < scale; dy++) {
          for (var dx = 0; dx < scale; dx++) {
            f.set(px + dx, py + dy, color);
          }
        }
      }
    }
  }
}

/// Draws [n] centred. Splits onto two lines when it's too wide, and scrolls
/// (driven by [t] seconds) when even that doesn't fit.
void drawNumber(Frame f, int n, int color, {int scale = 1, double t = 0}) {
  final s = '$n';
  final w = textWidth(s, scale), h = 5 * scale;
  if (w <= f.width) {
    drawDigits(f, s, (f.width - w) ~/ 2, (f.height - h) ~/ 2, color, scale: scale);
    return;
  }
  final half = (s.length + 1) ~/ 2;
  final a = s.substring(0, half), b = s.substring(half);
  if (textWidth(a, scale) <= f.width && 11 * scale <= f.height) {
    final top = (f.height - 11 * scale) ~/ 2;
    drawDigits(f, a, (f.width - textWidth(a, scale)) ~/ 2, top, color, scale: scale);
    drawDigits(f, b, (f.width - textWidth(b, scale)) ~/ 2, top + 6 * scale, color,
        scale: scale);
    return;
  }
  final off = (t * 10 * scale).floor() % (w + f.width);
  drawDigits(f, s, f.width - off, (f.height - h) ~/ 2, color, scale: scale);
}
