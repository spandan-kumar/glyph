import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/background.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/glance/glance_model.dart';
import 'package:glyph/features/glance/glance_generator.dart';
import 'package:glyph/features/glance/glance_session.dart';
import 'package:glyph/features/notifications/notification_logo.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/wled/ddp_group.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device/fake_wled.dart';
import 'glance_generator_test.dart' show Solid;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_foreground_task/methods');
  late FakeWled fake;
  late DeviceStore devices;
  late PlaybackController playback;
  late GlanceSession session;
  late bool running;
  bool rejectStart = false;
  Completer<void>? serviceGate;
  late Directory dir;
  Future<void> flush() => Future.delayed(const Duration(milliseconds: 20));
  GlanceCard card() => GlanceCard(
    id: 'c',
    title: 'Trip',
    kind: GlanceKind.counter,
    date: DateTime(2026, 10, 9),
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BackgroundStreaming.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('glyph/power'), (_) async => null);
    fake = FakeWled();
    devices = DeviceStore(clientFactory: fake.client);
    playback = PlaybackController();
    dir = Directory.systemTemp.createTempSync('glyph_glance');
    running = false;
    rejectStart = false;
    serviceGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isRunningService':
              return running;
            case 'startService':
              await serviceGate?.future;
              if (rejectStart) throw PlatformException(code: 'denied');
              running = true;
              return null;
            case 'stopService':
              running = false;
              return null;
            case 'checkNotificationPermission':
              return 0;
          }
          return null;
        });
    session = GlanceSession(
      devices: devices,
      playback: playback,
      catalog: Catalog(items: []),
      creations: CreationsStore(directory: () async => dir),
    );
    await session.load();
    await devices.select(const SavedDevice(host: '127.0.0.1', name: 'Test'));
  });
  tearDown(() async {
    session.dispose();
    playback.dispose();
    devices.dispose();
    await flush();
    BackgroundStreaming.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });
  test('load never starts playback; foreground card stops on app background and exits live only', () async {
    expect(session.playing, false);
    expect(session.background, false);
    expect(session.weather.isWatching, false);
    expect(await session.start(session.cardGenerator(card())), true);
    expect(playback.isStreaming, true);
    session.didChangeAppLifecycleState(AppLifecycleState.paused);
    await flush();
    expect(playback.isStreaming, false);
    expect(playback.isPlaying, false);
    expect(fake.posts.last.$2, {'live': false});
    expect(fake.uploads, isEmpty);
  });
  test('background ownership coexists with notification monitoring and ends on replacement', () async {
    final monitor = Object();
    await BackgroundStreaming.retain(monitor, () {});
    await session.start(session.cardGenerator(card()));
    expect(await session.setBackground(true), true);
    session.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(playback.isPlaying, true);
    playback.playGenerator(
      NotificationLogoGenerator(NotificationLogo.fallback),
    );
    await flush();
    expect(session.background, false);
    expect(session.ownsPlayback, false);
    expect(running, true);
    await BackgroundStreaming.release(monitor);
    expect(running, false);
  });
  test('switching devices stops previous stream without sending cleanup to the new device', () async {
    await session.start(session.cardGenerator(card()));
    fake.posts.clear();
    await devices.select(const SavedDevice(host: '127.0.0.2', name: 'Other'));
    await flush();
    expect(playback.isPlaying, false);
    expect(playback.isStreaming, false);
    expect(fake.posts, isEmpty);
  });
  test(
    'network loss stops playback and does not resume automatically',
    () async {
      await session.start(session.cardGenerator(card()));
      fake.offline = true;
      await devices.refresh();
      await flush();
      expect(session.playing, false);
      expect(playback.isStreaming, false);
      fake.offline = false;
      await devices.refresh();
      expect(playback.isPlaying, false);
    },
  );
  test('pending prepare cannot replace newer manual playback', () async {
    final gate = Completer<void>(), entered = Completer<void>();
    fake.beforeRequest = (r) async {
      if (r.method == 'POST') {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
      }
    };
    final starting = session.start(session.cardGenerator(card()));
    await entered.future;
    final manual = NotificationLogoGenerator(NotificationLogo.fallback);
    playback.playGenerator(manual);
    gate.complete();
    expect(await starting, false);
    expect(playback.generator, same(manual));
    expect(playback.isStreaming, false);
  });
  test(
    'Show instance and timing pause during an alert and resume after it',
    () async {
      final look = Solid(0xff0000);
      final show = PhoneShow(
        id: 's',
        title: 's',
        entries: [const PhoneShowEntry(ShowEntryKind.card, 'c', seconds: 3)],
      );
      // Exercise the real PlaybackController timer and loopback stream.
      final g = PhoneShowGenerator(show, (_) => ShowLook(look));
      playback.playGenerator(g);
      await playback.startStreamingTo([const DdpTarget('127.0.0.1')]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        await playback.beginAlert(
          NotificationLogoGenerator(NotificationLogo.fallback),
          const DdpTarget('127.0.0.1'),
          width: 16,
          height: 16,
        ),
        true,
      );
      final calls = look.times.length, creates = look.creates;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(look.times.length, calls);
      playback.endAlert();
      await Future<void>.delayed(
        Duration(milliseconds: 1000 ~/ g.streamFps + 20),
      );
      expect(look.times.length, greaterThan(calls));
      expect(look.creates, creates);
    },
  );
  test(
    'denied background start after hiding the app stops live playback',
    () async {
      await session.start(session.cardGenerator(card()));
      rejectStart = true;
      serviceGate = Completer<void>();
      final starting = session.setBackground(true);
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(playback.isPlaying, true);
      serviceGate!.complete();
      expect(await starting, false);
      expect(playback.isPlaying, false);
      expect(playback.isStreaming, false);
      expect(session.background, false);
    },
  );
}
