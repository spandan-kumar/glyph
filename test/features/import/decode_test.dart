import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/import/decode.dart';
import 'package:image/image.dart' as img;

img.Image _solid(int w, int h, int r, int g, int b) =>
    img.Image(width: w, height: h)..clear(img.ColorRgb8(r, g, b));

Uint8List _animatedGif(List<img.Image> frames, List<int> delaysMs) {
  final first = frames.first..frameDuration = delaysMs.first;
  for (var i = 1; i < frames.length; i++) {
    first.addFrame(frames[i]..frameDuration = delaysMs[i]);
  }
  return img.encodeGif(first);
}

void main() {
  test('animated GIF decodes every frame with its delay', () {
    final bytes = _animatedGif(
      [_solid(8, 8, 255, 0, 0), _solid(8, 8, 0, 255, 0), _solid(8, 8, 0, 0, 255)],
      [100, 200, 50],
    );
    final src = decodeSource(bytes);
    expect(src.frameCount, 3);
    expect(src.delaysMs, [100, 200, 50]);
    expect((src.width, src.height), (8, 8));
    expect(src.frames[0].sublist(0, 3), [255, 0, 0]);
    expect(src.frames[1].sublist(0, 3), [0, 255, 0]);
    expect(src.frames[2].sublist(0, 3), [0, 0, 255]);
    expect(src.looksPixelArt, isTrue);
  });

  test('frame cap samples evenly and keeps the total duration', () {
    final frames = [for (var i = 0; i < 12; i++) _solid(4, 4, i * 20, 0, 0)];
    final bytes = _animatedGif(frames, List.filled(12, 100));
    final src = decodeSource(bytes, maxFrames: 5);
    expect(src.frameCount, 4); // stride 3
    expect(src.sourceFrameCount, 12);
    expect(src.wasSampled, isTrue);
    expect(src.delaysMs.fold<int>(0, (a, b) => a + b), 1200);
    expect(src.frames[1][0], 60); // frame 3
  });

  test('PNG decodes and large images shrink to the working size', () {
    final png = img.encodePng(_solid(1200, 600, 10, 20, 30));
    final src = decodeSource(png);
    expect(src.frameCount, 1);
    expect(src.width, ImportLimits.maxWorkingSide);
    expect(src.height, ImportLimits.maxWorkingSide ~/ 2);
    expect(src.sourceWidth, 1200);
    expect(src.frames.first.sublist(0, 3), [10, 20, 30]);
    expect(src.looksPixelArt, isFalse);
  });

  test('APNG decodes only the first maxFrames with their delays', () {
    final image = _solid(4, 4, 255, 0, 0)..frameDuration = 120;
    image.addFrame(_solid(4, 4, 0, 255, 0)..frameDuration = 0);
    image.addFrame(_solid(4, 4, 0, 0, 255)..frameDuration = 80);
    final src = decodeSource(img.encodePng(image), maxFrames: 2);
    expect(src.frameCount, 2);
    expect(src.sourceFrameCount, 3);
    expect(src.wasSampled, isTrue);
    expect(src.delaysMs, [120, 100]);
    expect(src.frames[0].sublist(0, 3), [255, 0, 0]);
    expect(src.frames[1].sublist(0, 3), [0, 255, 0]);
  });

  test('APNG never decodes missing frames beyond maxFrames', () {
    final encoder = img.PngEncoder()..start(3);
    encoder.addFrame(_solid(4, 4, 255, 0, 0)..frameDuration = 120);
    encoder.addFrame(_solid(4, 4, 0, 255, 0)..frameDuration = 80);
    // The header declares a third frame, but decoding it would fail.
    final bytes = encoder.finish()!;
    expect(() => decodeSource(bytes), throwsA(isA<ImportException>()));
    final src = decodeSource(bytes, maxFrames: 2);
    expect(src.frameCount, 2);
    expect(src.delaysMs, [120, 80]);
  });

  test('APNG keeps patch offsets, blending and restore-previous disposal', () {
    // Original 2×1 RGB art: red canvas, green patch at x=1 (restore previous),
    // then blue at x=0. Each patch is a separately compressed APNG frame.
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAACGFjVEwAAAADAAAAAM7tusAA'
      'AAAaZmNUTAAAAAAAAAACAAAAAQAAAAAAAAAAAGQD6AAAECjlZAAAAA5JREFUeJxj+M/A8B+E'
      'ARH3A/3jxfXvAAAAGmZjVEwAAAABAAAAAQAAAAEAAAABAAAAAADIA+gCARlldloAAAARZmRB'
      'VAAAAAJ4nGNg+M/wHwAEAQH/YufpnAAAABpmY1RMAAAAAwAAAAEAAAABAAAAAAAAAAABLAPo'
      'AABmRJrdAAAAEWZkQVQAAAAEeJxjYGD4/x8AAwIB/w257mEAAAAASUVORK5CYII=',
    );
    final src = decodeSource(bytes);
    expect(src.delaysMs, [100, 200, 300]);
    expect(src.frames[0], [255, 0, 0, 255, 0, 0]);
    expect(src.frames[1], [255, 0, 0, 0, 255, 0]);
    expect(src.frames[2], [0, 0, 255, 255, 0, 0]);
  });

  test('decoded RGB budget rejects oversized animations before decoding', () {
    final image = _solid(4, 4, 255, 0, 0);
    image.addFrame(_solid(4, 4, 0, 255, 0));
    image.addFrame(_solid(4, 4, 0, 0, 255));
    final bytes = img.encodePng(image);
    const budget = 4 * 4 * 3 * 2;
    expect(
      () => decodeSource(bytes, maxFrames: 2, maxDecodedBytes: budget - 1),
      throwsA(isA<ImportException>().having((e) => e.message, 'message',
          'That animation is too large to import. Try a shorter or smaller one.')),
    );
    // Only the capped frame count contributes to the budget; equality fits.
    expect(decodeSource(bytes, maxFrames: 2, maxDecodedBytes: budget).frameCount, 2);
  });

  test('decoded RGB budget counts a still image as one frame', () {
    final bytes = img.encodePng(_solid(4, 4, 255, 0, 0));
    expect(
      () => decodeSource(bytes, maxDecodedBytes: 4 * 4 * 3 - 1),
      throwsA(isA<ImportException>().having((e) => e.message, 'message',
          'That animation is too large to import. Try a shorter or smaller one.')),
    );
  });

  test('transparency flattens onto black (LED off)', () {
    final im = img.Image(width: 2, height: 1, numChannels: 4)
      ..setPixelRgba(0, 0, 255, 255, 255, 255)
      ..setPixelRgba(1, 0, 255, 255, 255, 0);
    final src = decodeSource(img.encodePng(im));
    expect(src.frames.first, [255, 255, 255, 0, 0, 0]);
  });

  test('JPEG decodes', () {
    final src = decodeSource(img.encodeJpg(_solid(32, 16, 200, 200, 200)));
    expect((src.width, src.height), (32, 16));
    expect(src.frames.first[0], closeTo(200, 3));
  });

  test('junk and HEIC are rejected with a readable message', () {
    expect(() => decodeSource(Uint8List.fromList(List.filled(64, 7))),
        throwsA(isA<ImportException>()));
    final heic = Uint8List.fromList([0, 0, 0, 24, ...'ftypheic'.codeUnits, ...List.filled(16, 0)]);
    expect(
        () => decodeSource(heic),
        throwsA(isA<ImportException>()
            .having((e) => e.message, 'message', contains('HEIC'))));
  });
}
