import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/gif_encoder.dart';
import 'package:image/image.dart' as img;

/// A decoded GIF: the composited canvas after each frame, plus what the file
/// said about each frame. Only handles what the encoder writes (global table,
/// disposal 0/1, no interlace), and fails loudly on anything else.
class DecodedGif {
  DecodedGif(this.width, this.height, this.loop, this.tableSize);

  final int width, height, tableSize;
  final int? loop;
  final frames = <Uint8List>[];
  final delays = <int>[]; // centiseconds
  final rects = <(int, int, int, int)>[]; // x, y, w, h
  final codeSizes = <int>[];

  /// The picture on screen during each input frame, given the per-frame
  /// [inputDelays] it was encoded with (merged frames span several).
  List<Uint8List> timeline(List<int> inputDelays) {
    final out = <Uint8List>[];
    var t = 0, start = 0, j = 0;
    for (final d in inputDelays) {
      while (j + 1 < frames.length && start + delays[j] <= t) {
        start += delays[j];
        j++;
      }
      out.add(frames[j]);
      t += d;
    }
    return out;
  }
}

DecodedGif decodeTestGif(Uint8List d) {
  int u16(int p) => d[p] | (d[p + 1] << 8);
  expect(String.fromCharCodes(d.sublist(0, 6)), 'GIF89a');
  final w = u16(6), h = u16(8), packed = d[10];
  expect(packed & 0x80, 0x80, reason: 'global colour table');
  final n = 2 << (packed & 7);
  final gct = d.sublist(13, 13 + 3 * n);
  var p = 13 + 3 * n;
  final canvas = Uint8List(w * h * 3);
  int? loop;
  var delay = 0, trans = -1;
  final frames = <(Uint8List, int, (int, int, int, int), int)>[];
  while (true) {
    final b = d[p++];
    if (b == 0x3B) break;
    if (b == 0x21) {
      final label = d[p++];
      if (label == 0xF9) {
        expect(d[p], 4);
        final flags = d[p + 1];
        expect((flags >> 2) & 7, anyOf(0, 1), reason: 'disposal');
        delay = u16(p + 2);
        trans = (flags & 1) != 0 ? d[p + 4] : -1;
      } else if (label == 0xFF &&
          String.fromCharCodes(d.sublist(p + 1, p + 12)) == 'NETSCAPE2.0') {
        loop = u16(p + 14);
      }
      while (d[p] != 0) {
        p += d[p] + 1;
      }
      p++;
      continue;
    }
    expect(b, 0x2C, reason: 'image descriptor at $p');
    final fx = u16(p), fy = u16(p + 2), fw = u16(p + 4), fh = u16(p + 6);
    expect(d[p + 8], 0, reason: 'no local table, not interlaced');
    expect(fx + fw <= w && fy + fh <= h, isTrue);
    p += 9;
    final mcs = d[p++];
    final data = <int>[];
    while (d[p] != 0) {
      data.addAll(d.sublist(p + 1, p + 1 + d[p]));
      p += d[p] + 1;
    }
    p++;
    final px = _lzwDecode(data, mcs);
    expect(px.length, fw * fh);
    for (var i = 0; i < px.length; i++) {
      if (px[i] == trans) continue;
      final o = ((fy + i ~/ fw) * w + fx + i % fw) * 3;
      canvas.setRange(o, o + 3, gct, px[i] * 3);
    }
    frames.add((Uint8List.fromList(canvas), delay, (fx, fy, fw, fh), mcs));
  }
  expect(p, d.length, reason: 'nothing after the trailer');
  final g = DecodedGif(w, h, loop, n);
  for (final (rgb, dl, rect, mcs) in frames) {
    g.frames.add(rgb);
    g.delays.add(dl);
    g.rects.add(rect);
    g.codeSizes.add(mcs);
  }
  return g;
}

List<int> _lzwDecode(List<int> s, int mcs) {
  final clear = 1 << mcs, eoi = clear + 1;
  var size = mcs + 1, next = clear + 2;
  final prefix = Int32List(4096), suffix = Int32List(4096);
  for (var i = 0; i < clear; i++) {
    suffix[i] = i;
  }
  final out = <int>[], stack = <int>[];
  var acc = 0, bits = 0, pos = 0, prev = -1, first = 0;
  while (true) {
    while (bits < size) {
      if (pos >= s.length) throw StateError('LZW data ran out');
      acc |= s[pos++] << bits;
      bits += 8;
    }
    final code = acc & ((1 << size) - 1);
    acc >>= size;
    bits -= size;
    if (code == clear) {
      size = mcs + 1;
      next = clear + 2;
      prev = -1;
      continue;
    }
    if (code == eoi) break;
    if (prev < 0) {
      expect(code, lessThan(clear));
      out.add(code);
      prev = first = code;
      continue;
    }
    var c = code;
    final unseen = code >= next; // the KwKwK case
    if (unseen) {
      expect(code, next);
      c = prev;
    }
    stack.clear();
    while (c >= clear) {
      stack.add(suffix[c]);
      c = prefix[c];
    }
    stack.add(c);
    first = c;
    out.addAll(stack.reversed);
    if (unseen) out.add(first);
    if (next < 4096) {
      prefix[next] = prev;
      suffix[next] = first;
      next++;
      if (next == (1 << size) && size < 12) size++;
    }
    prev = code;
  }
  return out;
}

/// Deterministic LCG so the inputs are easy to reproduce elsewhere.
class _Lcg {
  _Lcg(this._s);
  int _s;
  int next(int n) {
    _s = (_s * 1103515245 + 12345) & 0x7FFFFFFF;
    return (_s >> 8) % n;
  }
}

List<Frame> _movingDot() => [
      for (var f = 0; f < 20; f++)
        Frame(16, 16)
          ..rgb.setAll(0, [
            for (var i = 0; i < 256; i++) ...[
              (i % 16 + i ~/ 16) * 8,
              64,
              255 - (i % 16 + i ~/ 16) * 8,
            ],
          ])
          ..set(f % 16, (f ~/ 2) % 16, 0xFFFFFF),
    ];

void _expectExact(DecodedGif g, List<Frame> frames, List<int> delays) {
  final shown = g.timeline(delays);
  for (var i = 0; i < frames.length; i++) {
    expect(shown[i], frames[i].rgb, reason: 'frame $i');
  }
}

void main() {
  test('round-trips frames exactly with one global table', () {
    final frames = _movingDot();
    final delays = List.filled(frames.length, 5);
    final bytes = encodeGif(frames, delays);
    final g = decodeTestGif(bytes);
    expect((g.width, g.height), (16, 16));
    expect(g.loop, 0);
    expect(g.tableSize, 64); // 32 colours + transparency
    expect(g.frames.length, 20);
    expect(g.delays, delays);
    _expectExact(g, frames, delays);
    expect(g.rects.first, (0, 0, 16, 16));
    // Only the old and new dot positions change between frames.
    expect(g.rects[1], (0, 0, 2, 1));
  });

  test('package:image reads the output', () {
    final frames = _movingDot();
    final d = img.decodeGif(encodeGif(frames, List.filled(20, 5)))!;
    expect(d.numFrames, 20);
    expect(d.loopCount, 0);
    expect(d.frames.first.frameDuration, 50);
    final f = d.frames.first;
    for (var i = 0; i < 256; i++) {
      final p = f.getPixel(i % 16, i ~/ 16);
      final c = frames[0].get(i % 16, i ~/ 16);
      expect([p.r.toInt(), p.g.toInt(), p.b.toInt()],
          [(c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF]);
    }
  });

  test('identical frames fold into the previous delay', () {
    final a = Frame(4, 4)..fill(0x102030);
    final b = a.copy()..set(1, 1, 0xFF0000);
    final frames = [a, a.copy(), b, b.copy(), b.copy()];
    final g = decodeTestGif(encodeGif(frames, [5, 5, 5, 5, 5]));
    expect(g.delays, [10, 15]);
    expect(g.rects[1], (1, 1, 1, 1));
    _expectExact(g, frames, [5, 5, 5, 5, 5]);
  });

  test('delta: false writes every frame in full', () {
    final frames = _movingDot().sublist(0, 4)..add(_movingDot()[3]);
    final g = decodeTestGif(encodeGif(frames, List.filled(5, 4), delta: false));
    expect(g.frames.length, 5);
    expect(g.rects.toSet(), {(0, 0, 16, 16)});
    _expectExact(g, frames, List.filled(5, 4));
  });

  test('large noisy frames survive dictionary resets', () {
    final r = _Lcg(42);
    final cols = [for (var i = 0; i < 200; i++) r.next(1 << 24)];
    final frames = <Frame>[];
    for (var f = 0; f < 3; f++) {
      final fr = Frame(100, 100);
      for (var i = 0; i < 10000; i++) {
        fr.set(i % 100, i ~/ 100, cols[r.next(200)]);
      }
      frames.add(fr);
    }
    final last = frames.last.copy();
    for (var y = 40; y < 45; y++) {
      for (var x = 10; x < 30; x++) {
        last.set(x, y, cols[r.next(200)]);
      }
    }
    frames.add(last);
    final g = decodeTestGif(encodeGif(frames, [5, 5, 5, 5]));
    expect(g.codeSizes.toSet(), {8});
    _expectExact(g, frames, [5, 5, 5, 5]);
    final (x, y, w, h) = g.rects.last;
    expect(x >= 10 && y >= 40 && x + w <= 30 && y + h <= 45, isTrue);
  });

  test('tiny palettes use a 2-colour table and 2-bit codes', () {
    final frames = [Frame(1, 1), Frame(1, 1)..set(0, 0, 0x00FF00), Frame(1, 1)];
    final g = decodeTestGif(encodeGif(frames, [3, 3, 3]));
    expect(g.tableSize, 4); // 2 colours + transparency
    expect(g.codeSizes, [2, 2, 2]);
    _expectExact(g, frames, [3, 3, 3]);
    final mono = [Frame(5, 3)..fill(0xABCDEF), Frame(5, 3)..fill(0xABCDEF)];
    final m = decodeTestGif(encodeGif(mono, [7, 7]));
    expect(m.tableSize, 2);
    expect(m.delays, [14]);
    _expectExact(m, mono, [7, 7]);
  });

  test('more than 255 colours quantise with bounded error', () {
    final frames = [
      for (var f = 0; f < 3; f++)
        Frame(32, 32)
          ..rgb.setAll(0, [
            for (var i = 0; i < 1024; i++)
              for (final v in [
                (i + f * 37) % 1024 % 256,
                (i + f * 37) % 1024 * 7 % 256,
                (i + f * 37) % 1024 ~/ 4,
              ])
                v,
          ]),
    ];
    final bytes = encodeGif(frames, [5, 5, 5]);
    expect(encodeGif(frames, [5, 5, 5]), bytes, reason: 'deterministic');
    final g = decodeTestGif(bytes);
    expect(g.tableSize, 256);
    final shown = g.timeline([5, 5, 5]);
    var se = 0, worst = 0;
    for (var f = 0; f < 3; f++) {
      for (var i = 0; i < frames[f].rgb.length; i++) {
        final e = (shown[f][i] - frames[f].rgb[i]).abs();
        se += e * e;
        if (e > worst) worst = e;
      }
    }
    // The Python port of this encoder gives MSE 28.6, max error 21.
    expect(se / (3 * 1024 * 3), lessThan(40));
    expect(worst, lessThanOrEqualTo(32));
    expect(shown[0].sublist(0, 3), [0, 0, 0], reason: 'black stays exact');
  });

  test('rejects bad input', () {
    expect(() => encodeGif(const [], const []), throwsArgumentError);
    expect(() => encodeGif([Frame(2, 2)], const []), throwsArgumentError);
    expect(() => encodeGif([Frame(2, 2), Frame(3, 2)], const [5, 5]),
        throwsArgumentError);
  });
}
