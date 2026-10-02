import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/wled/layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_wled.dart';

void main() {
  late FakeWled wled;
  late DeviceStore store;

  setUp(() {
    wled = FakeWled();
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([
        const SavedDevice(host: '192.168.29.6', name: 'Matrix').toJson(),
        const SavedDevice(
          host: '192.168.29.7',
          name: 'Shelf',
          layout: MatrixLayout(flipX: true),
        ).toJson(),
      ]),
      'devices.selected': '192.168.29.6',
    });
    store = DeviceStore(clientFactory: wled.client);
  });

  tearDown(() => store.dispose());

  void expectPost((String, Map<String, dynamic>) post, String path, Map<String, Object> body) {
    expect(post.$1, path);
    expect(post.$2, body);
  }

  test('load connects and reads power, brightness and preset', () async {
    await store.load();
    expect(store.isConnected, isTrue);
    expect(store.isOn, isTrue);
    expect(store.brightness, 128);
    expect(store.presetId, 102);
    expect(store.playlistRunning, isFalse);
    expect(store.selected!.mac, '48e729a39308', reason: 'mac learnt from info');
  });

  test('playlist state: -1 none, 0 started by a save, id when applied', () async {
    await store.load();
    wled.state['pl'] = 0;
    await store.refreshState();
    expect((store.playlistRunning, store.playlistId), (true, null));
    wled.state['pl'] = 201;
    await store.refreshState();
    expect((store.playlistRunning, store.playlistId), (true, 201));
  });

  test('setPower is optimistic and posts on', () async {
    await store.load();
    var notified = 0;
    store.addListener(() => notified++);
    final f = store.setPower(false);
    expect(store.isOn, isFalse);
    await f;
    expectPost(wled.posts.last, '/json/state', {'on': false});
    expect(notified, greaterThan(0));
    await store.togglePower();
    expect(wled.posts.last.$2, {'on': true});
  });

  test('setPower reverts when the write fails', () async {
    await store.load();
    wled.offline = true;
    await expectLater(store.setPower(false), throwsA(anything));
    expect(store.isOn, isTrue);
  });

  test('brightness is debounced to one write with the last value', () async {
    await store.load();
    for (final v in [10, 40, 90, 0]) {
      store.setBrightness(v);
    }
    expect(store.brightness, 0);
    expect(wled.posts, isEmpty);
    await Future<void>.delayed(DeviceStore.brightnessDebounce * 2);
    // 0 would turn WLED off, so it is sent as 1.
    expect(wled.posts, hasLength(1));
    expectPost(wled.posts.single, '/json/state', {'bri': 1});
  });

  test('a state read during a pending brightness write keeps the slider value', () async {
    await store.load();
    store.setBrightness(200);
    await store.refreshState();
    expect(store.brightness, 200);
    await Future<void>.delayed(DeviceStore.brightnessDebounce * 2);
  });

  test('applyPreset posts ps and re-reads state', () async {
    await store.load();
    await store.applyPreset(1);
    expectPost(wled.posts.first, '/json/state', {'ps': 1});
    expect(store.presetId, 1);
  });

  test('renameOnDevice writes cfg id.name and the saved name', () async {
    await store.load();
    await store.renameOnDevice('Living room');
    expectPost(wled.posts.first, '/json/cfg', {
      'id': {'name': 'Living room'},
    });
    expect(store.selected!.name, 'Living room');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('devices.v1'), contains('Living room'));
  });

  test('mirrors persist and resolve to sized targets with their layout', () async {
    await store.load();
    await store.setMirror('192.168.29.7', true);
    expect(store.mirrorHosts, {'192.168.29.7'});
    final targets = await store.mirrorTargets();
    expect(targets.single.host, '192.168.29.7');
    expect((targets.single.width, targets.single.height), (16, 16));
    expect(targets.single.layout, const MatrixLayout(flipX: true));
    expect(store.isOnline('192.168.29.7'), isTrue);

    final again = DeviceStore(clientFactory: wled.client);
    addTearDown(again.dispose);
    await again.load();
    expect(again.mirrorHosts, {'192.168.29.7'});

    // The selected device never mirrors itself.
    await again.select(again.saved.last);
    expect(again.mirrorHosts, isEmpty);
    await store.setMirror('192.168.29.7', false);
    expect(await store.mirrorTargets(), isEmpty);
  });

  test('unreachable device reports an error and clears state', () async {
    wled.offline = true;
    await store.load();
    expect(store.isConnected, isFalse);
    expect(store.error, contains('192.168.29.6'));
    expect(store.isOn, isNull);
  });
}
