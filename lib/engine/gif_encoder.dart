import 'dart:typed_data';

import 'frame.dart';
import 'led_gamma.dart';

// A small GIF89a encoder tuned for LED animations, where flash on the ESP is
// tight. Compared with a generic encoder it writes one global colour table
// instead of one per frame, and stores each later frame as just the changed
// rectangle with unchanged pixels transparent. Spec references are to
// https://www.w3.org/Graphics/GIF/spec-gif89a.txt.

/// Encodes [frames] (all the same size) as an infinitely looping GIF.
/// [delays] holds one delay per frame in centiseconds.
///
/// With at most 255 distinct colours across the whole animation the output is
/// pixel-exact; otherwise colours are quantised to 255 without dithering.
/// Frames identical to the previous one are folded into its delay, so the
/// file can hold fewer frames than [frames]. [delta] = false writes every
/// frame in full, for players that don't keep the previous frame.
///
/// [forLeds] stores the frames as WLED should play them (see [ledFramesForDevice]):
/// WLED's Image effect output goes through WLED's own colour gamma
/// (FX_fcn.cpp WS2812FX::show applies gamma32 to every pixel unless a
/// realtime stream asked it not to), so no gamma is applied here, only the
/// WS2812 white balance (green x0.8 in LED space) and the black floor: a
/// pixel whose brightest channel would reach the LEDs below [ledOffLevel]
/// becomes black instead of a dim glow. Set it for every GIF sent to a
/// matrix; leave it off for GIFs meant for screens (sharing).
Uint8List encodeGif(List<Frame> frames, List<int> delays,
    {bool delta = true, bool forLeds = false}) {
  if (frames.isEmpty) throw ArgumentError('No frames to encode');
  if (forLeds) frames = ledFramesForDevice(frames);
  if (delays.length != frames.length) {
    throw ArgumentError('Expected ${frames.length} delays, got ${delays.length}');
  }
  final w = frames.first.width, h = frames.first.height;
  for (final f in frames) {
    if (f.width != w || f.height != h) throw ArgumentError('Frame sizes differ');
  }
  final npx = w * h;
  final (palette, idx) = _index(frames);
  // One extra entry for transparency; table sizes are powers of two (spec 18).
  var bits = 1;
  while ((1 << bits) < palette.length + 1) {
    bits++;
  }
  final trans = palette.length;
  final minSize = bits < 2 ? 2 : bits; // LZW minimum code size (spec 22)

  final out = _Bytes(1024 + npx * frames.length ~/ 2);
  out
    ..addAll(const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) // GIF89a
    ..u16(w)
    ..u16(h)
    // Logical Screen Descriptor (spec 18): global table, colour resolution
    // and table size both bits-1.
    ..add(0x80 | ((bits - 1) << 4) | (bits - 1))
    ..add(0) // background colour index
    ..add(0); // pixel aspect ratio
  for (var i = 0; i < (1 << bits); i++) {
    final c = i < palette.length ? palette[i] : 0;
    out
      ..add((c >> 16) & 0xFF)
      ..add((c >> 8) & 0xFF)
      ..add(c & 0xFF);
  }
  // NETSCAPE2.0 application extension: loop count 0 = forever.
  out.addAll(const [0x21, 0xFF, 0x0B, 0x4E, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50,
      0x45, 0x32, 0x2E, 0x30, 0x03, 0x01, 0x00, 0x00, 0x00]);

  final buf = Uint8List(npx);
  final lzw = _Lzw(minSize);
  var delayAt = -1;
  for (var f = 0; f < frames.length; f++) {
    final base = f * npx;
    final delay = delays[f].clamp(0, 0xFFFF);
    final diff = delta && f > 0;
    var x0 = 0, y0 = 0, x1 = w - 1, y1 = h - 1;
    if (diff) {
      // Bounding box of pixels whose index changed since the last frame. The
      // canvas always equals the previous frame exactly, as nothing is lossy
      // after quantisation.
      final prev = base - npx;
      x0 = w;
      y0 = h;
      x1 = -1;
      y1 = -1;
      for (var y = 0; y < h; y++) {
        final row = y * w;
        for (var x = 0; x < w; x++) {
          if (idx[base + row + x] != idx[prev + row + x]) {
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
            if (y < y0) y0 = y;
            y1 = y;
          }
        }
      }
      if (x1 < 0) {
        final merged = (out[delayAt] | (out[delayAt + 1] << 8)) + delay;
        if (merged <= 0xFFFF) {
          out[delayAt] = merged & 0xFF;
          out[delayAt + 1] = merged >> 8;
          continue;
        }
        x0 = y0 = x1 = y1 = 0; // delay overflow: a 1x1 transparent frame
      }
    }
    final cw = x1 - x0 + 1, ch = y1 - y0 + 1;
    var n = 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final p = base + y * w + x;
        final v = idx[p];
        buf[n++] = diff && v == idx[p - npx] ? trans : v;
      }
    }
    // Graphic Control Extension (spec 23): disposal 1 (leave in place),
    // transparency flag set.
    out.addAll(const [0x21, 0xF9, 0x04, 0x05]);
    delayAt = out.length;
    out
      ..u16(delay)
      ..add(trans)
      ..add(0)
      // Image Descriptor (spec 20), no local table, not interlaced.
      ..add(0x2C)
      ..u16(x0)
      ..u16(y0)
      ..u16(cw)
      ..u16(ch)
      ..add(0);
    lzw.encode(out, buf, n);
  }
  out.add(0x3B); // trailer
  return out.toBytes();
}

/// Maps every pixel of every frame to a palette index. Returns the palette
/// (at most 255 colours, 0xRRGGBB) and indices for all frames back to back.
(Int32List, Uint8List) _index(List<Frame> frames) {
  final npx = frames.first.pixelCount;
  final cols = Int32List(frames.length * npx);
  var o = 0;
  for (final f in frames) {
    final rgb = f.rgb;
    for (var i = 0; i < npx * 3; i += 3) {
      cols[o++] = (rgb[i] << 16) | (rgb[i + 1] << 8) | rgb[i + 2];
    }
  }
  final sorted = _radixSort(cols);
  var u = 0;
  for (var i = 0; i < sorted.length; i++) {
    if (i == 0 || sorted[i] != sorted[i - 1]) u++;
  }
  final uniq = Int32List(u), counts = Int32List(u);
  u = -1;
  for (var i = 0; i < sorted.length; i++) {
    if (i == 0 || sorted[i] != sorted[i - 1]) uniq[++u] = sorted[i];
    counts[u]++;
  }

  final Int32List palette;
  final lut = Uint8List(uniq.length);
  if (uniq.length <= 255) {
    palette = uniq;
    for (var i = 0; i < lut.length; i++) {
      lut[i] = i;
    }
  } else {
    palette = _quantise(uniq, counts, 255);
    for (var i = 0; i < lut.length; i++) {
      lut[i] = _nearest(palette, uniq[i]);
    }
  }

  final idx = Uint8List(cols.length);
  var last = -1, li = 0;
  for (var i = 0; i < cols.length; i++) {
    final c = cols[i];
    if (c != last) {
      last = c;
      li = lut[_find(uniq, c)];
    }
    idx[i] = li;
  }
  return (palette, idx);
}

/// LSD radix sort of 24-bit colours, one byte per pass.
Int32List _radixSort(Int32List a) {
  var src = Int32List.fromList(a), tmp = Int32List(a.length);
  final count = Int32List(257);
  for (var shift = 0; shift < 24; shift += 8) {
    count.fillRange(0, 257, 0);
    for (var i = 0; i < src.length; i++) {
      count[((src[i] >> shift) & 0xFF) + 1]++;
    }
    for (var i = 0; i < 256; i++) {
      count[i + 1] += count[i];
    }
    for (var i = 0; i < src.length; i++) {
      final v = src[i];
      tmp[count[(v >> shift) & 0xFF]++] = v;
    }
    final t = src;
    src = tmp;
    tmp = t;
  }
  return src;
}

/// Index of [v] in the ascending list [a], which must contain it.
int _find(Int32List a, int v) {
  var lo = 0, hi = a.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (a[mid] < v) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

// Channel weights for colour distance: green matters most, blue least.
const _wr = 3, _wg = 4, _wb = 2;
const _sample = 16384;
const _kMeansIterations = 8;

int _nearest(Int32List palette, int c) {
  final r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
  var best = 0, bestD = 0x7FFFFFFF;
  for (var q = 0; q < palette.length; q++) {
    final p = palette[q];
    final dr = r - ((p >> 16) & 0xFF), dg = g - ((p >> 8) & 0xFF), db = b - (p & 0xFF);
    final d = _wr * dr * dr + _wg * dg * dg + _wb * db * db;
    if (d < bestD) {
      bestD = d;
      best = q;
      if (d == 0) break;
    }
  }
  return best;
}

class _Box {
  _Box(this.s, this.e, Int32List order, Int32List col, Int32List wt) {
    var sr = 0.0, sg = 0.0, sb = 0.0, qr = 0.0, qg = 0.0, qb = 0.0;
    for (var i = s; i < e; i++) {
      final c = col[order[i]];
      final w = wt[order[i]].toDouble();
      final r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
      weight += w;
      sr += w * r;
      sg += w * g;
      sb += w * b;
      qr += w * r * r;
      qg += w * g * g;
      qb += w * b * b;
    }
    vr = _wr * (qr - sr * sr / weight);
    vg = _wg * (qg - sg * sg / weight);
    vb = _wb * (qb - sb * sb / weight);
    error = vr + vg + vb;
    mr = sr / weight;
    mg = sg / weight;
    mb = sb / weight;
  }

  final int s, e; // range in the order list
  double weight = 0;
  late final double vr, vg, vb, error, mr, mg, mb;
}

/// Picks [k] colours for the unique colours [col] (ascending) with pixel
/// counts [wt]: variance-based median cut, refined by weighted k-means. Black
/// is kept exact when present, since "off" LEDs are where errors show most.
Int32List _quantise(Int32List col, Int32List wt, int k) {
  final u = col.length;
  final hasBlack = col[0] == 0;
  final target = hasBlack ? k - 1 : k;
  // Sample evenly through the (sorted) colours to bound the work.
  final sample = <int>[];
  for (var i = 0; i < (u > _sample ? _sample : u); i++) {
    final j = u > _sample ? i * u ~/ _sample : i;
    if (j != 0 || !hasBlack) sample.add(j);
  }
  final order = Int32List.fromList(sample);
  final boxes = [_Box(0, order.length, order, col, wt)];
  while (boxes.length < target) {
    var best = -1;
    for (var i = 0; i < boxes.length; i++) {
      final x = boxes[i];
      if (x.e - x.s > 1 && x.error > 0 && (best < 0 || x.error > boxes[best].error)) {
        best = i;
      }
    }
    if (best < 0) break;
    final b = boxes[best];
    final shift = b.vr >= b.vg && b.vr >= b.vb ? 16 : (b.vg >= b.vb ? 8 : 0);
    // Keys are unique (colours are), so any sort gives the same order.
    int key(int j) => ((col[j] >> shift) & 0xFF) * 0x1000000 + col[j];
    final seg = order.sublist(b.s, b.e)..sort((x, y) => key(x).compareTo(key(y)));
    order.setRange(b.s, b.e, seg);
    // Split at the weighted median, keeping both halves non-empty.
    final half = b.weight / 2;
    var acc = 0.0, m = b.s;
    while (m < b.e - 1) {
      acc += wt[order[m]];
      m++;
      if (acc >= half) break;
    }
    boxes[best] = _Box(b.s, m, order, col, wt);
    boxes.add(_Box(m, b.e, order, col, wt));
  }

  final fixed = boxes.length, kk = fixed + (hasBlack ? 1 : 0);
  final cr = Float64List(kk), cg = Float64List(kk), cb = Float64List(kk);
  for (var q = 0; q < fixed; q++) {
    cr[q] = boxes[q].mr;
    cg[q] = boxes[q].mg;
    cb[q] = boxes[q].mb;
  }
  // The black centroid (last, if any) stays at 0,0,0.
  final assign = Int32List(sample.length)..fillRange(0, sample.length, -1);
  final sw = Float64List(kk), sr = Float64List(kk);
  final sg = Float64List(kk), sb = Float64List(kk);
  for (var it = 0; it < _kMeansIterations; it++) {
    var changed = false;
    sw.fillRange(0, kk, 0);
    sr.fillRange(0, kk, 0);
    sg.fillRange(0, kk, 0);
    sb.fillRange(0, kk, 0);
    for (var n = 0; n < sample.length; n++) {
      final j = sample[n], c = col[j];
      final r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
      var bi = 0;
      var bd = double.infinity;
      for (var q = 0; q < kk; q++) {
        final dr = r - cr[q], dg = g - cg[q], db = b - cb[q];
        final d = _wr * dr * dr + _wg * dg * dg + _wb * db * db;
        if (d < bd) {
          bd = d;
          bi = q;
        }
      }
      if (assign[n] != bi) {
        assign[n] = bi;
        changed = true;
      }
      final w = wt[j].toDouble();
      sw[bi] += w;
      sr[bi] += w * r;
      sg[bi] += w * g;
      sb[bi] += w * b;
    }
    for (var q = 0; q < fixed; q++) {
      if (sw[q] > 0) {
        cr[q] = sr[q] / sw[q];
        cg[q] = sg[q] / sw[q];
        cb[q] = sb[q] / sw[q];
      }
    }
    if (!changed) break;
  }
  return Int32List.fromList([
    for (var q = 0; q < kk; q++)
      ((cr[q] + 0.5).toInt() << 16) |
          ((cg[q] + 0.5).toInt() << 8) |
          (cb[q] + 0.5).toInt(),
  ]);
}

/// Variable-width LZW (spec 22 and Appendix F), written as data sub-blocks.
class _Lzw {
  _Lzw(this.minSize) : _table = Int16List(4096 << minSize);

  final int minSize;
  // Child code for (prefix code << minSize | pixel), 0 = none (real codes
  // added to the dictionary start at the clear code + 2).
  final Int16List _table;
  int _dirty = 0; // codes whose rows may hold entries from the last frame
  late _Bytes _out;
  int _acc = 0, _bits = 0, _size = 0, _lenAt = 0, _count = 0;

  void encode(_Bytes out, Uint8List px, int n) {
    final clear = 1 << minSize;
    _table.fillRange(0, _dirty << minSize, 0);
    _out = out;
    out.add(minSize);
    _lenAt = out.length;
    out.add(0); // sub-block length, patched as bytes arrive
    _count = 0;
    _acc = 0;
    _bits = 0;
    _size = minSize + 1;
    var next = clear + 2;
    _emit(clear);
    var prefix = px[0];
    for (var i = 1; i < n; i++) {
      final k = px[i];
      final key = (prefix << minSize) | k;
      final c = _table[key];
      if (c != 0) {
        prefix = c;
        continue;
      }
      _emit(prefix);
      if (next < 4096) {
        // Widen as soon as the next code needs it: the decoder adds this
        // entry one code later and widens at the same point.
        if (next >= (1 << _size)) _size++;
        _table[key] = next++;
      } else {
        // Dictionary full: clear (at 12 bits) and start over.
        _emit(clear);
        _table.fillRange(0, next << minSize, 0);
        _size = minSize + 1;
        next = clear + 2;
      }
      prefix = k;
    }
    _emit(prefix);
    if (next >= (1 << _size) && _size < 12) _size++;
    _emit(clear + 1); // end of information
    _dirty = next;
    if (_bits > 0) _byte(_acc & 0xFF);
    if (_count > 0) {
      out[_lenAt] = _count;
      out.add(0); // block terminator
    } // else the empty placeholder is the terminator
  }

  void _emit(int code) {
    _acc |= code << _bits;
    _bits += _size;
    while (_bits >= 8) {
      _byte(_acc & 0xFF);
      _acc >>= 8;
      _bits -= 8;
    }
  }

  void _byte(int b) {
    _out.add(b);
    if (++_count == 255) {
      _out[_lenAt] = 255;
      _lenAt = _out.length;
      _out.add(0);
      _count = 0;
    }
  }
}

/// A growable byte buffer that can patch bytes already written.
class _Bytes {
  _Bytes(int capacity) : _buf = Uint8List(capacity < 64 ? 64 : capacity);

  Uint8List _buf;
  int length = 0;

  int operator [](int i) => _buf[i];
  void operator []=(int i, int v) => _buf[i] = v;

  void add(int b) {
    if (length == _buf.length) _grow(1);
    _buf[length++] = b;
  }

  void addAll(List<int> bytes) {
    _grow(bytes.length);
    _buf.setRange(length, length + bytes.length, bytes);
    length += bytes.length;
  }

  void u16(int v) {
    add(v & 0xFF);
    add((v >> 8) & 0xFF);
  }

  void _grow(int extra) {
    if (length + extra <= _buf.length) return;
    var cap = _buf.length * 2;
    while (cap < length + extra) {
      cap *= 2;
    }
    _buf = Uint8List(cap)..setRange(0, length, _buf);
  }

  Uint8List toBytes() => _buf.sublist(0, length);
}
