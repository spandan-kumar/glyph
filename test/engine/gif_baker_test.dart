import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/gif_baker.dart';
import 'package:glyph/engine/led_gamma.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';
import 'package:image/image.dart' as img;

import 'gif_encoder_test.dart' show decodeTestGif;

int _uniqueColours(List<Frame> frames) => {
      for (final f in frames)
        for (var i = 0; i < f.pixelCount; i++) f.get(i % f.width, i ~/ f.width),
    }.length;

void main() {
  for (final id in ['plasma', 'fire', 'fireworks', 'galaxy']) {
    test('$id bakes to a small, faithful, looping 16x16 GIF', () {
      final g = generatorById(id);
      expect(g.id, id);
      final params = Params.defaultsFor(g);
      final pal = paletteById(g.defaultPalette);
      final result = bakeGif(
          generator: g, params: params, palette: pal, width: 16, height: 16);
      // Same seed + same timeline => identical frames to compare against.
      final loop = renderLoop(
          generator: g, params: params, palette: pal, width: 16, height: 16);
      // The GIF carries the LED black floor (white balance, black floor).
      final frames = ledFramesForDevice(loop.frames);
      final n = frames.length;
      // About 4 s at 20 fps, trimmed or stretched to where it loops best.
      expect(result.frameCount, n);
      expect(n, inInclusiveRange(60, 100));
      expect(result.duration, Duration(milliseconds: n * 50));
      expect(loop.seconds, closeTo(n / 20, 1e-9));
      // ignore: avoid_print
      print('$id: ${result.bytes.length} bytes, $n frames');
      // The old per-frame-palette encoder needed ~85 KB for 4 s of this.
      expect(result.bytes.length, lessThan(40 * 1024));

      final decoded = decodeTestGif(result.bytes);
      expect(decoded.loop, 0);
      expect(decoded.frames.length, lessThanOrEqualTo(n));
      expect(decoded.delays.fold(0, (a, b) => a + b), n * 5);

      final shown = decoded.timeline(List.filled(n, 5));
      if (_uniqueColours(frames) <= 255) {
        for (var i = 0; i < n; i++) {
          expect(shown[i], frames[i].rgb, reason: 'frame $i');
        }
      } else {
        // Shared 255-colour palette: close, not exact.
        var se = 0;
        for (var i = 0; i < n; i++) {
          for (var j = 0; j < frames[i].rgb.length; j++) {
            final e = shown[i][j] - frames[i].rgb[j];
            se += e * e;
          }
        }
        expect(se / (n * 16 * 16 * 3), lessThan(20), reason: 'PSNR > 35 dB');
      }

      // An independent decoder agrees on the structure.
      final other = img.decodeGif(result.bytes)!;
      expect(other.numFrames, decoded.frames.length);
      expect(other.loopCount, 0);
      expect(other.frames.first.frameDuration, decoded.delays.first * 10);
    });
  }

  test('seamless: false bakes exactly the requested seconds', () {
    final g = generatorById('plasma');
    final r = bakeGif(
        generator: g,
        params: Params.defaultsFor(g),
        palette: paletteById(g.defaultPalette),
        width: 16,
        height: 16,
        seamless: false);
    expect(r.frameCount, 80);
    expect(r.duration, const Duration(seconds: 4));
  });

  test('plasma and fire take the exact (<= 255 colour) path', () {
    for (final id in ['plasma', 'fire']) {
      final g = generatorById(id);
      final frames = renderFrames(
          generator: g,
          params: Params.defaultsFor(g),
          palette: paletteById(g.defaultPalette),
          width: 16,
          height: 16);
      expect(_uniqueColours(frames), lessThanOrEqualTo(255), reason: id);
    }
  });

  test('non-square bake keeps its size', () {
    final g = generatorById('helix');
    final r = bakeGif(
        generator: g,
        params: Params.defaultsFor(g),
        palette: paletteById('neon'),
        width: 8,
        height: 32,
        seconds: 1,
        fps: 10,
        seamless: false);
    expect(r.frameCount, 10);
    expect(r.duration, const Duration(seconds: 1));
    final d = decodeTestGif(r.bytes);
    expect(d.width, 8);
    expect(d.height, 32);
    expect(d.frames.length, lessThanOrEqualTo(10));
    expect(d.delays.fold(0, (a, b) => a + b), 100);
    expect(d.delays.every((x) => x % 10 == 0), isTrue);
  });

  test('bakeFrames encodes hand-made frames exactly', () {
    final a = Frame(4, 4)..fill(0x112233);
    final b = Frame(4, 4)
      ..set(0, 0, 0xFF0000)
      ..set(3, 3, 0x00FF00)
      ..set(1, 2, 0x0000FF);
    final r = bakeFrames([a, b], fps: 5);
    expect(r.frameCount, 2);
    expect(r.duration, const Duration(milliseconds: 400));
    final d = decodeTestGif(r.bytes);
    expect(d.frames.length, 2);
    expect(d.delays, [20, 20]);
    // Stored as WLED should play them (white balance, black floor).
    final led = ledFramesForDevice([a, b]);
    expect(d.frames[0], led[0].rgb);
    expect(d.frames[1], led[1].rgb);
  });

  test('fps that does not divide 100 keeps the total duration', () {
    final frames = [for (var i = 0; i < 30; i++) Frame(2, 2)..set(0, 0, 0x400000 | i * 8)];
    final r = bakeFrames(frames, fps: 30);
    expect(r.duration, const Duration(seconds: 1));
    final d = decodeTestGif(r.bytes);
    expect(d.delays.take(6).toList(), [3, 4, 3, 3, 4, 3]);
    expect(d.delays.fold(0, (a, b) => a + b), 100);
  });

  test('frames with more than 256 colours still encode', () {
    final f = Frame(32, 32);
    for (var i = 0; i < 1024; i++) {
      f.set(i % 32, i ~/ 32, rgb(i % 256, (i * 7) % 256, i ~/ 4));
    }
    final r = bakeFrames([f, f.copy()]);
    final d = decodeTestGif(r.bytes);
    expect(d.frames.length, 1, reason: 'identical frames merge');
    expect(d.delays, [10]);
    expect(d.width, 32);
    expect(img.decodeGif(r.bytes)!.numFrames, 1);
  });

  test('rejects an empty frame list', () {
    expect(() => bakeFrames(const []), throwsArgumentError);
  });
}
