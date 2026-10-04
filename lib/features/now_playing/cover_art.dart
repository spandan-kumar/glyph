import 'dart:math' as math;
import 'dart:typed_data';

import '../../engine/frame.dart';
import '../import/processing.dart';

/// A cover tuned for LEDs at one size, plus the colour that best stands for
/// it (for the progress bar and the room glow).
class CoverArt {
  CoverArt(this.frame, this.accent);

  final Frame frame;
  final int accent;
}

/// Shrinks a square RGB cover to [size]² by area averaging (keeps colours
/// honest at a handful of LEDs), then tunes it like an imported photo:
/// LEDs wash out midtones and colours, so add contrast, saturation
/// ([vivid] 0..1) and a darkening gamma, and switch near-blacks fully off.
CoverArt prepareCover(Uint8List rgb, int srcSize, int size, {double vivid = 0.5}) {
  final px = resampleArea(rgb, srcSize, srcSize, 0, 0, srcSize.toDouble(), srcSize.toDouble(), size, size);
  final tuned = ImportSettings(contrast: 1.12, saturation: 1 + 0.7 * vivid, gamma: 1.4);
  adjustPixels(px, tuned);
  for (var i = 0; i < px.length; i += 3) {
    if (px[i] < 6 && px[i + 1] < 6 && px[i + 2] < 6) px[i] = px[i + 1] = px[i + 2] = 0;
  }
  final f = Frame(size, size)..rgb.setAll(0, px);
  return CoverArt(f, accentOf(f));
}

/// The cover's signature colour: the hue family carrying the most vivid,
/// bright pixels, averaged and brought to full brightness. Greyscale covers
/// get a soft white.
int accentOf(Frame f) {
  const buckets = 12;
  final weight = List<double>.filled(buckets, 0);
  final sums = List.generate(buckets, (_) => [0.0, 0.0, 0.0]);
  for (var i = 0; i < f.rgb.length; i += 3) {
    final r = f.rgb[i], g = f.rgb[i + 1], b = f.rgb[i + 2];
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    if (mx < 40) continue;
    final sat = (mx - mn) / mx, val = mx / 255;
    final w = sat * sat * val;
    if (w < 0.04) continue;
    final k = (_hue(r, g, b, mx, mn) * buckets).floor() % buckets;
    weight[k] += w;
    sums[k][0] += r * w;
    sums[k][1] += g * w;
    sums[k][2] += b * w;
  }
  var best = 0;
  for (var k = 1; k < buckets; k++) {
    if (weight[k] > weight[best]) best = k;
  }
  // Too little colour to call it: a few faint pixels shouldn't tint the bar.
  if (weight[best] < 0.6) return 0xD8D8E0;
  final w = weight[best];
  final r = sums[best][0] / w, g = sums[best][1] / w, b = sums[best][2] / w;
  final mx = math.max(r, math.max(g, b));
  final k = mx > 0 ? 255 / mx : 0.0;
  return rgb((r * k).round(), (g * k).round(), (b * k).round());
}

double _hue(int r, int g, int b, int mx, int mn) {
  final d = (mx - mn).toDouble();
  if (d == 0) return 0;
  double h;
  if (mx == r) {
    h = ((g - b) / d) % 6;
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return (h / 6 + 1) % 1;
}

/// HSV (all 0..1) to a packed colour.
int hsv(double h, double s, double v) {
  final i = (h * 6).floor() % 6;
  final f = h * 6 - (h * 6).floor();
  final p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  final (r, g, b) = switch (i) {
    0 => (v, t, p),
    1 => (q, v, p),
    2 => (p, v, t),
    3 => (p, q, v),
    4 => (t, p, v),
    _ => (v, p, q),
  };
  return rgb((r * 255).round(), (g * 255).round(), (b * 255).round());
}

/// A stand-in cover for tracks without art: two hues picked from the title
/// across a soft diagonal, so every song still gets its own look.
CoverArt placeholderCover(String title, int size) {
  final seed = title.codeUnits.fold(17, (h, c) => (h * 31 + c) & 0xFFFFFF);
  final h1 = (seed % 360) / 360, h2 = (h1 + 0.12 + (seed >> 9) % 20 / 100) % 1;
  final a = hsv(h1, 0.85, 0.55), b = hsv(h2, 0.9, 0.3);
  final f = Frame(size, size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final u = (x + y) / (2 * (size - 1)).clamp(1, 1 << 20);
      f.set(x, y, _lerp(a, b, u));
    }
  }
  return CoverArt(f, hsv(h1, 0.75, 1));
}

int _lerp(int a, int b, double u) => rgb(
      (((a >> 16) & 0xFF) + (((b >> 16) & 0xFF) - ((a >> 16) & 0xFF)) * u).round(),
      (((a >> 8) & 0xFF) + (((b >> 8) & 0xFF) - ((a >> 8) & 0xFF)) * u).round(),
      ((a & 0xFF) + ((b & 0xFF) - (a & 0xFF)) * u).round(),
    );

int lerpColor(int a, int b, double u) => _lerp(a, b, u.clamp(0.0, 1.0));
