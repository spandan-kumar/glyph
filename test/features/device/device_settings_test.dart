import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/device/widgets/device_settings.dart';

void main() {
  group('isDeviceSettingsUrl', () {
    bool ok(String url, [String host = '192.168.1.40']) =>
        isDeviceSettingsUrl(Uri.parse(url), host);

    test('allows pages on the device', () {
      expect(ok('http://192.168.1.40/settings'), isTrue);
      expect(ok('http://192.168.1.40/settings/wifi?x=1'), isTrue);
      expect(ok('http://192.168.1.40:80/update'), isTrue);
      expect(ok('http://wled-desk.local/settings', 'wled-desk.local'), isTrue);
      expect(ok('http://192.168.1.40:8080/settings', '192.168.1.40:8080'), isTrue);
    });

    test('blocks other sites, ports and schemes', () {
      expect(ok('https://kb.wled.me/'), isFalse);
      expect(ok('http://192.168.1.41/settings'), isFalse);
      expect(ok('http://192.168.1.40:8080/settings'), isFalse);
      expect(ok('http://192.168.1.40.evil.example/settings'), isFalse);
      expect(ok('https://192.168.1.40/settings'), isFalse);
      expect(ok('file:///data/data/dev.spandankumar.glyph/'), isFalse);
      expect(ok('javascript:alert(1)'), isFalse);
      expect(ok('intent://scan/#Intent;scheme=zxing;end'), isFalse);
    });
  });
}
