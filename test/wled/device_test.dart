import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/wled/layout.dart';

import 'fixtures.dart';

void main() {
  final esp32 = WledInfo.fromJson(jsonDecode(infoEsp32V16));
  final esp8266 = WledInfo.fromJson(jsonDecode(infoEsp8266V014));

  test('parses real ESP32 / WLED 16 info', () {
    expect(esp32.name, 'WLED');
    expect(esp32.version, '16.0.1');
    expect(esp32.arch, 'esp32');
    expect(esp32.brand, 'WLED');
    expect(esp32.ledCount, 256);
    expect((esp32.matrixWidth, esp32.matrixHeight), (16, 16));
    expect((esp32.fsUsedKb, esp32.fsTotalKb), (98, 983));
    expect(esp32.flashMb, 4);
    expect(esp32.rssi, -90);
    expect(esp32.signal, 20);
    expect(esp32.fxCount, 220);
    expect(esp32.ip, '192.168.29.6');
    expect(esp32.mac, '48e729a39308');
    expect(esp32.isLive, isFalse);
    expect(esp32.liveSource, '');
    expect(esp32.isEsp8266, isFalse);
    expect(esp32.versionAtLeast(16), isTrue);
    expect(esp32.versionAtLeast(16, 1), isFalse);
  });

  test('parses ESP8266 info without matrix, fs or flash', () {
    expect(esp8266.arch, 'esp8266');
    expect(esp8266.isEsp8266, isTrue);
    expect(esp8266.name, 'Desk strip');
    expect(esp8266.ledCount, 30);
    expect(esp8266.matrixWidth, isNull);
    expect(esp8266.matrixHeight, isNull);
    expect(esp8266.fsUsedKb, isNull);
    expect(esp8266.flashMb, isNull);
    expect(esp8266.hasMatrix, isFalse);
    expect(esp8266.versionParts, (0, 14, 4));
    expect(esp8266.versionAtLeast(0, 14), isTrue);
  });

  test('tolerates an empty object', () {
    final i = WledInfo.fromJson({});
    expect(i.ledCount, 0);
    expect(i.version, '');
    expect(DeviceCapabilities.detect(i, const []).canStream, isFalse);
  });

  test('ESP32 with Image effect can stream and play GIFs', () {
    expect(effectsEsp32V16[53], 'Image');
    final c = DeviceCapabilities.detect(esp32, effectsEsp32V16);
    expect(c.canStream, isTrue);
    expect(c.canPlayGifs, isTrue);
    expect(c.imageEffectId, 53);
    expect(c.is2D, isTrue);
    expect((c.width, c.height), (16, 16));
    expect(c.freeFsBytes, (983 - 98) * 1024);
    expect(c.fitsFile(100 * 1024), isTrue);
    expect(c.fitsFile(c.freeFsBytes - 32 * 1024), isTrue);
    expect(c.fitsFile(c.freeFsBytes - 32 * 1024 + 1), isFalse);
  });

  test('Image effect is looked up by name, not index', () {
    final fx = ['Solid', 'Blink', 'Image'];
    expect(DeviceCapabilities.detect(esp32, fx).imageEffectId, 2);
  });

  test('ESP8266 lists Image but cannot play GIFs', () {
    final c = DeviceCapabilities.detect(esp8266, effectsEsp32V16);
    expect(c.canStream, isTrue);
    expect(c.canPlayGifs, isFalse);
    expect(c.is2D, isFalse);
    expect((c.width, c.height), (30, 1));
    expect(c.freeFsBytes, 0);
    expect(c.fitsFile(1), isFalse);
    expect(c.suggestedFps, 30);
  });

  test('older ESP32 firmware without Image effect', () {
    final fx = effectsEsp32V16.where((e) => e != 'Image').toList();
    final c = DeviceCapabilities.detect(esp32, fx);
    expect(c.canPlayGifs, isFalse);
    expect(c.imageEffectId, isNull);
  });

  test('realtime disabled in cfg blocks streaming', () {
    expect(
        DeviceCapabilities.detect(esp32, effectsEsp32V16, realtimeEnabled: false)
            .canStream,
        isFalse);
  });

  test('SavedDevice json round trip', () {
    const d = SavedDevice(
        host: '192.168.29.6',
        name: 'Niji',
        layout: MatrixLayout(serpentine: true, rotation: 1),
        mac: '48e729a39308');
    final back = SavedDevice.fromJson(jsonDecode(jsonEncode(d.toJson())));
    expect(back.host, d.host);
    expect(back.name, d.name);
    expect(back.layout, d.layout);
    expect(back.mac, d.mac);
    expect(SavedDevice.fromJson({'host': '10.0.0.2'}).layout, MatrixLayout.identity);
  });
}
