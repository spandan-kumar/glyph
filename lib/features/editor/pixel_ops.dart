import '../../engine/frame.dart';

/// Cells on a Bresenham line from (x0,y0) to (x1,y1), both ends included.
List<(int, int)> linePoints(int x0, int y0, int x1, int y1) {
  final out = <(int, int)>[];
  final dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
  final sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  var err = dx + dy;
  var x = x0, y = y0;
  while (true) {
    out.add((x, y));
    if (x == x1 && y == y1) break;
    final e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y += sy;
    }
  }
  return out;
}

/// Outline of the rectangle spanned by two corners, each cell once.
List<(int, int)> rectPoints(int x0, int y0, int x1, int y1) {
  final l = x0 < x1 ? x0 : x1, r = x0 < x1 ? x1 : x0;
  final t = y0 < y1 ? y0 : y1, b = y0 < y1 ? y1 : y0;
  return [
    for (var x = l; x <= r; x++) (x, t),
    if (b != t)
      for (var x = l; x <= r; x++) (x, b),
    for (var y = t + 1; y < b; y++) (l, y),
    if (r != l)
      for (var y = t + 1; y < b; y++) (r, y),
  ];
}

/// (x,y) plus its reflections for the enabled symmetry axes.
List<(int, int)> mirrored(int x, int y, int w, int h, {bool mx = false, bool my = false}) {
  final xs = {x, if (mx) w - 1 - x};
  final ys = {y, if (my) h - 1 - y};
  return [for (final yy in ys) for (final xx in xs) (xx, yy)];
}

/// 4-connected flood fill. Returns the number of cells changed.
int floodFill(Frame f, int x, int y, int color) {
  final w = f.width, h = f.height;
  if (x < 0 || y < 0 || x >= w || y >= h) return 0;
  final target = f.get(x, y);
  if (target == color) return 0;
  final stack = <int>[y * w + x];
  var n = 0;
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final cx = i % w, cy = i ~/ w;
    if (f.get(cx, cy) != target) continue;
    f.set(cx, cy, color);
    n++;
    if (cx > 0) stack.add(i - 1);
    if (cx < w - 1) stack.add(i + 1);
    if (cy > 0) stack.add(i - w);
    if (cy < h - 1) stack.add(i + w);
  }
  return n;
}

/// [src] moved by (dx,dy) with wrap-around, so nothing is lost while dragging.
Frame shifted(Frame src, int dx, int dy) {
  final w = src.width, h = src.height;
  final out = Frame(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.set((x + dx) % w, (y + dy) % h, src.get(x, y));
    }
  }
  return out;
}

bool sameFrame(Frame a, Frame b) {
  if (a.width != b.width || a.height != b.height) return false;
  final x = a.rgb, y = b.rgb;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
