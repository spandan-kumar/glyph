/// Frames the matrix shows while it is being set up: the hello wave, a big
/// arrow and an "L", each drawn for the matrix's own size.
library;

import 'dart:math';

import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../../features/text/fonts.dart';

/// Matrix size to draw for when the device hasn't reported one.
const fallbackSize = 16;

// An open hand, palm towards you; '#' lit, '+' shaded.
const _hand = [
  '.#.#.#..',
  '.#.#.#.#',
  '.#.#.#.#',
  '.#######',
  '########',
  '#++#####',
  '.++++##.',
  '..++++..',
];

const _skin = 0xFFC069;
const _shade = 0xD8873A;
const _hiColor = 0xFFF1DC;
const _sparkle = 0xFFE7B0;

/// A pixel hand waving next to "HI", about two seconds per loop.
FrameClip helloClip(int width, int height) {
  final w = max(1, width), h = max(1, height);
  final wide = w >= h * 1.6;
  // Drawn on a small design canvas, then fitted (integer-scaled when it can
  // be) to the matrix.
  final cw = wide ? 24 : 16, ch = wide ? 8 : 16;
  const poses = [0, 1, 2, 1, 0, -1, -2, -1];
  final frames = <Frame>[];
  for (var loop = 0; loop < 2; loop++) {
    for (var i = 0; i < poses.length; i++) {
      final f = Frame(cw, ch);
      final k = poses[i];
      final hx = wide ? 2 : 4;
      _drawHand(f, hx, 0, k);
      if (k.abs() == 2) {
        // Little motion marks on the side the hand swings to.
        final mx = k > 0 ? hx + 10 : hx - 3;
        f.set(mx, 1, _sparkle);
        f.set(mx + (k > 0 ? 1 : -1), 0, scaleColorInt(_sparkle, 0.6));
      }
      final step = loop * poses.length + i;
      final tx = wide ? 13 : (cw - boldFont.measure('HI')) ~/ 2;
      final ty = wide ? 1 : 9;
      // A slow glint travels across the letters.
      final glint = (step / (poses.length * 2)) * 18 - 3;
      drawText(f, boldFont, 'HI', tx, ty, 1, (x, y) {
        final d = ((x - tx) - glint).abs();
        return d < 1.5 ? 0xFFFFFF : _hiColor;
      });
      frames.add(f);
    }
  }
  return FrameClip(
    width: cw,
    height: ch,
    frames: frames,
    delaysMs: List.filled(frames.length, 125),
  ).fitTo(w, h);
}

void _drawHand(Frame f, int ox, int oy, int tilt) {
  for (var r = 0; r < _hand.length; r++) {
    // Shear: the fingertips swing furthest, the wrist stays put.
    final shift = (tilt * (_hand.length - 1 - r) / (_hand.length - 1)).round();
    final row = _hand[r];
    for (var c = 0; c < row.length; c++) {
      final ch = row[c];
      if (ch == '.') continue;
      f.set(ox + c + shift, oy + r, ch == '+' ? _shade : _skin);
    }
  }
}

/// A big arrow pointing up, with light flowing towards its tip.
FrameClip arrowClip(int width, int height, {int color = 0xFFB547}) {
  final w = max(1, width), h = max(1, height);
  final n = min(w, h);
  final inset = n >= 12 ? 1 : 0;
  final size = n - inset * 2;
  final ox = (w - size) / 2, oy = (h - size) / 2;
  final cx = ox + (size - 1) / 2;
  final head = max(1, (size / 2).ceil());
  final shaft = max(0.5, size / 8);
  const count = 8;
  final frames = <Frame>[];
  for (var i = 0; i < count; i++) {
    final f = Frame(w, h);
    for (var r = 0; r < size; r++) {
      final y = (oy + r).floor();
      final half = r < head ? r + (size.isEven ? 0.5 : 0.0) : shaft;
      final v = 0.45 + 0.55 * (1 - ((r / size + i / count) % 1));
      for (var x = 0; x < w; x++) {
        if ((x - cx).abs() <= half + 1e-9) f.set(x, y, scaleColorInt(color, v));
      }
    }
    frames.add(f);
  }
  return FrameClip(width: w, height: h, frames: frames, delaysMs: List.filled(count, 90));
}

/// A large capital L: easy to tell when it's drawn backwards.
FrameClip letterClip(int width, int height, {String letter = 'L', int color = 0xF3EFE8}) {
  final w = max(1, width), h = max(1, height);
  final font = h >= 9 && w >= 8 ? boldFont : tinyFont;
  final gw = font.measure(letter), gh = font.capHeight;
  final scale = max(1, min((w - 2) ~/ gw, (h - 2) ~/ gh));
  final x0 = (w - gw * scale) ~/ 2, y0 = (h - gh * scale) ~/ 2;
  final frames = <Frame>[];
  for (final v in [1.0, 0.8]) {
    final f = Frame(w, h);
    drawText(f, font, letter, x0, y0, scale, (_, _) => scaleColorInt(color, v));
    frames.add(f);
  }
  return FrameClip(width: w, height: h, frames: frames, delaysMs: const [700, 700]);
}

/// Draws [text] with [font] at ([ox], [oy]), each font pixel [scale]×[scale].
void drawText(Frame f, BitmapFont font, String text, int ox, int oy, int scale,
    int Function(int x, int y) color) {
  var x0 = 0;
  for (final rune in text.runes) {
    final g = font.glyph(rune);
    for (var y = 0; y < font.capHeight && y < g.rows.length; y++) {
      for (var x = 0; x < g.width; x++) {
        if (!g.on(x, y)) continue;
        for (var sy = 0; sy < scale; sy++) {
          for (var sx = 0; sx < scale; sx++) {
            final px = ox + (x0 + x) * scale + sx, py = oy + y * scale + sy;
            f.set(px, py, color(px, py));
          }
        }
      }
    }
    x0 += g.width + font.spacing;
  }
}

int scaleColorInt(int c, double k) {
  int ch(int s) => (((c >> s) & 0xFF) * k).round().clamp(0, 255);
  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}
