import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/wled/wled_client.dart';

import 'fake_wled.dart';

void main() {
  late FakeWled wled;
  late WledClient client;

  setUp(() {
    wled = FakeWled();
    client = wled.client('send-test');
    wled.state['seg'] = [
      {'id': 0, 'fx': 53, 'n': 'same.gif'},
    ];
    wled.presets['42'] = {
      'n': 'Same',
      'seg': [
        {'id': 0, 'fx': 53, 'n': 'same.gif'},
      ],
    };
    wled.files.add({'name': 'same.gif', 'type': 'file', 'size': 10});
    wled.gifs['/same.gif'] = List.filled(10, 1);
  });
  tearDown(() => client.close());

  Future<int> send({bool Function()? canSwitch}) async =>
      client.saveGifToDevice(
        fileName: 'same.gif',
        gif: Uint8List.fromList(List.filled(20, 2)),
        presetName: 'Same',
        presetId: 42,
        caps: await client.capabilities(),
        canSwitch: canSwitch,
      );

  String playing() => (wled.state['seg'] as List).first['n'] as String;

  test(
    'replacement reuses the preset, retires its old file and preserves shared files',
    () async {
      expect(await send(), 42);
      expect(playing(), 'same-00.gif');
      expect((wled.presets['42']['seg'] as List).first['n'], 'same-00.gif');
      // The file the preset played before is retired once nothing uses it,
      // even though this client didn't create it (e.g. before an app restart).
      expect(wled.deleted, ['/same.gif']);
      await send();
      expect(playing(), 'same.gif'); // the freed name is reused
      expect(wled.deleted, ['/same.gif', '/same-00.gif']);
      // A different Saved look now shares that file: it must survive.
      wled.presets['43'] = {...wled.presets['42'] as Map, 'n': 'Shared'};
      await send();
      expect(playing(), 'same-00.gif');
      expect(wled.gifs.containsKey('/same.gif'), isTrue);
      expect(wled.presets['43']['seg'].first['n'], 'same.gif');
      expect(wled.presets.keys.where((k) => k == '42'), hasLength(1));
    },
  );

  test(
    'cancellation after upload leaves playback and preset unchanged',
    () async {
      var current = true;
      wled.beforeRequest = (r) async {
        if (r.url.path == '/upload') current = false;
      };
      await expectLater(
        send(canSwitch: () => current),
        throwsA(isA<WledException>()),
      );
      expect(playing(), 'same.gif');
      expect((wled.presets['42']['seg'] as List).first['n'], 'same.gif');
      expect(wled.posts.where((p) => p.$1 == '/json/state'), isEmpty);
      expect(wled.deleted, ['/same-00.gif']);
    },
  );

  test(
    'replacement counts the file it retires as free space, but not more',
    () async {
      final detected = await client.capabilities();
      DeviceCapabilities capsWith(int free) => DeviceCapabilities(
        canStream: true,
        canPlayGifs: true,
        imageEffectId: 53,
        freeFsBytes: DeviceCapabilities.fsSafetyMarginBytes + free,
        is2D: true,
        width: detected.width,
        height: detected.height,
        ledCount: detected.ledCount,
        isEsp8266: false,
      );
      Future<int> sendWith(DeviceCapabilities caps) => client.saveGifToDevice(
        fileName: 'same.gif',
        gif: Uint8List(20),
        presetName: 'Same',
        caps: caps,
        presetId: 42,
      );
      // 20 B new, 10 B old: 9 B free is short even after the swap.
      await expectLater(sendWith(capsWith(9)), throwsA(isA<WledException>()));
      expect(wled.uploads, isEmpty);
      expect(wled.posts, isEmpty);
      expect(playing(), 'same.gif');
      // 10 B free + the 10 B old file fits.
      expect(await sendWith(capsWith(10)), 42);
      expect(playing(), 'same-00.gif');
    },
  );

  test(
    'long catalog names retain their identity within the filename limit',
    () async {
      final base = '${'x' * 24}.gif';
      wled.files.add({'name': base, 'type': 'file', 'size': 10});
      await client.saveGifToDevice(
        fileName: base,
        gif: Uint8List(20),
        presetName: 'Long',
        presetId: 42,
        caps: await client.capabilities(),
      );
      expect(playing().length, WledClient.maxGifNameLength);
      expect(WledClient.matchesGifName(base, playing()), isTrue);
      expect(WledClient.matchesGifName('other.gif', playing()), isFalse);
    expect(WledClient.matchesGifName(base, '${'x' * 24}-000.gif'), isFalse);
    expect(WledClient.matchesGifName('.gif', playing()), isFalse);
    },
  );
}
