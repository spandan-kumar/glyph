import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/wled/wled_client.dart';

void main() {
  test('keptFileName slugs titles the way Keep names files', () {
    expect(keptFileName('Spooky Swirl'), 'spooky-swirl.gif');
    expect(keptFileName('Steamboat Whistle (1928)'), 'steamboat-whistle-1928.gif');
    expect(keptFileName('  Ocean Plasma!! '), 'ocean-plasma.gif');
    // Capped so WLED segment names and LittleFS paths stay short.
    expect(keptFileName('A very long animation title indeed').length, lessThanOrEqualTo(28));
  });

  test('long titles that share a start get different files', () {
    const a = 'Northern lights over the frozen lake';
    const b = 'Northern lights over the frozen sea';
    expect(keptFileName(a), isNot(keptFileName(b)));
    expect(keptFileName(a), keptFileName(a));
    expect(keptFileName(a).length, lessThanOrEqualTo(28));
    expect(WledClient.matchesGifName(keptFileName(a), keptFileName(b)), isFalse);
    expect(WledClient.matchesGifName(keptFileName(a), keptFileName(a)), isTrue);
  });
}
