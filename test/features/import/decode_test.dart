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
