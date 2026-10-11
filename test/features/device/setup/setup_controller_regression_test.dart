import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/device/device_time.dart';
import 'package:glyph/features/device/setup/setup_controller.dart';
import 'package:glyph/wled/discovery.dart';
import 'package:glyph/wled/panel_setup.dart';
import 'package:http/http.dart' as http;

import 'fake_setup_device.dart';
import 'fake_setup_wifi.dart';
import 'setup_rig.dart';

bool rlmWrite(http.Request r, bool value) =>
    r.method == 'POST' &&
    r.url.path == '/json/cfg' &&
    r.body.contains('"rlm":$value');

void main() {
  Future<SetupRig> rigFor(
    WidgetTester tester, {
    FakeSetupDevice? device,
    bool dispose = true,
  }) async {
    final rig = await SetupRig.create(
      tester,
      device: device ?? FakeSetupDevice(width: 8, height: 8, ledCount: 32),
    );
    rig.controller.begin();
    await settle(tester);
    if (rig.controller.step == SetupStep.look) {
      rig.controller.lookDoesNotMatch();
      await settle(tester);
    }
    expect(rig.controller.step, SetupStep.size);
    addTearDown(() {
      if (dispose) rig.controller.dispose();
      rig.devices.dispose();
    });
    return rig;
  }

  testWidgets('selecting B after testing A resets the snapshot and draft', (
    tester,
  ) async {
    const otherHost = '192.168.1.51';
    final b = FakeSetupDevice(mac: 'aabbccddeeff', width: 16, height: 8);
    (b.cfg['if'] as Map)['live']['rlm'] = false;
    final rig = await SetupRig.create(
      tester,
      entry: SetupEntry.newDevice,
      device: FakeSetupDevice(width: 8, height: 8, ledCount: 32),
      otherDevices: {otherHost: b},
    );
    final c = rig.controller;
    await c.connectFound(const DiscoveredDevice(host: deviceHost, name: 'A'));
    await settle(tester);
    if (c.step == SetupStep.look) {
      c.lookDoesNotMatch();
      await settle(tester);
    }
    c.setSize(8, 8);
    c.sizeNext();
    await settle(tester);
    expect(c.hasSnapshot, isTrue);
    c.setSupply(3);
    c.back();
    c.back();
    await c.connectFound(const DiscoveredDevice(host: otherHost, name: 'B'));
    await settle(tester);
    expect(c.state?.mac, b.mac);
    expect((c.draftWidth, c.draftHeight), (16, 8));
    expect(c.draftWiring, const PanelWiring());
    expect(c.supplyAmps, isNull);
    expect(c.hasSnapshot, isFalse);
    expect(c.wrote, isFalse);
    b.writes.clear();
    expect(await c.undo(), isTrue);
    expect(b.writes, isEmpty);
    await c.cleanUp();
    c.dispose();
    rig.devices.dispose();
  });

  testWidgets(
    'Close waits for pending realtime-map disable before closing clients',
    (tester) async {
      final rig = await rigFor(tester, dispose: false);
      final pending = Completer<void>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete();
      });
      var disabling = false;
      rig.device.beforeRequest = (r) async {
        if (rlmWrite(r, false)) {
          disabling = true;
          await pending.future;
        }
      };
      rig.controller.sizeNext();
      await settle(tester);
      expect(disabling, isTrue);
      final closedBefore = rig.device.clientsClosed;
      var finished = false;
      final closing = rig.controller.cleanUp().then((_) => finished = true);
      rig.controller.dispose();
      await settle(tester);
      expect(finished, isFalse);
      expect(rig.device.clientsClosed, closedBefore);
      pending.complete();
      await settle(tester);
      await closing;
      expect(rig.device.rlmValue, 1);
      expect(await rig.store.has(rig.device.mac), isFalse);
    },
  );

  testWidgets(
    'failed realtime-map restoration survives Close and is restored next run',
    (tester) async {
      final rig = await rigFor(tester);
      rig.controller.sizeNext();
      await settle(tester);
      rig.device.beforeRequest = (r) async {
        if (rlmWrite(r, true)) throw http.ClientException('lost connection');
      };
      final closing = rig.controller.cleanUp();
      await settle(tester);
      await closing;
      final snap = (await rig.store.load(rig.device.mac))!;
      expect(snap.needsRestore, isTrue);
      expect(rig.device.rlmValue, 0);
      rig.device.beforeRequest = null;
      final next = SetupController(
        devices: rig.devices,
        playback: rig.playback,
        wifi: FakeSetupWifi(),
        store: rig.store,
        entry: SetupEntry.existing,
        clientFactory: rig.device.client,
        delay: (_) async {},
      );
      next.begin();
      await settle(tester);
      expect(rig.device.rlmValue, 1);
      expect(await rig.store.has(rig.device.mac), isFalse);
      await next.cleanUp();
      next.dispose();
    },
  );

  for (final phase in ['snapshot', 'session']) {
    testWidgets('background during $phase cancels startup; resume restarts', (
      tester,
    ) async {
      final rig = await rigFor(tester);
      final pending = Completer<void>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete();
      });
      var waiting = false;
      rig.device.beforeRequest = (r) async {
        final match = phase == 'snapshot'
            ? r.method == 'GET' && r.url.path == '/json/state'
            : r.method == 'POST' && r.url.path == '/json/state';
        if (match && !waiting) {
          waiting = true;
          await pending.future;
        }
      };
      final before = rig.senders.length;
      rig.controller.sizeNext();
      await settle(tester);
      expect(waiting, isTrue);
      rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      pending.complete();
      await settle(tester);
      expect(rig.controller.testRunning, isFalse);
      expect(
        rig.senders.skip(before).every((s) => !s.isOpen && s.sent.isEmpty),
        isTrue,
      );
      expect(rig.device.rlmValue, 1);
      rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle(tester);
      expect(rig.controller.testRunning, isTrue);
      expect(rig.sender.sent, isNotEmpty);
      await rig.controller.cleanUp();
    });
  }

  testWidgets(
    'background during Look startup cannot activate it until resume',
    (tester) async {
      final device = FakeSetupDevice(width: 8, height: 8);
      final pending = Completer<void>();
      var waiting = false;
      device.beforeRequest = (r) async {
        if (r.method == 'POST' &&
            r.url.path == '/json/state' &&
            r.body.contains('"lor":0') &&
            !waiting) {
          waiting = true;
          await pending.future;
        }
      };
      final rig = await SetupRig.create(tester, device: device);
      addTearDown(() {
        if (!pending.isCompleted) pending.complete();
      });
      rig.controller.begin();
      await settle(tester);
      expect(waiting, isTrue);
      rig.controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      pending.complete();
      await settle(tester);
      expect(rig.controller.testRunning, isFalse);
      expect(rig.senders.every((s) => !s.isOpen && s.sent.isEmpty), isTrue);
      rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle(tester);
      expect(rig.controller.testRunning, isTrue);
      await rig.controller.cleanUp();
      rig.controller.dispose();
      rig.devices.dispose();
    },
  );

  testWidgets('Look reached while backgrounded starts on resume', (
    tester,
  ) async {
    final device = FakeSetupDevice(width: 8, height: 8);
    final rig = await SetupRig.create(tester, device: device);
    final pending = Completer<void>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete();
    });
    device.beforeRequest = (r) async {
      if (r.method == 'GET' && r.url.path == '/json/cfg') await pending.future;
    };
    rig.controller.begin();
    await settle(tester);
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    pending.complete();
    await settle(tester);
    expect(rig.controller.step, SetupStep.look);
    expect(rig.senders, isEmpty);
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle(tester);
    expect(rig.controller.testRunning, isTrue);
    await rig.controller.cleanUp();
    rig.controller.dispose();
    rig.devices.dispose();
  });

  testWidgets('Back during setLedsNow snapshot prevents all writes', (
    tester,
  ) async {
    final rig = await rigFor(tester);
    final pending = Completer<void>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete();
    });
    rig.device.beforeRequest = (r) async {
      if (r.method == 'GET' && r.url.path == '/json/state') {
        await pending.future;
      }
    };
    rig.device.writes.clear();
    rig.controller.sizeNext();
    await settle(tester);
    final setting = rig.controller.setLedsNow();
    await settle(tester);
    rig.controller.back();
    rig.controller.setSize(16, 16);
    pending.complete();
    await settle(tester);
    await setting;
    expect(rig.device.writes, isEmpty);
    expect(rig.controller.wrote, isFalse);
    await rig.controller.cleanUp();
  });

  testWidgets('failed apply restores every original segment and its geometry', (
    tester,
  ) async {
    final device = FakeSetupDevice(width: 8, height: 8, ledCount: 32);
    final segments = [
      {'id': 0, 'start': 0, 'stop': 8, 'startY': 0, 'stopY': 4, 'fx': 9},
      {'id': 1, 'start': 0, 'stop': 8, 'startY': 4, 'stopY': 8, 'fx': 12},
    ];
    device.state['seg'] = segments;
    device.state['mainseg'] = 1;
    final rig = await rigFor(tester, device: device);
    final c = rig.controller;
    c.setSize(16, 16);
    c.sizeNext();
    await settle(tester);
    c.pickCorner(StartCorner.topLeft);
    c.pickRun(alongWidth: true);
    c.pickJump(farEnd: false);
    c.looksRight();
    device.ignoreLayout = true;
    await c.apply();
    expect(c.step, SetupStep.applyFailed);
    expect(c.rollbackFailed, isFalse);
    expect(device.state['seg'], segments);
    expect(device.state['mainseg'], 1);
    await c.cleanUp();
  });

  testWidgets(
    'Wi-Fi join includes the phone timezone in the credentials write',
    (tester) async {
      final previous = phoneZoneReader;
      phoneZoneReader = () async =>
          (iana: 'Asia/Kolkata', offset: const Duration(hours: 5, minutes: 30));
      addTearDown(() => phoneZoneReader = previous);
      final rig = await SetupRig.create(tester, entry: SetupEntry.newDevice);
      final c = rig.controller;
      c.chooseNew();
      await c.connectAssisted();
      await settle(tester);
      c.pickOther();
      c.setOtherSsid('Home');
      c.setPassword('pw');
      final joining = c.joinNetwork();
      await settle(tester);
      expect((rig.ap.writes.first.$2 as Map)['if'], {
        'ntp': {'en': true, 'tz': 14, 'offset': 0},
      });
      c.back();
      await joining;
      await c.cleanUp();
      c.dispose();
      rig.devices.dispose();
    },
  );
}
