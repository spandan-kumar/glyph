// Draws Glyph's app icon: a pixel "G" in lit LED dots on a dark panel, with
// a warm phosphor-to-pink gradient, soft bloom and one "spark" pixel.
//
//   dart run tool/make_icon.dart            # writes Android launcher icons
//   dart run tool/make_icon.dart --preview  # also writes build/icon_1024.png
import 'dart:io';
import 'dart:math';

import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/generators/intro.dart';
import 'package:glyph/engine/palette.dart';
import 'package:image/image.dart' as img;

const _bg = 0xFF0B0A09;
const _off = 0xFF1D1A17;

/// The logo as the intro leaves it: the last frame of [GlyphIntro], with
/// the spark at full brightness. Null = unlit.
List<List<int?>> _finalFrame() {
  final inst = GlyphIntro().create(16, 16, 1);
  final f = Frame(16, 16);
  // Step through the whole intro so the physics settle, then read the end.
  for (var i = 0; i <= (GlyphIntro.duration + 0.6) * 60; i++) {
    inst.render(f, i / 60, 1 / 60, Params({}), palettes.first);
  }
  final out = [
    for (var y = 0; y < 16; y++) [for (var x = 0; x < 16; x++) f.get(x, y) == 0 ? null : 0xFF000000 | f.get(x, y)],
  ];
  out[glyphSparkCell.$2][glyphSparkCell.$1] = glyphSpark;
  return out;
}

int _lerp(int a, int b, double t) {
  int ch(int s) => (((a >> s) & 0xFF) + (((b >> s) & 0xFF) - ((a >> s) & 0xFF)) * t).round();
  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

img.ColorRgba8 _c(int argb, [int? alpha]) =>
    img.ColorRgba8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, alpha ?? (argb >> 24) & 0xFF);

/// Renders the icon at [size] px. [inset] is the fraction of the canvas
/// left as margin (adaptive icons need a safe zone). [background] false
/// leaves it transparent (adaptive foreground).
img.Image render(int size, {double inset = 0.14, bool background = true, bool rounded = false}) {
  final im = img.Image(width: size, height: size, numChannels: 4);
  if (background) {
    img.fill(im, color: _c(_bg));
    if (rounded) {
      // Square-ish panel with tiny corners for store/preview art.
      final r = (size * 0.06).round();
      final mask = img.Image(width: size, height: size, numChannels: 4);
      img.fillRect(mask, x1: 0, y1: 0, x2: size - 1, y2: size - 1, color: _c(_bg), radius: r);
      img.fill(im, color: _c(0x00000000, 0));
      img.compositeImage(im, mask);
    }
  }
  final px = _finalFrame();
  const n = 16;
  final area = size * (1 - 2 * inset);
  final cell = area / n;
  final ox = size * inset, oy = size * inset;
  final r = cell * 0.4;
  bool glows(int c) => c != glyphShadow;

  // Bloom pass: soft discs under the lit dots (the shadow doesn't glow).
  final glow = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final color = px[y][x];
      if (color == null || !glows(color)) continue;
      final cx = (ox + (x + 0.5) * cell).round(), cy = (oy + (y + 0.5) * cell).round();
      img.fillCircle(glow, x: cx, y: cy, radius: (cell * 0.95).round(), color: _c(color, color == glyphSpark ? 130 : 75), antialias: true);
    }
  }
  img.compositeImage(im, img.gaussianBlur(glow, radius: max(1, (cell * 0.6).round())));

  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final color = px[y][x];
      final cx = (ox + (x + 0.5) * cell).round(), cy = (oy + (y + 0.5) * cell).round();
      if (color == null) {
        if (background) img.fillCircle(im, x: cx, y: cy, radius: r.round(), color: _c(_off), antialias: true);
        continue;
      }
      img.fillCircle(im, x: cx, y: cy, radius: r.round(), color: _c(color), antialias: true);
      if (glows(color)) {
        // Hot core: emitted light, not paint.
        img.fillCircle(im, x: cx, y: cy, radius: (r * 0.45).round(), color: _c(_lerp(color, 0xFFFFFFFF, 0.5), 200), antialias: true);
      }
    }
  }
  return im;
}

void main(List<String> args) {
  const legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
  const adaptive = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432};
  const res = 'android/app/src/main/res';
  for (final MapEntry(:key, :value) in legacy.entries) {
    File('$res/mipmap-$key/ic_launcher.png').writeAsBytesSync(img.encodePng(render(value, inset: 0.12)));
  }
  for (final MapEntry(:key, :value) in adaptive.entries) {
    // Adaptive foreground: art inside the 66/108 safe zone.
    File('$res/mipmap-$key/ic_launcher_foreground.png')
        .writeAsBytesSync(img.encodePng(render(value, inset: 0.25, background: false)));
  }
  Directory('$res/mipmap-anydpi-v26').createSync(recursive: true);
  File('$res/mipmap-anydpi-v26/ic_launcher.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');
  File('$res/values/ic_launcher_background.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0B0A09</color>
</resources>
''');
  Directory('assets/brand').createSync(recursive: true);
  File('assets/brand/glyph_icon_1024.png').writeAsBytesSync(img.encodePng(render(1024, inset: 0.12, rounded: true)));
  stdout.writeln('icons written; preview: assets/brand/glyph_icon_1024.png');
}
