import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/gif_encoder.dart';
import 'package:glyph/engine/led_gamma.dart';

import 'gif_encoder_test.dart' show decodeTestGif;

/// WLED 16 master brightness: colors.cpp color_fade(c, bri, video = true),
/// as BusDigital::setPixelColor applies it after gamma. Channels above a
/// quarter of the brightest keep at least level 1.
List<int> _wledFade(List<int> c, int bri) {
  final maxc = (c.reduce(math.max) >> 2) + 1;
  return [for (final x in c) ((x * bri + 0x7F) >> 8) | (x > maxc ? 1 : 0)];
}

/// App colour → LED drive levels on the panel: Glyph's stream correction
/// (no-gc device, gamma 2.2), then WLED's brightness.
List<int> _onLeds(int rgb, int bri, {LedWhiteBalance balance = ws2812WhiteBalance}) {
  final c = LedCorrection(balance: balance);
  final out = c.apply(Uint8List.fromList([(rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF]));
  return _wledFade(out, bri);
}

/// Blue/green as perceived: LED levels decoded back through gamma 2.2.
double _perceivedBG(List<int> led) => math.pow(led[2] / led[1], 1 / 2.2).toDouble();

void main() {
  test('gamma table matches WLED colors.cpp calcGammaTable', () {
    for (final g in [1.0, 1.8, 2.2, 2.8]) {
      final t = ledGammaTable(g);
      expect(t[0], 0);
      expect(t[255], 255);
      for (var i = 1; i < 256; i++) {
        expect(t[i], (math.pow(i / 255, g) * 255 + 0.5).toInt(), reason: 'gamma $g at $i');
        if (i > 1) expect(t[i], greaterThanOrEqualTo(t[i - 1]));
      }
    }
    final t = ledGammaTable(2.2);
    expect([t[0xE8], t[0x28], t[0x3C], t[0x0E]], [207, 4, 11, 0]);
    expect(ledGammaTable(1), [for (var i = 0; i < 256; i++) i]);
  });

  test('black threshold is the first raw value lit at level 3', () {
    expect(ledBlackThreshold(2.2), 32);
    expect(ledGammaTable(2.2)[31], 2);
    expect(ledGammaTable(2.2)[32], 3);
    expect(ledBlackThreshold(1), 3);
  });

  test('LedCorrection floors on the brightest LED level, then applies gamma', () {
    final c = LedCorrection(balance: neutralWhiteBalance);
    final out = c.apply(Uint8List.fromList([31, 31, 31, 32, 0, 0, 0, 0, 200, 0, 0, 0]));
    expect(out, [0, 0, 0, 3, 0, 0, 0, 0, ledGammaTable(2.2)[200], 0, 0, 0]);
    final keep = LedCorrection(applyGamma: false, balance: neutralWhiteBalance);
    expect(keep.apply(Uint8List.fromList([31, 10, 0, 32, 10, 0])), [0, 0, 0, 32, 10, 0]);
  });

  test('white balance cuts green by 0.8 in LED space either way', () {
    final applied = LedCorrection();
    expect(applied.apply(Uint8List.fromList([255, 255, 255])), [255, 204, 255]);
    // Left to the device's gamma: 255 x 0.8^(1/2.2) = 230, and WLED's own
    // table then gives 230 → 203.
    final deferred = LedCorrection(applyGamma: false);
    expect(deferred.apply(Uint8List.fromList([255, 255, 255])), [255, 230, 255]);
    expect(ledGammaTable(2.2)[230], closeTo(204, 1));
  });

  group('low master brightness (WLED bri 30-80)', () {
    const lightBlues = [0x3CC8FF, 0x8EE8FF, 0x19D3DA, 0x40A0FF];

    test('light blues keep their perceived blue/green ratio within 20%', () {
      for (final c in lightBlues) {
        final original = (c & 0xFF) / ((c >> 8) & 0xFF);
        for (final bri in [30, 40, 80]) {
          final led = _onLeds(c, bri);
          expect(led[2], greaterThan(led[1]), reason: '${c.toRadixString(16)} @ $bri: blue leads');
          expect(_perceivedBG(led) / original, inInclusiveRange(1.0, 1.2),
              reason: '${c.toRadixString(16)} @ $bri: $led');
        }
      }
      // #8EE8FF at bri 40: before, streamed linear, G and B drove almost
      // equally (22, 36, 40) and the brighter WS2812 green won.
      expect(_onLeds(0x8EE8FF, 40), [11, 27, 41]);
    });

    test('red stays red, near-black stays off', () {
      final red = _onLeds(0xE8283C, 40);
      expect(red, [33, 0, 2]);
      for (final bri in [30, 40, 80, 255]) {
        expect(_onLeds(0x0E0E0E, bri), [0, 0, 0]);
        expect(_onLeds(0x1A1A1A, bri), [0, 0, 0]);
      }
    });
  });

  group('GIFs for the matrix (encodeGif forLeds)', () {
    Frame swatch() => Frame(4, 1)
      ..set(0, 0, 0xE8283C)
      ..set(1, 0, 0x0E0E0E)
      ..set(2, 0, 0x1F1F1F)
      ..set(3, 0, 0x200000);

    test('balance and black floor applied, gamma left to WLED', () {
      final f = swatch();
      final g = decodeTestGif(encodeGif([f], [10], forLeds: true));
      // WLED gamma-corrects Image effect output itself (FX_fcn.cpp show).
      expect(g.frames.single, [0xE8, 36, 0x3C, 0, 0, 0, 0, 0, 0, 0x20, 0, 0]);
      expect(f.get(1, 0), 0x0E0E0E, reason: 'input frames untouched');
    });

    test('plain encodeGif keeps exact colours (sharing)', () {
      final f = swatch();
      expect(decodeTestGif(encodeGif([f], [10])).frames.single, f.rgb);
    });
  });
}
