import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/device/boot_intro.dart';
import 'package:glyph/features/device/device_features.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_wled.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('switching the device off holds the stream; on releases it', () async {
    BootIntro.autoInstall = false;
    addTearDown(() => BootIntro.autoInstall = true);
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([const SavedDevice(host: '192.168.29.6', name: 'Desk').toJson()]),
      'devices.selected': '192.168.29.6',
    });
    final wled = FakeWled();
    final devices = DeviceStore(clientFactory: wled.client);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await devices.load();
    DeviceFeatures.attach(devices: devices, playback: playback);
    expect(playback.streamHeld, isFalse);

    await devices.setPower(false);
    expect(playback.streamHeld, isTrue, reason: 'no live frames may wake an off device');

    await devices.setPower(true);
    expect(playback.streamHeld, isFalse);
  });
}
