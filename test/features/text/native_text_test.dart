import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/text/native_text.dart';
import 'package:glyph/features/text/text_settings.dart';

void main() {
  // Excerpt of /json/pal from WLED 16.0.1.
  const pals = ['Default', '* Random Cycle', '* Color 1', 'Party', 'Lava', 'Ocean', 'Rainbow', 'Sunset'];

  test('finds the effect by name', () {
    expect(nativeEffectId(['Solid', 'Blink', ' Scrolling Text ', 'Image']), 2);
    expect(nativeEffectId(['Solid']), isNull);
  });

  test('clock tokens', () {
    expect(nativeText(TextSettings(date: false), 'clock'), '#HH0:#MM0');
    expect(nativeText(TextSettings(hour24: false, seconds: true, date: false), 'clock'), '#HH:#MM0:#SS0');
    expect(nativeText(TextSettings(), 'clock'), '#HH0:#MM0 #DAY #DD #MON');
  });

  test('text is flattened and capped to the segment name length', () {
    expect(nativeText(TextSettings(text: ' a\nb '), 'text'), 'a b');
    expect(nativeText(TextSettings(text: 'x' * 80), 'text', maxLength: 32).length, 32);
  });

  test('speed maps px/s onto the sx step interval', () {
    expect(nativeSpeed(4), 0); // 250 ms per pixel
    expect(nativeSpeed(20), 255); // 50 ms per pixel
    expect(nativeSpeed(40), 255);
    expect(nativeSpeed(10), 191); // 100 ms
  });

  test('font sizes respect matrix height', () {
    expect(nativeFont(TextSettings(font: 'tiny'), 16), 0);
    expect(nativeFont(TextSettings(font: 'classic', large: false), 16), 128);
    expect(nativeFont(TextSettings(font: 'bold', large: false), 16), 192);
    expect(nativeFont(TextSettings(font: 'bold'), 16), 255);
    expect(nativeFont(TextSettings(font: 'bold'), 8), 128);
    expect(nativeFont(TextSettings(font: 'classic'), 6), 0);
  });

  test('segment for solid text', () {
    final seg = nativeSegment(
        s: TextSettings(text: 'Hi', color: 0xFF8000, direction: 'right'),
        mode: 'text',
        effectId: 122,
        wledPalettes: pals,
        rows: 16);
    expect(seg['fx'], 122);
    expect(seg['n'], 'Hi');
    expect(seg['pal'], 0);
    expect(seg['col'], [[255, 128, 0], [0, 0, 0], [255, 128, 0]]);
    expect(seg['o3'], isTrue);
    expect(seg['o1'], isFalse);
    expect(seg['c3'], 16);
    expect(seg['ix'], 128);
  });

  test('palette modes pick WLED palettes by name', () {
    Map<String, dynamic> seg(TextSettings s) =>
        nativeSegment(s: s, mode: 'text', effectId: 1, wledPalettes: pals, rows: 16);
    expect(seg(TextSettings(colorMode: 'rainbow', palette: 'lava'))['pal'], 6);
    final g = seg(TextSettings(colorMode: 'gradient', palette: 'ocean'));
    expect(g['pal'], 5);
    expect(g['o1'], isTrue);
    expect(seg(TextSettings(colorMode: 'animated', palette: 'galaxy'))['pal'], 6); // falls back to Rainbow
    expect(seg(TextSettings(direction: 'up'))['ix'], 0);
    expect(nativePaletteId('ocean', const []), 0);
  });
}
