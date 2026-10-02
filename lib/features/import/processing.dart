import 'dart:math' as math;
import 'dart:typed_data';

import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../../engine/gif_baker.dart';
import 'decode.dart';

// Pure image pipeline for imports: geometry (crop/fit, rotate, flip,
// resample), tone adjustments, background removal, palette reduction and
// timing. Everything here is synchronous and isolate-safe.

enum FitMode { fill, fit, stretch }

enum BackgroundMode { off, dark, colour }

/// Editor state for one import. Neutral values leave pixels untouched.
class ImportSettings {
  const ImportSettings({
    this.fit = FitMode.fill,
    this.cropX = 0.5,
    this.cropY = 0.5,
    this.zoom = 1,
    this.quarterTurns = 0,
    this.flipH = false,
    this.flipV = false,
    this.pixelArt = false,
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.gamma = 1,
    this.background = BackgroundMode.off,
    this.bgColor = 0x000000,
    this.bgTolerance = 0.12,
    this.colors = 0,
    this.dither = false,
    this.trimStart = 0,
    this.trimEnd,
    this.speed = 1,
    this.frameStep = 1,
  });

  /// LEDs render midtones bright and colours pale, so imports start with a
  /// little extra contrast and saturation and a darkening gamma.
  static const ledDefaults =
      ImportSettings(contrast: 1.1, saturation: 1.25, gamma: 1.4);

  final FitMode fit;

  /// Crop window centre in the oriented image (0..1) and zoom (1 = largest
  /// window that fits). Only used by [FitMode.fill].
  final double cropX, cropY, zoom;

  /// Clockwise quarter turns, applied before the flips.
  final int quarterTurns;
  final bool flipH, flipV;

  /// Nearest-neighbour sampling for already-pixelated sources.
  final bool pixelArt;

  /// -0.5..0.5 added after contrast.
  final double brightness;
  final double contrast;

  /// 0 = greyscale, 1 = unchanged.
  final double saturation;

  /// Output = input^gamma, so > 1 darkens midtones.
  final double gamma;

  final BackgroundMode background;
  final int bgColor;

  /// 0..1 of the channel range.
  final double bgTolerance;

  /// Palette size; 0 keeps all colours.
  final int colors;
  final bool dither;

  /// Source frame range, inclusive. [trimEnd] null = last frame.
  final int trimStart;
  final int? trimEnd;
  final double speed;

  /// Keep every n-th frame (delays are merged, so duration is unchanged).
  final int frameStep;

  bool get rotated => quarterTurns.isOdd;

  ImportSettings copyWith({
    FitMode? fit,
    double? cropX,
    double? cropY,
    double? zoom,
    int? quarterTurns,
    bool? flipH,
    bool? flipV,
    bool? pixelArt,
    double? brightness,
    double? contrast,
    double? saturation,
    double? gamma,
    BackgroundMode? background,
    int? bgColor,
    double? bgTolerance,
    int? colors,
    bool? dither,
    int? trimStart,
    int? Function()? trimEnd,
    double? speed,
    int? frameStep,
  }) =>
      ImportSettings(
        fit: fit ?? this.fit,
        cropX: cropX ?? this.cropX,
        cropY: cropY ?? this.cropY,
        zoom: zoom ?? this.zoom,
        quarterTurns: (quarterTurns ?? this.quarterTurns) % 4,
        flipH: flipH ?? this.flipH,
        flipV: flipV ?? this.flipV,
        pixelArt: pixelArt ?? this.pixelArt,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        gamma: gamma ?? this.gamma,
        background: background ?? this.background,
        bgColor: bgColor ?? this.bgColor,
        bgTolerance: bgTolerance ?? this.bgTolerance,
        colors: colors ?? this.colors,
        dither: dither ?? this.dither,
        trimStart: trimStart ?? this.trimStart,
        trimEnd: trimEnd != null ? trimEnd() : this.trimEnd,
        speed: speed ?? this.speed,
        frameStep: frameStep ?? this.frameStep,
      );

  /// Same settings with the tone controls swapped for [tone]'s.
  ImportSettings withToneOf(ImportSettings tone) => copyWith(
        brightness: tone.brightness,
        contrast: tone.contrast,
        saturation: tone.saturation,
        gamma: tone.gamma,
      );

  Map<String, dynamic> toJson() => {
        'fit': fit.name,
        'cropX': cropX,
        'cropY': cropY,
        'zoom': zoom,
        'quarterTurns': quarterTurns,
        'flipH': flipH,
        'flipV': flipV,
        'pixelArt': pixelArt,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'gamma': gamma,
        'background': background.name,
        'bgColor': bgColor,
        'bgTolerance': bgTolerance,
        'colors': colors,
        'dither': dither,
        'trimStart': trimStart,
        'trimEnd': trimEnd,
        'speed': speed,
        'frameStep': frameStep,
      };
}

// ---------------------------------------------------------------------------
// Geometry

/// Where a source rect (raw, unrotated pixels) lands in the target.
class Placement {
  const Placement(this.sx, this.sy, this.sw, this.sh, this.dx, this.dy, this.dw, this.dh);

  /// Source rect in raw image coordinates (fractional).
  final double sx, sy, sw, sh;

  /// Destination rect in the target (oriented).
  final int dx, dy, dw, dh;
}

/// Image size after rotation.
(int, int) orientedSize(int w, int h, int quarterTurns) =>
    quarterTurns.isOdd ? (h, w) : (w, h);

/// The fill-mode crop window in oriented coordinates: (x, y, w, h).
(double, double, double, double) cropWindow(
    int ow, int oh, ImportSettings s, int tw, int th) {
  final ta = tw / th;
  double ww, wh;
  if (ow / oh > ta) {
    wh = oh.toDouble();
    ww = oh * ta;
  } else {
    ww = ow.toDouble();
    wh = ow / ta;
  }
  final z = s.zoom.clamp(1.0, maxZoom(ow, oh, tw, th));
  ww /= z;
  wh /= z;
  final cx = (s.cropX * ow).clamp(ww / 2, ow - ww / 2);
  final cy = (s.cropY * oh).clamp(wh / 2, oh - wh / 2);
  return (cx - ww / 2, cy - wh / 2, ww, wh);
}

/// Zoom stops once the window is about one source pixel per LED.
double maxZoom(int ow, int oh, int tw, int th) {
  final ta = tw / th;
  final ww = ow / oh > ta ? oh * ta : ow.toDouble();
  return (ww / tw).clamp(1.0, 12.0);
}

Placement placement(int w, int h, ImportSettings s, int tw, int th) {
  final (ow, oh) = orientedSize(w, h, s.quarterTurns);
  double rx = 0, ry = 0, rw = ow.toDouble(), rh = oh.toDouble();
  var dx = 0, dy = 0, dw = tw, dh = th;
  switch (s.fit) {
    case FitMode.fill:
      (rx, ry, rw, rh) = cropWindow(ow, oh, s, tw, th);
    case FitMode.fit:
      final scale = math.min(tw / ow, th / oh);
      dw = (ow * scale).round().clamp(1, tw);
      dh = (oh * scale).round().clamp(1, th);
      dx = (tw - dw) ~/ 2;
      dy = (th - dh) ~/ 2;
    case FitMode.stretch:
      break;
  }
  final (ax, ay) = orientedToRaw(rx, ry, w, h, s);
  final (bx, by) = orientedToRaw(rx + rw, ry + rh, w, h, s);
  return Placement(math.min(ax, bx), math.min(ay, by), (ax - bx).abs(),
      (ay - by).abs(), dx, dy, dw, dh);
}

/// Maps a continuous point in the oriented image back to the raw image.
/// Orientation is: rotate clockwise [ImportSettings.quarterTurns] times, then
/// flip.
(double, double) orientedToRaw(double u, double v, int w, int h, ImportSettings s) {
  final (ow, oh) = orientedSize(w, h, s.quarterTurns);
  if (s.flipH) u = ow - u;
  if (s.flipV) v = oh - v;
  // Undo each clockwise turn: (x, y) in W×H went to (H - y, x) in H×W.
  var cw = ow, ch = oh;
  for (var i = 0; i < s.quarterTurns; i++) {
    final x = v, y = cw - u;
    u = x;
    v = y;
    final t = cw;
    cw = ch;
    ch = t;
  }
  return (u, v);
}

/// Rotates/flips an RGB buffer like the editor does. Returns the new buffer;
/// its size is [orientedSize].
Uint8List orient(Uint8List rgb, int w, int h, int quarterTurns,
    {bool flipH = false, bool flipV = false}) {
  var src = rgb, cw = w, ch = h;
  for (var t = 0; t < quarterTurns % 4; t++) {
    final out = Uint8List(src.length);
    // Clockwise: (x, y) -> (ch - 1 - y, x) in a ch×cw image.
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        final si = (y * cw + x) * 3, di = (x * ch + (ch - 1 - y)) * 3;
        out[di] = src[si];
        out[di + 1] = src[si + 1];
        out[di + 2] = src[si + 2];
      }
    }
    src = out;
    final tmp = cw;
    cw = ch;
    ch = tmp;
  }
  if (flipH || flipV) {
    final out = Uint8List(src.length);
    for (var y = 0; y < ch; y++) {
      final sy = flipV ? ch - 1 - y : y;
      for (var x = 0; x < cw; x++) {
        final sx = flipH ? cw - 1 - x : x;
        final si = (sy * cw + sx) * 3, di = (y * cw + x) * 3;
        out[di] = src[si];
        out[di + 1] = src[si + 1];
        out[di + 2] = src[si + 2];
      }
    }
    src = out;
  }
  return identical(src, rgb) ? Uint8List.fromList(rgb) : src;
}

/// Area-averaging (box filter) resample of the source rect ([rx], [ry],
/// [rw], [rh]) into [dw]×[dh]. Each output pixel is the exact coverage-
/// weighted mean of the source pixels under it, which keeps thin details
/// and colours honest when shrinking to a handful of LEDs.
Uint8List resampleArea(Uint8List src, int sw, int sh, double rx, double ry,
    double rw, double rh, int dw, int dh) {
  final xs = _weights(rx, rw, dw, sw), ys = _weights(ry, rh, dh, sh);
  final x0 = xs.first, x1 = xs.last;
  final span = x1 - x0;
  final row = Float64List(span * 3);
  final out = Uint8List(dw * dh * 3);
  for (var dy = 0; dy < dh; dy++) {
    row.fillRange(0, row.length, 0);
    final yw = ys.taps[dy];
    var wsum = 0.0;
    for (final (sy, w) in yw) {
      wsum += w;
      var si = (sy * sw + x0) * 3;
      for (var i = 0; i < span * 3; i++) {
        row[i] += src[si++] * w;
      }
    }
    final inv = wsum > 0 ? 1 / wsum : 0.0;
    for (var dx = 0; dx < dw; dx++) {
      var r = 0.0, g = 0.0, b = 0.0, ws = 0.0;
      for (final (sx, w) in xs.taps[dx]) {
        final i = (sx - x0) * 3;
        r += row[i] * w;
        g += row[i + 1] * w;
        b += row[i + 2] * w;
        ws += w;
      }
      final k = ws > 0 ? inv / ws : 0.0;
      final o = (dy * dw + dx) * 3;
      out[o] = (r * k).round().clamp(0, 255);
      out[o + 1] = (g * k).round().clamp(0, 255);
      out[o + 2] = (b * k).round().clamp(0, 255);
    }
  }
  return out;
}

class _Taps {
  _Taps(this.taps, this.first, this.last);
  final List<List<(int, double)>> taps;
  final int first, last; // source index range [first, last)
}

_Taps _weights(double start, double length, int n, int size) {
  final step = length / n;
  final taps = <List<(int, double)>>[];
  var first = size, last = 0;
  for (var i = 0; i < n; i++) {
    var a = start + i * step, b = a + step;
    a = a.clamp(0.0, size.toDouble());
    b = b.clamp(0.0, size.toDouble());
    final t = <(int, double)>[];
    if (b - a < 1e-9) {
      // Degenerate (fully outside): use the nearest edge pixel.
      final p = a.floor().clamp(0, size - 1);
      t.add((p, 1));
    } else {
      for (var p = a.floor(); p < b; p++) {
        final w = math.min(b, p + 1.0) - math.max(a, p.toDouble());
        if (w > 1e-9 && p < size) t.add((p, w));
      }
    }
    for (final (p, _) in t) {
      if (p < first) first = p;
      if (p + 1 > last) last = p + 1;
    }
    taps.add(t);
  }
  return _Taps(taps, first, last);
}

/// Nearest-neighbour resample, for pixel art.
Uint8List resampleNearest(Uint8List src, int sw, int sh, double rx, double ry,
    double rw, double rh, int dw, int dh) {
  final out = Uint8List(dw * dh * 3);
  for (var dy = 0; dy < dh; dy++) {
    final sy = (ry + (dy + 0.5) * rh / dh).floor().clamp(0, sh - 1);
    for (var dx = 0; dx < dw; dx++) {
      final sx = (rx + (dx + 0.5) * rw / dw).floor().clamp(0, sw - 1);
      final si = (sy * sw + sx) * 3, o = (dy * dw + dx) * 3;
      out[o] = src[si];
      out[o + 1] = src[si + 1];
      out[o + 2] = src[si + 2];
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Colour

/// Precomputed tone curve for one [ImportSettings].
class ToneMap {
  ToneMap(ImportSettings s)
      : saturation = s.saturation,
        identity = s.brightness == 0 &&
            s.contrast == 1 &&
            s.saturation == 1 &&
            s.gamma == 1,
        _pre = Uint8List(256),
        _post = Uint8List(256) {
    for (var i = 0; i < 256; i++) {
      final v = ((i / 255 - 0.5) * s.contrast + 0.5 + s.brightness).clamp(0.0, 1.0);
      _pre[i] = (v * 255).round();
      _post[i] = (math.pow(i / 255, s.gamma) * 255).round().clamp(0, 255);
    }
  }

  final double saturation;
  final bool identity;
  final Uint8List _pre, _post;

  /// Adjusts one colour: contrast/brightness, saturation, then gamma.
  int apply(int r, int g, int b) {
    if (identity) return (r << 16) | (g << 8) | b;
    var fr = _pre[r].toDouble(), fg = _pre[g].toDouble(), fb = _pre[b].toDouble();
    if (saturation != 1) {
      final l = 0.299 * fr + 0.587 * fg + 0.114 * fb;
      fr = l + (fr - l) * saturation;
      fg = l + (fg - l) * saturation;
      fb = l + (fb - l) * saturation;
    }
    return (_post[fr.round().clamp(0, 255)] << 16) |
        (_post[fg.round().clamp(0, 255)] << 8) |
        _post[fb.round().clamp(0, 255)];
  }
}

/// Whether a colour counts as background and should be switched off.
bool isBackground(int r, int g, int b, ImportSettings s) {
  final tol = (s.bgTolerance * 255).round();
  switch (s.background) {
    case BackgroundMode.off:
      return false;
    case BackgroundMode.dark:
      return r <= tol && g <= tol && b <= tol;
    case BackgroundMode.colour:
      final c = s.bgColor;
      return (r - ((c >> 16) & 0xFF)).abs() <= tol &&
          (g - ((c >> 8) & 0xFF)).abs() <= tol &&
          (b - (c & 0xFF)).abs() <= tol;
  }
}

/// Background removal then tone mapping, in place.
void adjustPixels(Uint8List rgb, ImportSettings s, [ToneMap? tone]) {
  final t = tone ?? ToneMap(s);
  final bg = s.background != BackgroundMode.off;
  if (t.identity && !bg) return;
  for (var i = 0; i < rgb.length; i += 3) {
    final r = rgb[i], g = rgb[i + 1], b = rgb[i + 2];
    if (bg && isBackground(r, g, b, s)) {
      rgb[i] = rgb[i + 1] = rgb[i + 2] = 0;
      continue;
    }
    final c = t.apply(r, g, b);
    rgb[i] = (c >> 16) & 0xFF;
    rgb[i + 1] = (c >> 8) & 0xFF;
    rgb[i + 2] = c & 0xFF;
  }
}

/// Median-cut palette of at most [n] colours over all [frames]. Pure black is
/// kept as an exact entry when present, so LEDs that were off stay off.
List<int> buildPalette(List<Uint8List> frames, int n) {
  // 15-bit histogram with running sums for box averages.
  final count = Int32List(1 << 15);
  final sr = Float64List(1 << 15), sg = Float64List(1 << 15), sb = Float64List(1 << 15);
  var hasBlack = false;
  for (final f in frames) {
    for (var i = 0; i < f.length; i += 3) {
      final r = f[i], g = f[i + 1], b = f[i + 2];
      if ((r | g | b) == 0) {
        hasBlack = true;
        continue;
      }
      final k = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      count[k]++;
      sr[k] += r;
      sg[k] += g;
      sb[k] += b;
    }
  }
  final keys = <int>[for (var k = 0; k < count.length; k++) if (count[k] > 0) k];
  final slots = hasBlack ? n - 1 : n;
  final palette = <int>[if (hasBlack) 0];
  if (keys.isEmpty || slots <= 0) return palette.isEmpty ? [0] : palette;

  int ch(int k, int axis) => (k >> (10 - axis * 5)) & 31;
  final boxes = <List<int>>[keys];
  while (boxes.length < slots) {
    // Split the box with the widest, most populated channel range.
    var best = -1, bestAxis = 0;
    var bestScore = 0.0;
    for (var bi = 0; bi < boxes.length; bi++) {
      final box = boxes[bi];
      if (box.length < 2) continue;
      var pop = 0;
      for (final k in box) {
        pop += count[k];
      }
      for (var axis = 0; axis < 3; axis++) {
        var lo = 31, hi = 0;
        for (final k in box) {
          final v = ch(k, axis);
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
        final score = (hi - lo) * math.sqrt(pop.toDouble());
        if (score > bestScore) {
          bestScore = score;
          best = bi;
          bestAxis = axis;
        }
      }
    }
    if (best < 0) break;
    final box = boxes.removeAt(best)..sort((a, b) => ch(a, bestAxis) - ch(b, bestAxis));
    var total = 0;
    for (final k in box) {
      total += count[k];
    }
    var acc = 0, cut = 1;
    for (var i = 0; i < box.length - 1; i++) {
      acc += count[box[i]];
      cut = i + 1;
      if (acc * 2 >= total) break;
    }
    boxes
      ..add(box.sublist(0, cut))
      ..add(box.sublist(cut));
  }
  for (final box in boxes) {
    var c = 0.0, r = 0.0, g = 0.0, b = 0.0;
    for (final k in box) {
      c += count[k];
      r += sr[k];
      g += sg[k];
      b += sb[k];
    }
    palette.add(rgb((r / c).round(), (g / c).round(), (b / c).round()));
  }
  return palette;
}

const _bayer4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/// Maps every pixel to its nearest [palette] entry, in place. With [dither]
/// a 4×4 ordered (Bayer) pattern trades banding for a fine, stable texture:
/// stable matters because error diffusion would shimmer between frames.
void quantize(List<Uint8List> frames, int width, List<int> palette, {bool dither = false}) {
  final lookup = Int16List(1 << 15)..fillRange(0, 1 << 15, -1);
  final pr = [for (final c in palette) (c >> 16) & 0xFF];
  final pg = [for (final c in palette) (c >> 8) & 0xFF];
  final pb = [for (final c in palette) c & 0xFF];
  int nearest(int r, int g, int b) {
    final k = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
    final hit = lookup[k];
    if (hit >= 0) return hit;
    final cr = (r & ~7) + 4, cg = (g & ~7) + 4, cb = (b & ~7) + 4;
    var best = 0, bestD = 1 << 30;
    for (var i = 0; i < palette.length; i++) {
      final dr = cr - pr[i], dg = cg - pg[i], db = cb - pb[i];
      // Weighted towards green, roughly how eyes rank the channels.
      final d = 2 * dr * dr + 4 * dg * dg + 3 * db * db;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return lookup[k] = best;
  }

  // Dither amplitude ~ the spacing between palette levels.
  final spread = dither ? 255 / math.pow(palette.length, 1 / 3) : 0.0;
  for (final f in frames) {
    for (var p = 0, i = 0; i < f.length; p++, i += 3) {
      var r = f[i], g = f[i + 1], b = f[i + 2];
      if ((r | g | b) == 0 && palette.first == 0) continue;
      if (dither) {
        final x = p % width, y = p ~/ width;
        final o = ((_bayer4[(y & 3) * 4 + (x & 3)] + 0.5) / 16 - 0.5) * spread;
        r = (r + o).round().clamp(0, 255);
        g = (g + o).round().clamp(0, 255);
        b = (b + o).round().clamp(0, 255);
      }
      final idx = nearest(r, g, b);
      f[i] = pr[idx];
      f[i + 1] = pg[idx];
      f[i + 2] = pb[idx];
    }
  }
}

int countColors(List<Uint8List> frames, {int stopAt = 1 << 24}) {
  final seen = <int>{};
  for (final f in frames) {
    for (var i = 0; i < f.length; i += 3) {
      seen.add((f[i] << 16) | (f[i + 1] << 8) | f[i + 2]);
      if (seen.length >= stopAt) return seen.length;
    }
  }
  return seen.length;
}

// ---------------------------------------------------------------------------
// Timing

/// Source frames to keep with their output delays: trimmed, every
/// [ImportSettings.frameStep]-th frame (absorbing the skipped delays), sped
/// up by [ImportSettings.speed] and rounded to GIF centiseconds (min 20 ms).
List<(int, int)> selectFrames(List<int> delaysMs, ImportSettings s) {
  final n = delaysMs.length;
  final start = s.trimStart.clamp(0, n - 1);
  final end = (s.trimEnd ?? n - 1).clamp(start, n - 1);
  final step = math.max(1, s.frameStep);
  final speed = s.speed <= 0 ? 1.0 : s.speed;
  final out = <(int, int)>[];
  for (var i = start; i <= end; i += step) {
    var d = 0;
    for (var j = i; j < math.min(i + step, end + 1); j++) {
      d += delaysMs[j];
    }
    out.add((i, math.max(20, (d / speed / 10).round() * 10)));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Whole pipeline

/// Renders one source frame to the target size: geometry, then background
/// removal and tone. No palette reduction.
Frame renderFrame(Uint8List rgb, int w, int h, ImportSettings s, int tw, int th,
    {Placement? at, ToneMap? tone}) {
  final p = at ?? placement(w, h, s, tw, th);
  // Resample in raw orientation, then orient the tiny result: 90° turns and
  // flips are exact pixel permutations, so the order doesn't change pixels.
  final rw = s.rotated ? p.dh : p.dw, rh = s.rotated ? p.dw : p.dh;
  final small = (s.pixelArt ? resampleNearest : resampleArea)(
      rgb, w, h, p.sx, p.sy, p.sw, p.sh, rw, rh);
  final o = orient(small, rw, rh, s.quarterTurns, flipH: s.flipH, flipV: s.flipV);
  adjustPixels(o, s, tone);
  final out = Frame(tw, th);
  for (var y = 0; y < p.dh; y++) {
    out.rgb.setRange(((p.dy + y) * tw + p.dx) * 3, ((p.dy + y) * tw + p.dx + p.dw) * 3,
        o, y * p.dw * 3);
  }
  return out;
}

/// The finished clip for [s] at [tw]×[th].
FrameClip processClip(DecodedSource src, ImportSettings s, int tw, int th) {
  final at = placement(src.width, src.height, s, tw, th);
  final tone = ToneMap(s);
  final picks = selectFrames(src.delaysMs, s);
  final frames = [
    for (final (i, _) in picks)
      renderFrame(src.frames[i], src.width, src.height, s, tw, th, at: at, tone: tone),
  ];
  if (s.colors > 0) {
    final px = [for (final f in frames) f.rgb];
    if (countColors(px, stopAt: s.colors + 1) > s.colors) {
      quantize(px, tw, buildPalette(px, s.colors), dither: s.dither);
    }
  }
  return FrameClip(
      width: tw, height: th, frames: frames, delaysMs: [for (final (_, d) in picks) d]);
}

class ImportJob {
  const ImportJob(this.source, this.settings, this.width, this.height);
  final DecodedSource source;
  final ImportSettings settings;
  final int width, height;
}

class ImportOutput {
  const ImportOutput(this.clip, this.gifBytes);
  final FrameClip clip;

  /// Size of the GIF the matrix upload would write.
  final int gifBytes;
}

/// Top-level so it can run under `compute`. Encodes exactly as
/// `GlyphActions.saveClipToDevice` does, so the estimate matches the upload.
ImportOutput runImportJob(ImportJob job) {
  final clip = processClip(job.source, job.settings, job.width, job.height);
  final gif = bakeFrames(clip.frames, fps: clip.averageFps);
  return ImportOutput(clip, gif.bytes.length);
}
