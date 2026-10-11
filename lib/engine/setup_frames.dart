import 'dart:math' as math;
import 'dart:typed_data';

import 'frame.dart';

/// Test images for the device setup wizard.

/// A raw RGB buffer for [ledCount] LEDs in physical order with [indices]
/// lit warm white at [level] (0-255) and every other LED off. Indices outside
/// the strip are ignored. Send it as it is: it is not mapped or corrected.
Uint8List litLeds(int ledCount, Iterable<int> indices, {int level = 96}) {
  final out = Uint8List(ledCount * 3);
  final r = level.clamp(0, 255);
  final g = (level * 0.78).round().clamp(0, 255);
  final b = (level * 0.4).round().clamp(0, 255);
  for (final i in indices) {
    if (i < 0 || i >= ledCount) continue;
    out[i * 3] = r;
    out[i * 3 + 1] = g;
    out[i * 3 + 2] = b;
  }
  return out;
}

const _amber = 0xFFA010;
const _arrow = 0xC8DCFF;
const _mark = 0x28D060;

/// A frame that shows whether the display is the right way up and not
/// mirrored: an amber block in the top left corner, an arrow pointing up in
/// the middle, and a small green "L" in the bottom left corner. No rotation
/// or mirror of it looks like the original, even on an 8x8 display.
Frame cornerCheckFrame(int w, int h) {
  final f = Frame(w, h);
  final u = math.min(w, h);

  // Corner block: 2x2 (1x1 on very small displays).
  final block = u >= 6 ? 2 : 1;
  for (var y = 0; y < block; y++) {
    for (var x = 0; x < block; x++) {
      f.set(x, y, _amber);
    }
  }

  // Up arrow centred; the shaft is two pixels wide on an even width.
  final even = w.isEven;
  final left = even ? w ~/ 2 - 1 : (w - 1) ~/ 2; // first apex column
  final apex = even ? 2 : 1; // apex width
  final ah = (u * 5 / 8).round().clamp(4, 16);
  final top = math.max(0, (h - ah) ~/ 2);
  for (var row = 0; row < ah; row++) {
    final grow = row < 3 ? row : 0; // a three-row head, then the shaft
    for (var x = left - grow; x <= left + apex - 1 + grow; x++) {
      f.set(x, top + row, _arrow);
    }
  }

  // "L" mark in the bottom left: stem two high and a foot.
  if (h >= 4) {
    f.set(0, h - 1, _mark);
    f.set(0, h - 2, _mark);
    if (w >= 3) f.set(1, h - 1, _mark);
  }
  return f;
}
