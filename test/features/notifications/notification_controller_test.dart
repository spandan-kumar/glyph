import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/background.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/notifications/notification_controller.dart';
import 'package:glyph/features/notifications/notification_logo.dart';
import 'package:glyph/features/notifications/notification_service.dart';
import 'package:glyph/wled/ddp_group.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device/fake_wled.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeWled fake;
  late DeviceStore devices;
  late PlaybackController playback;
  late NotificationController controller;
  late NotificationService service;
  late StreamController<Object?> bridge;
  late List<List<String>> configurations;
  late DateTime clock;
  late bool access, connected;
  late int retains, releases;
  late Set<Object> owners;
  Completer<void>? emptyConfiguration;

  Future<void> flush([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));
  void post(String package, String key, {DateTime? at}) => bridge.add({
    'package': package,
    'key': key,
    'time': (at ?? clock).millisecondsSinceEpoch,
    'icon': Uint8List(3072)..fillRange(0, 3072, 200),
    'title': 'This must never be used',
    'body': 'Neither must this',
  });
  Future<void> start() async {
    await controller.setApp('chat', true);
    await controller.setMonitoring(true);
    expect(controller.monitoring, isTrue);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fake = FakeWled();
    devices = DeviceStore(clientFactory: fake.client);
    playback = PlaybackController();
    bridge = StreamController<Object?>.broadcast(sync: true);
    configurations = [];
    access = connected = true;
    retains = releases = 0;
    owners = {};
    emptyConfiguration = null;
    clock = DateTime(2026, 10, 7, 12);
    service = NotificationService(
      supported: true,
      events: () => bridge.stream,
      invoke: (method, args) async {
        switch (method) {
          case 'status':
            return {'access': access, 'connected': connected};
          case 'configure':
            final selected = (args as List).cast<String>();
            configurations.add(selected);
            if (selected.isEmpty) await emptyConfiguration?.future;
            return {'access': access, 'connected': connected};
          case 'icon':
            return Uint8List(3072)..fillRange(0, 3072, 180);
        }
        return null;
      },
    );
    controller = NotificationController(
      devices: devices,
      playback: playback,
      service: service,
      now: () => clock,
      alertDuration: const Duration(milliseconds: 180),
      retain: (owner, stop) async {
        owners.add(owner);
        retains++;
        return true;
      },
      release: (owner) async {
        owners.remove(owner);
        releases++;
      },
    );
    await devices.select(const SavedDevice(host: '127.0.0.1', name: 'Test'));
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    playback.dispose();
    devices.dispose();
    await bridge.close();
    BackgroundStreaming.debugReset();
  });

  test('defaults off, persists app choices and quiet hours but never starts on load', () async {
    expect(controller.settings.packages, isEmpty);
    expect(controller.monitoring, isFalse);
    expect(retains, 0);
    await controller.setApp('chat', true);
    await controller.setQuiet(true, start: 1200, end: 420);
    await controller.load();
    expect(controller.settings.packages, {'chat'});
    expect(controller.settings.quietStart, 1200);
    expect(controller.settings.quietEnd, 420);
    expect(controller.monitoring, isFalse);
    expect(configurations, isEmpty);
  });

  test('denied access does not start the foreground monitor', () async {
    access = false;
    await controller.setApp('chat', true);
    await controller.setMonitoring(true);
    expect(controller.monitoring, isFalse);
    expect(controller.error, contains('Allow notification access'));
    expect(retains, 0);
  });

  test('allows only selected apps; logo ends with native look restored and no idle frames', () async {
    await start();
    post('other', '1');
    await flush();
    expect(playback.isAlerting, isFalse);
    post('chat', '2');
    await flush();
    expect(playback.isAlerting, isTrue);
    expect(playback.generator, isNull);
    expect(playback.isStreaming, isFalse);
    await flush(220);
    expect(playback.isAlerting, isFalse);
    expect(playback.isPlaying, isFalse);
    expect(fake.posts.map((p) => p.$2), [
      {'lor': 0},
      {'live': false},
    ]);
    expect(fake.uploads, isEmpty);
  });

  test('overlay preserves the generator and the live stream', () async {
    final base = NotificationLogoGenerator(NotificationLogo.fallback);
    playback.playGenerator(base);
    await playback.startStreamingTo([const DdpTarget('127.0.0.1')]);
    await start();
    final revision = playback.revision, stream = playback.streamGeneration;
    post('chat', 'a');
    await flush();
    expect(playback.isAlerting, isTrue);
    expect(identical(playback.generator, base), isTrue);
    await flush(220);
    expect(playback.isAlerting, isFalse);
    expect(playback.isPlaying, isTrue);
    expect(playback.isStreaming, isTrue);
    expect(playback.revision, revision);
    expect(playback.streamGeneration, stream);
    expect(fake.posts, isEmpty);
  });

  test('queue coalesces, expires, bounds to three, and removals cancel queued alerts', () async {
    await start();
    for (final p in ['b', 'c', 'd', 'e']) {
      await controller.setApp(p, true);
    }
    post('chat', 'a');
    await flush();
    post('chat', 'update');
    post('b', 'b');
    post('b', 'b2');
    expect(controller.queued, 1);
    post('c', 'c');
    post('d', 'd');
    post('e', 'e');
    expect(controller.queued, 3);
    bridge.add({'removed': 'c'});
    expect(controller.queued, 2);
    clock = clock.add(const Duration(seconds: 31));
    await flush(220);
    expect(controller.queued, 0);
    expect(playback.isAlerting, isFalse);
    expect(fake.posts.where((p) => p.$2.containsKey('lor')), hasLength(1));
  });

  test('quiet hours, interactive tools and Send discard events', () async {
    await start();
    await controller.setQuiet(true, start: 660, end: 780);
    post('chat', 'quiet');
    await flush();
    expect(playback.isAlerting, isFalse);
    await controller.setQuiet(false);
    final owner = Object();
    playback.blockAlerts(owner);
    post('chat', 'blocked');
    await flush();
    expect(controller.queued, 0);
    playback.unblockAlerts(owner);
    await flush();
    expect(playback.isAlerting, isFalse);
    post('chat', 'okay');
    await flush();
    expect(playback.isAlerting, isTrue);
  });

  test(
    'pause cancels alert and queue, and still leaves live mode on the same device',
    () async {
      await start();
      await controller.setApp('b', true);
      post('chat', 'a');
      await flush();
      post('b', 'b');
      playback.pause();
      await flush(220);
      expect(playback.isAlerting, isFalse);
      expect(controller.queued, 0);
      expect(fake.posts.last.$2, {'live': false});
    },
  );

  test('device switch during prepare cannot draw on either device or restore old state', () async {
    await start();
    final gate = Completer<void>();
    fake.beforeRequest = (r) async {
      if (r.method == 'POST') await gate.future;
    };
    post('chat', 'a');
    await flush();
    await devices.select(const SavedDevice(host: '127.0.0.2', name: 'Other'));
    gate.complete();
    await flush();
    expect(playback.isAlerting, isFalse);
    expect(fake.posts.any((p) => p.$2.containsKey('live')), isFalse);
  });

  test('power off cancels alert and pending logos', () async {
    await start();
    await controller.setApp('b', true);
    post('chat', 'a');
    await flush();
    post('b', 'b');
    await devices.setPower(false);
    await flush(220);
    expect(playback.isAlerting, isFalse);
    expect(controller.queued, 0);
    expect(fake.posts.any((p) => p.$2.containsKey('live')), isFalse);
  });

  test(
    'listener disconnect clears queue; revocation disables native collection',
    () async {
      await start();
      await controller.setApp('b', true);
      post('chat', 'a');
      await flush();
      post('b', 'b');
      bridge.add({'connected': false});
      expect(playback.isAlerting, isFalse);
      expect(controller.queued, 0);
      access = false;
      bridge.add({'access': false});
      await flush();
      expect(controller.monitoring, isFalse);
      expect(configurations.last, isEmpty);
    },
  );

  test('preview does not enable monitoring or change selected apps', () async {
    await controller.preview('chat');
    expect(playback.isAlerting, isTrue);
    expect(controller.monitoring, isFalse);
    expect(controller.settings.packages, isEmpty);
    expect(configurations, isEmpty);
    expect(retains, 0);
    await flush(220);
    expect(playback.isAlerting, isFalse);
  });

  test(
    'stopping monitoring clears native allowlist and restores the native look',
    () async {
      await start();
      post('chat', 'a');
      await flush();
      await controller.setMonitoring(false);
      await flush();
      expect(playback.isAlerting, isFalse);
      expect(configurations.last, isEmpty);
      expect(releases, 1);
      expect(fake.posts.last.$2, {'live': false});
    },
  );

  test('native realtime override is restored without rewriting the saved look or Show', () async {
    fake.state['lor'] = 2;
    await start();
    post('chat', 'a');
    await flush(230);
    expect(fake.posts.last.$2, {'live': false, 'lor': 2});
    expect(
      fake.posts.any(
        (p) =>
            p.$2.containsKey('ps') ||
            p.$2.containsKey('seg') ||
            p.$2.containsKey('playlist'),
      ),
      isFalse,
    );
  });

  test('rapid off/on cannot release the new monitoring session', () async {
    await start();
    final gate = emptyConfiguration = Completer<void>();
    final off = controller.setMonitoring(false);
    await flush();
    final on = controller.setMonitoring(true);
    await flush();
    gate.complete();
    await off;
    await on;
    expect(controller.monitoring, isTrue);
    expect(owners, hasLength(1));
    expect(configurations.last, ['chat']);
  });

  test(
    'last app disabled stops monitoring and releases its foreground owner',
    () async {
      await start();
      await controller.setApp('chat', false);
      expect(controller.monitoring, isFalse);
      expect(configurations.last, isEmpty);
      expect(releases, 1);
    },
  );

  test('foreign live source or an off device is never hijacked', () async {
    await start();
    fake.state['live'] = true;
    post('chat', 'a');
    await flush();
    expect(playback.isAlerting, isFalse);
    expect(fake.posts, isEmpty);
    fake.state['live'] = false;
    fake.state['on'] = false;
    post('chat', 'b');
    await flush();
    expect(playback.isAlerting, isFalse);
    expect(fake.posts, isEmpty);
  });

  test('lor is restored when the alert is abandoned after prepare', () async {
    fake.state['lor'] = 2;
    await start();
    final owner = Object();
    fake.beforeRequest = (r) async {
      if (r.method == 'POST' && !playback.alertsBlocked) {
        playback.blockAlerts(owner); // user tool starts while lor is changed
      }
    };
    post('chat', 'a');
    await flush();
    fake.beforeRequest = null;
    expect(fake.posts.map((p) => p.$2).first, {'lor': 0});
    expect(fake.posts.map((p) => p.$2).last['lor'], 2);
    expect(playback.isAlerting, isFalse);
  });

  test('lor 1 is not rewritten after an alert; WLED clears it itself', () async {
    fake.state['lor'] = 1;
    await start();
    post('chat', 'a');
    await flush(230);
    expect(fake.posts.last.$2, {'live': false});
  });

  test('a user command on the same device still leaves live mode', () async {
    await start();
    post('chat', 'a');
    await flush();
    expect(playback.isAlerting, isTrue);
    playback.pause(); // bumps revision like any user command
    await flush();
    expect(playback.isAlerting, isFalse);
    expect(fake.posts.last.$2, {'live': false});
  });

  test('resume during an alert keeps playback running afterwards', () async {
    playback.playGenerator(NotificationLogoGenerator(NotificationLogo.fallback));
    playback.pause();
    await start();
    post('chat', 'a');
    await flush();
    expect(playback.isAlerting, isTrue);
    playback.resume();
    await flush(220);
    expect(playback.isAlerting, isFalse);
    expect(playback.isPlaying, isTrue);
    playback.pause();
  });

  test('stale notifications and future timestamps never play', () async {
    await start();
    post('chat', 'old', at: clock.subtract(const Duration(seconds: 30)));
    post('chat', 'future', at: clock.add(const Duration(seconds: 1)));
    await flush();
    expect(playback.isAlerting, isFalse);
    expect(fake.posts, isEmpty);
  });
}
