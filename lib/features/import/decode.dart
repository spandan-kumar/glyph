import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'processing.dart' show resampleArea;

/// Limits that keep decoding within a phone's memory and patience.
abstract final class ImportLimits {
  /// Frames kept after decoding; longer animations are sampled evenly.
  static const maxFrames = 300;

  /// Frames decoded at all; anything beyond is dropped.
  static const maxDecodedFrames = 1500;

  /// Largest source canvas accepted (40 MP).
  static const maxSourcePixels = 40000000;

  static const maxFileBytes = 40 * 1024 * 1024;

  /// Total working pixels across all kept frames (×3 bytes of RGB).
  static const workingPixelBudget = 9000000;
  static const maxWorkingSide = 384;
  static const minWorkingSide = 64;
}

class ImportException implements Exception {
  const ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A decoded image or animation, flattened onto black and downscaled to a
/// working size that still leaves room to crop and zoom.
class DecodedSource {
  DecodedSource({
    required this.width,
    required this.height,
    required this.frames,
    required this.delaysMs,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceFrameCount,
    required this.format,
  }) : assert(frames.isNotEmpty && frames.length == delaysMs.length);

  /// Wraps already-decoded RGB frames (tests, other features).
  factory DecodedSource.rgb(int w, int h, List<Uint8List> frames, {List<int>? delaysMs}) =>
      DecodedSource(
        width: w,
        height: h,
        frames: frames,
        delaysMs: delaysMs ?? List.filled(frames.length, 100),
        sourceWidth: w,
        sourceHeight: h,
        sourceFrameCount: frames.length,
        format: 'rgb',
      );

  final int width, height;

  /// Row-major RGB, [width]×[height].
  final List<Uint8List> frames;
  final List<int> delaysMs;
  final int sourceWidth, sourceHeight, sourceFrameCount;
  final String format;

  int get frameCount => frames.length;
  bool get isAnimated => frames.length > 1;
  bool get wasSampled => sourceFrameCount > frames.length;

  /// Small sources are probably pixel art and look best with nearest.
  bool get looksPixelArt => sourceWidth <= 64 && sourceHeight <= 64;
}

/// Decodes GIF, PNG, JPEG, WebP, BMP and the other formats package:image
/// reads. Animated GIF and WebP are composited frame by frame on one canvas
/// and shrunk straight away, so memory stays bounded by [ImportLimits].
DecodedSource decodeSource(Uint8List bytes, {int maxFrames = ImportLimits.maxFrames}) {
  if (bytes.length > ImportLimits.maxFileBytes) {
    throw const ImportException('That file is too big (max 40 MB).');
  }
  if (_isHeic(bytes)) {
    throw const ImportException(
        'HEIC photos aren\'t supported yet. Share it as JPEG or PNG first.');
  }
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) throw const ImportException('Not an image Glyph can read.');
  final info = decoder.startDecode(bytes);
  if (info == null) throw const ImportException('The image looks damaged.');
  if (info.width * info.height > ImportLimits.maxSourcePixels) {
    throw const ImportException('That image is too large (max 40 megapixels).');
  }
  final name = decoder.format.name;
  try {
    if (decoder is img.GifDecoder && info.numFrames > 1) {
      return _decodeGif(decoder, decoder.info!, maxFrames, name);
    }
    if (decoder is img.WebPDecoder && decoder.info!.hasAnimation) {
      return _decodeWebP(decoder, decoder.info!, maxFrames, name);
    }
    var image = decoder.decode(bytes);
    if (image == null) throw const ImportException('The image looks damaged.');
    if (image.exif.imageIfd.hasOrientation) image = img.bakeOrientation(image);
    final frames = image.frames;
    final b = _Builder(image.width, image.height, frames.length, maxFrames, name);
    for (final f in frames) {
      final canvas = Uint8List(image.width * image.height * 3);
      _draw(canvas, image.width, image.height, f, 0, 0, blend: true);
      b.add(canvas, f.frameDuration > 0 ? f.frameDuration : (frames.length > 1 ? 100 : 1000));
    }
    return b.build();
  } on ImportException {
    rethrow;
  } catch (e) {
    throw ImportException('Couldn\'t decode the image ($e).');
  }
}

/// Isolate entry point for `compute`.
DecodedSource decodeSourceMessage(Uint8List bytes) => decodeSource(bytes);

bool _isHeic(Uint8List b) {
  if (b.length < 12) return false;
  final box = String.fromCharCodes(b.sublist(4, 8));
  final brand = String.fromCharCodes(b.sublist(8, 12));
  return box == 'ftyp' && const {'heic', 'heix', 'hevc', 'mif1', 'msf1', 'avif'}.contains(brand);
}

DecodedSource _decodeGif(img.GifDecoder dec, img.GifInfo info, int maxFrames, String name) {
  final w = info.width, h = info.height;
  final n = math.min(info.numFrames, ImportLimits.maxDecodedFrames);
  final b = _Builder(w, h, n, maxFrames, name);
  var canvas = Uint8List(w * h * 3);
  for (var i = 0; i < n; i++) {
    final d = info.frames[i];
    final saved = d.disposal == 3 ? Uint8List.fromList(canvas) : null;
    final frame = dec.decodeFrame(i);
    if (frame != null) _draw(canvas, w, h, frame, d.x, d.y, blend: false);
    // Browsers treat 0-1 cs as 100 ms; GIFs in the wild rely on it.
    b.add(canvas, d.duration <= 1 ? 100 : d.duration * 10);
    if (d.disposal == 2) {
      _clear(canvas, w, h, d.x, d.y, d.width, d.height);
    } else if (saved != null) {
      canvas = saved;
    }
  }
  return b.build();
}

DecodedSource _decodeWebP(img.WebPDecoder dec, img.WebPInfo info, int maxFrames, String name) {
  final w = info.width, h = info.height;
  final n = math.min(info.numFrames, ImportLimits.maxDecodedFrames);
  final b = _Builder(w, h, n, maxFrames, name);
  final canvas = Uint8List(w * h * 3);
  for (var i = 0; i < n; i++) {
    final f = info.frames[i];
    final frame = dec.decodeFrame(i);
    if (frame != null) _draw(canvas, w, h, frame, f.x, f.y, blend: f.blendFrame);
    b.add(canvas, f.duration <= 0 ? 100 : f.duration);
    if (f.clearFrame) _clear(canvas, w, h, f.x, f.y, f.width, f.height);
  }
  return b.build();
}

/// Composites [frame] at ([ox], [oy]) onto an RGB canvas over black.
/// [blend] = false treats alpha as on/off (GIF transparency).
void _draw(Uint8List canvas, int w, int h, img.Image frame, int ox, int oy,
    {required bool blend}) {
  final rgba = _rgba(frame);
  final fw = frame.width, fh = frame.height;
  for (var y = 0; y < fh; y++) {
    final cy = oy + y;
    if (cy < 0 || cy >= h) continue;
    for (var x = 0; x < fw; x++) {
      final cx = ox + x;
      if (cx < 0 || cx >= w) continue;
      final si = (y * fw + x) * 4, di = (cy * w + cx) * 3;
      final a = rgba[si + 3];
      if (a == 0) continue;
      if (a == 255 || !blend) {
        canvas[di] = rgba[si];
        canvas[di + 1] = rgba[si + 1];
        canvas[di + 2] = rgba[si + 2];
      } else {
        final k = a / 255;
        for (var c = 0; c < 3; c++) {
          canvas[di + c] = (canvas[di + c] * (1 - k) + rgba[si + c] * k).round();
        }
      }
    }
  }
}

void _clear(Uint8List canvas, int w, int h, int x0, int y0, int fw, int fh) {
  final a = math.max(0, x0), b = math.min(w, x0 + fw);
  if (b <= a) return;
  for (var y = math.max(0, y0); y < math.min(h, y0 + fh); y++) {
    canvas.fillRange((y * w + a) * 3, (y * w + b) * 3, 0);
  }
}

Uint8List _rgba(img.Image im) {
  final x = im.format == img.Format.uint8 && im.numChannels == 4 && !im.hasPalette
      ? im
      : im.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
  return x.getBytes(order: img.ChannelOrder.rgba);
}

/// Collects composited canvases: samples evenly down to [maxFrames]
/// (merging delays so the duration holds) and shrinks each to working size.
class _Builder {
  _Builder(this.w, this.h, int frameCount, int maxFrames, this.format)
      : n = frameCount,
        stride = (frameCount / maxFrames).ceil().clamp(1, 1 << 20) {
    final kept = (frameCount / stride).ceil();
    final perFrame = ImportLimits.workingPixelBudget / kept;
    var s = math.min(1.0, ImportLimits.maxWorkingSide / math.max(w, h));
    s = math.min(s, math.sqrt(perFrame / (w * h)));
    s = math.max(s, math.min(1.0, ImportLimits.minWorkingSide / math.max(w, h)));
    ww = math.max(1, (w * s).round());
    wh = math.max(1, (h * s).round());
  }

  final int w, h, n, stride;
  final String format;
  late final int ww, wh;
  final frames = <Uint8List>[];
  final delays = <int>[];
  var _seen = 0;

  void add(Uint8List canvas, int delayMs) {
    if (_seen++ % stride == 0) {
      frames.add(ww == w && wh == h
          ? Uint8List.fromList(canvas)
          : resampleArea(canvas, w, h, 0, 0, w.toDouble(), h.toDouble(), ww, wh));
      delays.add(delayMs);
    } else {
      delays[delays.length - 1] += delayMs;
    }
  }

  DecodedSource build() {
    if (frames.isEmpty) throw const ImportException('The image has no frames.');
    return DecodedSource(
      width: ww,
      height: wh,
      frames: frames,
      delaysMs: delays,
      sourceWidth: w,
      sourceHeight: h,
      sourceFrameCount: n,
      format: format,
    );
  }
}
