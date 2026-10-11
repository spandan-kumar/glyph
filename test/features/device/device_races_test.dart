import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/features/device/device_manager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_wled.dart';

void main() {
  late FakeWled alpha, beta;
  late DeviceStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    alpha = FakeWled();
    beta = FakeWled();
    for (final (fake, name, size) in [
      (alpha, 'Alpha', 16),
      (beta, 'Beta', 32),
    ]) {
      final info = jsonDecode(fake.info) as Map<String, dynamic>;
      info['name'] = name;
      info['mac'] = '$name-mac';
      (info['leds'] as Map)['matrix'] = {'w': size, 'h': size};
      fake.info = jsonEncode(info);
    }
    store = DeviceStore(
      clientFactory: (host) => (host == 'alpha' ? alpha : beta).client(host),
    );
    await store.addAndSelect('alpha', 'Alpha');
  });
  tearDown(() => store.dispose());

  test(
    'a late refresh cannot replace selected device metadata or persisted name',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      alpha.beforeRequest = (r) async {
        if (r.url.path == '/json/info') {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        }
      };
      final old = store.refresh();
      await entered.future;
      await store.addAndSelect('beta', 'Beta');
      release.complete();
      await old;
      expect(store.selected!.host, 'beta');
      expect(store.selected!.name, 'Beta');
      expect(store.selected!.mac, 'Beta-mac');
      expect(store.info!.name, 'Beta');
      expect((store.caps!.width, store.caps!.height), (32, 32));
      final prefs = await SharedPreferences.getInstance();
      final saved = (jsonDecode(prefs.getString('devices.v1')!) as List)
          .cast<Map>();
      expect(saved.singleWhere((d) => d['host'] == 'beta')['name'], 'Beta');
    },
  );

  test(
    'an old failed refresh cannot clear the new connection or loading state',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      alpha.beforeRequest = (r) async {
        if (r.url.path == '/json/info') {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          throw http.ClientException('old device offline');
        }
      };
      final old = store.refresh();
      await entered.future;
      await store.addAndSelect('beta', 'Beta');
      release.complete();
      await old;
      expect(store.isConnected, isTrue);
      expect(store.info!.name, 'Beta');
      expect(store.error, isNull);
      expect(store.isLoading, isFalse);
    },
  );

  test('failed power writes cannot roll back another device', () async {
    final entered = Completer<void>(), release = Completer<void>();
    alpha.beforeRequest = (r) async {
      if (r.method == 'POST') {
        entered.complete();
        await release.future;
        throw http.ClientException('old write failed');
      }
    };
    final failed = expectLater(store.setPower(false), throwsA(anything));
    await entered.future;
    beta.state['on'] = false;
    await store.addAndSelect('beta', 'Beta');
    release.complete();
    await failed;
    expect(store.isOn, isFalse);
  });

  test(
    'selected clients are reused and old selections remain invalid',
    () async {
      final original = store.client!, generation = store.selectionGeneration;
      await store.addAndSelect('beta', 'Beta');
      await store.select(store.saved.first);
      expect(store.client, same(original));
      expect(store.isCurrent(original, generation), isFalse);
    },
  );

  test(
    'manager rejects old lists while the new device load is pending',
    () async {
      final aEntered = Completer<void>(), aRelease = Completer<void>();
      final bEntered = Completer<void>(), bRelease = Completer<void>();
      alpha.presets = {
        '1': {'n': 'Alpha only'},
      };
      beta.presets = {
        '2': {'n': 'Beta only'},
      };
      alpha.beforeRequest = (r) async {
        if (r.url.path == '/presets.json') {
          if (!aEntered.isCompleted) aEntered.complete();
          await aRelease.future;
        }
      };
      beta.beforeRequest = (r) async {
        if (r.url.path == '/presets.json') {
          if (!bEntered.isCompleted) bEntered.complete();
          await bRelease.future;
        }
      };
      final manager = DeviceManager(store);
      addTearDown(manager.dispose);
      final old = manager.load();
      await aEntered.future;
      await store.addAndSelect('beta', 'Beta');
      manager.syncHost();
      aRelease.complete();
      await old;
      await bEntered.future;
      expect(manager.presets, isEmpty);
      expect(manager.files, isEmpty);
      expect(manager.schedule, isNull);
      bRelease.complete();
      await manager.load();
      expect(manager.presets.single.name, 'Beta only');
    },
  );

  for (final kind in ['preset', 'nightlight']) {
    test(
      '$kind write still lands when a brightness drag bumps state meanwhile',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        alpha.beforeRequest = (r) async {
          if (r.method == 'POST' &&
              r.url.path == '/json/state' &&
              (r.body.contains('"ps"') || r.body.contains('"nl"'))) {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
        };
        final write = kind == 'preset'
            ? store.applyPreset(12)
            : store.setNightlight(true, minutes: 5);
        await entered.future;
        store.setBrightness(90); // bumps the read counter mid-write
        release.complete();
        await write;
        if (kind == 'preset') {
          expect(store.presetId, 12);
        } else {
          expect(store.nightlightOn, isTrue);
        }
      },
    );
  }
}
