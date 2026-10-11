import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/features/device/setup/setup_store.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/wled/layout.dart';
import 'package:glyph/wled/panel_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_setup_device.dart';

void main() {
  const host = '192.168.1.50';
  const mac = '48e729a39308';
  late FakeSetupDevice device;
  late DeviceStore devices;
  late SetupStore store;
  final delays = <Duration>[];

  /// The "before" state: a 16x8 matrix, 128 LEDs, streamed pixels mapped.
  Future<SetupSnapshot> takeSnapshot(
      {MatrixLayout layout = const MatrixLayout(flipX: true)}) async {
    final s = await device.client(host).setupState();
    return SetupSnapshot.of(s, host: host, appLayout: layout, takenAt: DateTime.utc(2026, 10, 10));
  }

  setUp(() async {
    delays.clear();
    device = FakeSetupDevice();
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([
        const SavedDevice(host: host, name: 'Desk', layout: MatrixLayout(rotation: 2), mac: mac).toJson(),
      ]),
      'devices.selected': host,
    });
    devices = DeviceStore(clientFactory: device.client);
    await devices.load();
    store = SetupStore(delay: (d) async => delays.add(d));
  });

  tearDown(() => devices.dispose());

  List<String> deviceWrites() => [for (final (k, _) in device.writes) k];

  test('snapshots persist per mac and can be cleared', () async {
    final snap = await takeSnapshot();
    expect(await store.has(mac), isFalse);
    await store.save(snap);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), contains('setup.snapshot.$mac'));
    final back = (await store.load(mac.toUpperCase()))!;
    expect(back.toJson(), snap.toJson());
    expect(back.appLayout, const MatrixLayout(flipX: true));
    expect(await store.load('other'), isNull);
    await store.clear(mac);
    expect(await store.has(mac), isFalse);
  });

  test('a corrupt snapshot reads as none', () async {
    SharedPreferences.setMockInitialValues({'setup.snapshot.$mac': '{not json'});
    expect(await store.load(mac), isNull);
  });

  test('restore without a snapshot does nothing', () async {
    final r = await store.restore(device.client(host), devices, mac: mac);
    expect(r.hadSnapshot, isFalse);
    expect(r.ok, isFalse);
    expect(device.writes, isEmpty);
  });

  test('restore writes only what changed, in order, and clears the snapshot', () async {
    final snap = await takeSnapshot();
    await store.save(snap);
    // The wizard changed everything it can.
    final c = device.client(host);
    await c.setLedCount(256, snap.outputEntry);
    await c.setPanelLayout(const DisplaySetup(16, 16, PanelWiring(corner: StartCorner.bottomRight, zigzag: true)));
    await c.setRealtimeMaps(false);
    await c.setCurrentLimit(2000);
    await devices.updateLayout(const MatrixLayout());
    device.writes.clear();

    final r = await store.restore(c, devices, mac: mac);

    expect(r.ok, isTrue, reason: '$r');
    expect(r.restored, SetupField.values.toSet());
    expect(deviceWrites(), [
      'POST /json/cfg', // rlm
      'POST /settings/2D',
      'POST /json/cfg', // led count
      'POST /json/cfg', // current limit
    ]);
    expect(device.writes[0].$2, {
      'if': {
        'live': {'rlm': true}
      }
    });
    expect(device.writes[1].$2, containsPair('P0W', '16'));
    expect(device.writes[1].$2, containsPair('P0H', '8'));
    final entry = ((device.writes[2].$2 as Map)['hw']['led']['ins'] as List).single as Map;
    expect(entry, {...snap.outputEntry, 'len': 128}, reason: 'the complete entry');
    expect(delays, [SetupStore.busSettle]);
    expect(device.writes[3].$2, {
      'hw': {
        'led': {'maxpwr': 1000}
      }
    });
    final after = await c.setupState();
    expect((after.width, after.height, after.ledCount, after.realtimeMaps, after.currentLimitMa),
        (16, 8, 128, true, 1000));
    expect(devices.saved.single.layout, const MatrixLayout(flipX: true));
    expect(await store.has(mac), isFalse);
  });

  test('fields that already match are not written', () async {
    final snap = await takeSnapshot(layout: const MatrixLayout(rotation: 2));
    await store.save(snap);
    final r = await store.restore(device.client(host), devices, mac: mac);
    expect(r.ok, isTrue);
    expect(device.writes, isEmpty);
    expect(r.restored, isEmpty);
    expect(r.unchanged, SetupField.values.toSet());
  });

  test('only the changed field is written', () async {
    final snap = await takeSnapshot(layout: const MatrixLayout(rotation: 2));
    await store.save(snap);
    final c = device.client(host);
    await c.setCurrentLimit(500);
    device.writes.clear();
    final r = await store.restore(c, devices, mac: mac);
    expect(r.restored, {SetupField.currentLimit});
    expect(deviceWrites(), ['POST /json/cfg']);
    expect(device.limit, 1000);
  });

  test('a device that was a strip goes back to a strip', () async {
    device = FakeSetupDevice(matrix: false, ledCount: 64);
    devices.dispose();
    devices = DeviceStore(clientFactory: device.client);
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([const SavedDevice(host: host, name: 'Desk', mac: mac).toJson()]),
      'devices.selected': host,
    });
    await devices.load();
    final snap = await takeSnapshot(layout: MatrixLayout.identity);
    expect(snap.isMatrix, isFalse);
    final c = device.client(host);
    await c.setPanelLayout(const DisplaySetup(8, 8, PanelWiring()));
    device.writes.clear();
    final r = await store.restore(c, devices, snapshot: snap, clearOnSuccess: false);
    expect(r.restored, {SetupField.layout});
    expect(device.writes.single.$2, {'SOMP': '0'});
    expect((await c.setupState()).isMatrix, isFalse);
  });

  test('a device that ignores the layout is reported, and the snapshot is kept', () async {
    final snap = await takeSnapshot(layout: const MatrixLayout(rotation: 2));
    await store.save(snap);
    final c = device.client(host);
    await c.setPanelLayout(const DisplaySetup(8, 8, PanelWiring()));
    device.ignoreLayout = true;
    final r = await store.restore(c, devices, mac: mac);
    expect(r.ok, isFalse);
    expect(r.failed.keys, [SetupField.layout]);
    expect(await store.has(mac), isTrue);
  });

  test('a different device MAC refuses all restoration writes', () async {
    final snap = await takeSnapshot();
    await store.save(snap);
    final other = FakeSetupDevice(mac: 'aabbccddeeff', ledCount: 16);
    final result = await store.restore(other.client(host), devices, snapshot: snap);
    expect(result.ok, isFalse);
    expect(result.deviceMismatch, isTrue);
    expect(other.writes, isEmpty);
    expect(await store.has(mac), isTrue);
  });

  test('successful writes followed by disconnection keep the backup', () async {
    final snap = await takeSnapshot();
    await store.save(snap);
    final c = device.client(host);
    await c.setCurrentLimit(500);
    device.afterRequest = (r) {
      if (r.method == 'POST') device.offline = true;
    };
    final result = await store.restore(c, devices, snapshot: snap);
    expect(device.limit, snap.currentLimitMa);
    expect(result.ok, isFalse);
    expect(result.verificationFailed, isTrue);
    expect(result.failed[SetupField.currentLimit], contains('verify'));
    expect(result.restored, isNot(contains(SetupField.currentLimit)));
    expect(await store.has(mac), isTrue);
  });

  test('undo restores all segment geometry after count and layout changes', () async {
    final c = device.client(host);
    device.state['seg'] = [
      {'id': 0, 'start': 0, 'stop': 8, 'startY': 0, 'stopY': 4, 'fx': 9},
      {'id': 1, 'start': 8, 'stop': 16, 'startY': 4, 'stopY': 8, 'grp': 2, 'spc': 1, 'fx': 12},
    ];
    final playback = await c.state();
    final snap = SetupSnapshot.of(await c.setupState(), host: host, playback: playback);
    await store.save(snap);
    await c.setLedCount(256, snap.outputEntry);
    await c.setPanelLayout(const DisplaySetup(16, 16, PanelWiring()));
    final result = await store.restore(c, devices, snapshot: snap);
    expect(result.ok, isTrue);
    expect(device.state['seg'], playback['seg']);
  });

  test('failed full-state restore keeps the backup for retry', () async {
    final c = device.client(host);
    final snap = SetupSnapshot.of(await c.setupState(), host: host, playback: await c.state());
    await store.save(snap);
    await c.setPanelLayout(const DisplaySetup(16, 16, PanelWiring()));
    device.beforeRequest = (r) async {
      if (r.method == 'POST' && r.url.path == '/json/state') throw Exception('disconnected');
    };
    final result = await store.restore(c, devices, snapshot: snap);
    expect(result.ok, isFalse);
    expect(result.playbackFailed, isTrue);
    expect(await store.has(mac), isTrue);
  });

  test('a locked device is reported without writing', () async {
    device = FakeSetupDevice(pin: '1234');
    final snap = SetupSnapshot(
        mac: mac, host: host, isMatrix: false, ledCount: 1, outputEntry: const {}, realtimeMaps: true, takenAt: DateTime.utc(2026));
    final r = await store.restore(device.client(host), devices, snapshot: snap);
    expect(r.ok, isFalse);
    expect(r.failed, isNotEmpty);
    // The refused write is reported; the device is untouched.
    expect(r.failed.keys, contains(SetupField.layout));
    expect(device.panel, isNotNull);
  });

  test('restore brings playback back after the layout is rewritten, from a stored snapshot', () async {
    device = FakeSetupDevice(playingFx: 53, playingName: 'the-starry-night.gif');
    devices.dispose();
    devices = DeviceStore(clientFactory: device.client);
    final c = device.client(host);
    final s = await c.setupState();
    final snap = SetupSnapshot.of(s,
        host: host, playback: await c.state(), takenAt: DateTime.utc(2026, 10, 10));
    await store.save(snap);
    await c.setPanelLayout(const DisplaySetup(16, 16, PanelWiring()));
    expect(device.fx, 0, reason: 'WLED recreated the segments');

    // As after an app restart: only the stored copy is left.
    final r = await store.restore(c, devices, mac: mac);
    expect(r.ok, isTrue, reason: '$r');
    expect(device.fx, 53);
    expect(device.seg0['n'], 'the-starry-night.gif');
    expect(device.seg0['start'], 0);
    expect(deviceWrites().last, 'POST /json/state');
    expect(await store.has(mac), isFalse);
  });

  test('a running preset or playlist is applied again, not the segment', () async {
    final c = device.client(host);
    await c.restorePlayback({'ps': 3, 'pl': -1, 'seg': [{'id': 0, 'fx': 9}]});
    await c.restorePlayback({'ps': 3, 'pl': 2});
    expect(device.writes.map((w) => w.$2), [{'ps': 3}, {'pl': 2}]);
  });
}
