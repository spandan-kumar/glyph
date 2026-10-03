import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/devices.dart';

void main() {
  test('keptFileName slugs titles the way Keep names files', () {
    expect(keptFileName('Spooky Swirl'), 'spooky-swirl.gif');
    expect(keptFileName('Steamboat Whistle (1928)'), 'steamboat-whistle-1928.gif');
    expect(keptFileName('  Ocean Plasma!! '), 'ocean-plasma.gif');
    // Capped so WLED segment names and LittleFS paths stay short.
    expect(keptFileName('A very long animation title indeed').length, lessThanOrEqualTo(28));
  });
}
