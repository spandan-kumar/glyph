import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/import/decode.dart';
import 'package:glyph/features/import/processing.dart';

Uint8List solid(int w, int h, int r, int g, int b) {
  final out = Uint8List(w * h * 3);
  for (var i = 0; i < out.length; i += 3) {
    out[i] = r;
    out[i + 1] = g;
    out[i + 2] = b;
  }
  return out;
}

List<int> px(Uint8List rgb, int w, int x, int y) {
  final i = (y * w + x) * 3;
  return [rgb[i], rgb[i + 1], rgb[i + 2]];
}

const neutral = ImportSettings();

void main() {
  group('resample', () {
    test('2×2 checker averages to mid grey', () {
      final src = Uint8List.fromList([255, 255, 255, 0, 0, 0, 0, 0, 0, 255, 255, 255]);
      final out = resampleArea(src, 2, 2, 0, 0, 2, 2, 1, 1);
      expect(out, [128, 128, 128]);
    });

    test('a 1-px line survives a 4× shrink as a quarter-bright pixel', () {
      // 8×8 black with one white column at x = 1; nearest would drop it.
      final src = solid(8, 8, 0, 0, 0);
      for (var y = 0; y < 8; y++) {
        src.setAll((y * 8 + 1) * 3, [255, 255, 255]);
      }
      final area = resampleArea(src, 8, 8, 0, 0, 8, 8, 2, 2);
      expect(px(area, 2, 0, 0), [64, 64, 64]);
      expect(px(area, 2, 1, 0), [0, 0, 0]);
      final near = resampleNearest(src, 8, 8, 0, 0, 8, 8, 2, 2);
      expect(px(near, 2, 0, 0), [0, 0, 0]);
    });

    test('fractional coverage weights pixels by overlap', () {
      // 3 px (0, 90, 180) into 2: [0..1.5) and [1.5..3).
      final src = Uint8List.fromList([0, 0, 0, 90, 90, 90, 180, 180, 180]);
      final out = resampleArea(src, 3, 1, 0, 0, 3, 1, 2, 1);
      expect(out[0], 30); // (0*1 + 90*0.5) / 1.5
      expect(out[3], 150); // (90*0.5 + 180*1) / 1.5
    });

    test('nearest keeps hard pixel-art edges when upscaling', () {
      final src = Uint8List.fromList([255, 0, 0, 0, 0, 255]);
      final out = resampleNearest(src, 2, 1, 0, 0, 2, 1, 4, 1);
      expect([for (var i = 0; i < 4; i++) out[i * 3]], [255, 255, 0, 0]);
    });
  });

  group('geometry', () {
    test('fit letterboxes a wide image into a square', () {
      // 4×2 red image into 4×4: rows 0 and 3 black, middle rows red.
      final src = solid(4, 2, 255, 0, 0);
      final f = renderFrame(src, 4, 2, neutral.copyWith(fit: FitMode.fit), 4, 4);
      for (var x = 0; x < 4; x++) {
        expect(f.get(x, 0), 0);
        expect(f.get(x, 1), 0xFF0000);
        expect(f.get(x, 2), 0xFF0000);
        expect(f.get(x, 3), 0);
      }
    });

    test('fit pillarboxes a tall image', () {
      final p = placement(2, 4, neutral.copyWith(fit: FitMode.fit), 8, 8);
      expect((p.dx, p.dy, p.dw, p.dh), (2, 0, 4, 8));
    });

    test('fill crops the centre with the matrix aspect', () {
      final p = placement(200, 100, neutral, 16, 16);
      expect((p.sx, p.sy, p.sw, p.sh), (50.0, 0.0, 100.0, 100.0));
      expect((p.dx, p.dy, p.dw, p.dh), (0, 0, 16, 16));
    });

    test('fill crop window is clamped inside the image and zooms', () {
      final s = neutral.copyWith(cropX: 0, cropY: 0.5, zoom: 2);
      final (x, y, w, h) = cropWindow(200, 100, s, 16, 16);
      expect((x, y, w, h), (0.0, 25.0, 50.0, 50.0));
    });

    test('stretch uses the whole image and target', () {
      final p = placement(30, 10, neutral.copyWith(fit: FitMode.stretch), 16, 16);
      expect((p.sx, p.sy, p.sw, p.sh), (0.0, 0.0, 30.0, 10.0));
    });

    test('rotate and flip match a direct pixel permutation', () {
      // 3×2 image with distinct pixels, rendered 1:1 so no resampling blur.
      final src = Uint8List.fromList(List.generate(18, (i) => i * 10));
      for (final turns in [0, 1, 2, 3]) {
        for (final fh in [false, true]) {
          final s = neutral.copyWith(fit: FitMode.stretch, quarterTurns: turns, flipH: fh);
          final (ow, oh) = orientedSize(3, 2, turns);
          final f = renderFrame(src, 3, 2, s, ow, oh);
          expect(f.rgb, orient(src, 3, 2, turns, flipH: fh), reason: 'turns $turns flip $fh');
        }
      }
    });

    test('clockwise rotation moves the top-left pixel to the top-right', () {
      final src = solid(2, 2, 0, 0, 0)..setAll(0, [255, 0, 0]);
      final o = orient(src, 2, 2, 1);
      expect(px(o, 2, 1, 0), [255, 0, 0]);
      final (rx, ry) = orientedToRaw(1.5, 0.5, 2, 2, neutral.copyWith(quarterTurns: 1));
      expect((rx, ry), (0.5, 0.5));
    });
  });

  group('adjustments', () {
    test('neutral settings are the identity', () {
      final t = ToneMap(neutral);
      for (final c in [0x000000, 0x123456, 0xFFFFFF, 0x808080]) {
        expect(t.apply((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF), c);
      }
    });

    test('brightness, contrast, saturation, gamma', () {
      expect(ToneMap(neutral.copyWith(brightness: 0.2)).apply(100, 100, 100), 0x979797);
      expect(ToneMap(neutral.copyWith(contrast: 2)).apply(32, 192, 255), 0x00FFFF);
      // Saturation 0 is luma grey: 0.299 * 255 = 76.
      expect(ToneMap(neutral.copyWith(saturation: 0)).apply(255, 0, 0), 0x4C4C4C);
      // Gamma 2: 0.5^2 = 0.25 (128 → 64).
      expect(ToneMap(neutral.copyWith(gamma: 2)).apply(128, 255, 0), (64 << 16) | (255 << 8));
    });

    test('LED defaults darken midtones and keep black/white', () {
      final t = ToneMap(ImportSettings.ledDefaults);
      expect(t.apply(0, 0, 0), 0);
      expect(t.apply(255, 255, 255), 0xFFFFFF);
      expect(t.apply(128, 128, 128) & 0xFF, lessThan(128));
    });

    test('background removal: near-black and picked colour', () {
      final rgb = Uint8List.fromList([10, 12, 8, 200, 30, 30, 0, 250, 5, 40, 40, 40]);
      final dark = Uint8List.fromList(rgb);
      adjustPixels(dark, neutral.copyWith(background: BackgroundMode.dark, bgTolerance: 0.1));
      expect(dark, [0, 0, 0, 200, 30, 30, 0, 250, 5, 40, 40, 40]);

      final green = Uint8List.fromList(rgb);
      adjustPixels(green,
          neutral.copyWith(background: BackgroundMode.colour, bgColor: 0x00FF00, bgTolerance: 0.1));
      expect(green, [10, 12, 8, 200, 30, 30, 0, 0, 0, 40, 40, 40]);
    });

    test('removed pixels stay off even with a brightness boost', () {
      final rgb = Uint8List.fromList([5, 5, 5]);
      adjustPixels(rgb, neutral.copyWith(background: BackgroundMode.dark, brightness: 0.5));
      expect(rgb, [0, 0, 0]);
    });
  });

  group('palette', () {
    test('reduces to n colours and keeps black exact', () {
      final f = Uint8List(64 * 3);
      for (var i = 0; i < 64; i++) {
        if (i < 8) continue; // black
        f[i * 3] = i * 4;
        f[i * 3 + 1] = 255 - i * 4;
        f[i * 3 + 2] = 128;
      }
      final pal = buildPalette([f], 4);
      expect(pal.length, lessThanOrEqualTo(4));
      expect(pal.first, 0);
      quantize([f], 8, pal);
      expect(countColors([f]), lessThanOrEqualTo(4));
      expect(f.sublist(0, 24).every((v) => v == 0), isTrue);
    });

    test('ordered dither is deterministic and stays within the palette', () {
      final a = Uint8List(16 * 3);
      for (var i = 0; i < 16; i++) {
        a.fillRange(i * 3, i * 3 + 3, 60 + i * 8);
      }
      final b = Uint8List.fromList(a);
      final pal = [0x404040, 0xC0C0C0];
      quantize([a], 4, pal, dither: true);
      quantize([b], 4, pal, dither: true);
      expect(a, b);
      final colours = {for (var i = 0; i < 16; i++) a[i * 3]};
      expect(colours, {0x40, 0xC0});
    });

    test('processClip skips quantising when colours already fit', () {
      final src = DecodedSource.rgb(2, 1, [Uint8List.fromList([255, 0, 0, 0, 0, 255])]);
      final clip = processClip(
          src, neutral.copyWith(fit: FitMode.stretch, pixelArt: true, colors: 2), 2, 1);
      expect(clip.frames.single.rgb, [255, 0, 0, 0, 0, 255]);
    });
  });

  group('timing', () {
    final delays = [100, 100, 100, 100, 100, 100];

    test('trim selects an inclusive range', () {
      final p = selectFrames(delays, neutral.copyWith(trimStart: 1, trimEnd: () => 3));
      expect([for (final x in p) x.$1], [1, 2, 3]);
    });

    test('frame skip merges delays so duration holds', () {
      final p = selectFrames(delays, neutral.copyWith(frameStep: 2));
      expect(p, [(0, 200), (2, 200), (4, 200)]);
    });

    test('speed scales delays with a 20 ms floor', () {
      expect(selectFrames(delays, neutral.copyWith(speed: 2)).first.$2, 50);
      expect(selectFrames([30], neutral.copyWith(speed: 4)).first.$2, 20);
    });

    test('processClip carries the selected delays', () {
      final src = DecodedSource.rgb(4, 4, List.generate(6, (_) => solid(4, 4, 9, 9, 9)),
          delaysMs: delays);
      final clip = processClip(src, neutral.copyWith(frameStep: 3), 2, 2);
      expect(clip.frames.length, 2);
      expect(clip.delaysMs, [300, 300]);
      expect((clip.width, clip.height), (2, 2));
    });
  });

  test('runImportJob reports a GIF size', () {
    final src = DecodedSource.rgb(8, 8, [solid(8, 8, 255, 0, 0), solid(8, 8, 0, 0, 255)]);
    final out = runImportJob(ImportJob(src, neutral, 16, 16));
    expect(out.clip.frames.length, 2);
    expect(out.gifBytes, greaterThan(30));
  });
}
