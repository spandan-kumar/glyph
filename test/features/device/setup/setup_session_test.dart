import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/features/device/setup/setup_session.dart';
import 'package:glyph/wled/ddp.dart';
import 'package:glyph/wled/ddp_group.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/wled/layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_setup_device.dart';

class FakeSender extends DdpSender {
  FakeSender(super.host, {this.failOpen = false});
  final bool failOpen;
  final sent = <Uint8List>[];
  bool opened = false, closed = false;

  @override
  bool get isOpen => opened && !closed;

  @override
  Future<void> open() async {
    if (failOpen) throw StateError('no socket');
    opened = true;
  }

  @override
  void send(Uint8List rgb) => sent.add(Uint8List.fromList(rgb));

  @override
  void close() => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const host = '127.0.0.1';
  late FakeSetupDevice device;
  late DeviceStore devices;
  late PlaybackController playback;
  late FakeSender sender;

  SetupSession session(WidgetTester tester, {bool failOpen = false}) => SetupSession(
        playback: playback,
        devices: devices,
        host: host,
        client: device.client(host),
        senderFactory: (h) => sender = FakeSender(h, failOpen: failOpen),
        observeLifecycle: false,
      );

  setUp(() {
    device = FakeSetupDevice();
    playback = PlaybackController();
  });

  Future<void> boot(WidgetTester tester) => tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({
          'devices.v1': jsonEncode([
            const SavedDevice(host: host, name: 'Desk', layout: MatrixLayout(flipX: true)).toJson(),
          ]),
          'devices.selected': host,
        });
        devices = DeviceStore(clientFactory: device.client);
        await devices.load();
      });

  testWidgets('start takes over, resends every 100 ms; end gives everything back', (tester) async {
    await boot(tester);
    playback.playGenerator(generators.first);
    final s = session(tester);
    await tester.runAsync(() async {
      await playback.startStreamingTo([const DdpTarget(host)]);
    });
    expect(playback.isPlaying, isTrue);
    expect(playback.isStreaming, isTrue);

    await tester.runAsync(s.start);
    expect(s.isActive, isTrue);
    expect(playback.isPlaying, isFalse);
    expect(playback.isStreaming, isFalse);
    expect(playback.alertsBlocked, isTrue);
    expect(sender.opened, isTrue);
    expect(device.writes.any((w) => w.$2 is Map && (w.$2 as Map)['lor'] == 0), isTrue);

    s.showRaw(Uint8List.fromList([1, 2, 3]));
    expect(sender.sent, hasLength(1), reason: 'sent at once');
    await tester.pump(const Duration(milliseconds: 350));
    expect(sender.sent.length, 4, reason: 'then every 100 ms');
    expect(sender.sent.last, [1, 2, 3]);

    s.showRaw(Uint8List.fromList([9, 9, 9]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(sender.sent.last, [9, 9, 9]);

    await tester.runAsync(() => s.end());
    expect(sender.closed, isTrue);
    expect(s.isActive, isFalse);
    final count = sender.sent.length;
    await tester.pump(const Duration(milliseconds: 500));
    expect(sender.sent.length, count, reason: 'nothing after end');
    expect(device.writes.last.$2, {'live': false});
    expect(playback.alertsBlocked, isFalse);
    expect(playback.isPlaying, isTrue);
    expect(playback.isStreaming, isTrue);
    expect(playback.targets.single.host, host);
    expect(playback.targets.single.layout, const MatrixLayout(flipX: true),
        reason: 'streaming resumes with the device\'s current app layout');

    playback.pause();
    await tester.runAsync(playback.stopStreaming);
    playback.dispose();
    devices.dispose();
  });

  testWidgets('end applies a layout changed during setup and a new size', (tester) async {
    await boot(tester);
    playback.playGenerator(generators.first);
    final s = session(tester);
    await tester.runAsync(() async {
      await playback.startStreamingTo([const DdpTarget(host)]);
      await s.start();
      await devices.updateLayout(const MatrixLayout(rotation: 2));
      await s.end(width: 8, height: 8);
    });
    expect(playback.targets.single.layout, const MatrixLayout(rotation: 2));
    expect(playback.frame.width, 8);
    playback.pause();
    await tester.runAsync(playback.stopStreaming);
    playback.dispose();
    devices.dispose();
  });

  testWidgets('nothing playing before means nothing resumed after', (tester) async {
    await boot(tester);
    final s = session(tester);
    await tester.runAsync(s.start);
    s.showRaw(Uint8List(3));
    await tester.runAsync(() => s.end());
    expect(playback.isPlaying, isFalse);
    expect(playback.isStreaming, isFalse);
    expect(playback.alertsBlocked, isFalse);
    playback.dispose();
    devices.dispose();
  });

  testWidgets('backgrounding stops sending; coming back resumes', (tester) async {
    await boot(tester);
    final s = session(tester);
    await tester.runAsync(s.start);
    s.showRaw(Uint8List.fromList([5, 5, 5]));
    await tester.pump(const Duration(milliseconds: 200));
    final before = sender.sent.length;
    s.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(s.isSending, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(sender.sent.length, before);
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(sender.sent.length, before + 1, reason: 'pushes the buffer straight away');
    await tester.pump(const Duration(milliseconds: 200));
    expect(sender.sent.length, before + 3);
    await tester.runAsync(() => s.end());
    playback.dispose();
    devices.dispose();
  });

  testWidgets('showFrame matches the device colour handling and never sends before start', (tester) async {
    await boot(tester);
    final s = session(tester);
    s.showRaw(Uint8List(3)); // not started: ignored
    await tester.runAsync(s.start);
    final f = Frame(2, 1)..fill(0xFFFFFF);
    s.showFrame(f);
    expect(sender.sent.single.length, 6);
    expect(sender.sent.single.any((v) => v > 0), isTrue);
    s.showBlack(4);
    expect(sender.sent.last, Uint8List(12));
    await tester.runAsync(() => s.end());
    playback.dispose();
    devices.dispose();
  });

  testWidgets('a socket that will not open restores playback and throws', (tester) async {
    await boot(tester);
    playback.playGenerator(generators.first);
    final s = session(tester, failOpen: true);
    Object? error;
    await tester.runAsync(() async {
      try {
        await s.start();
      } catch (e) {
        error = e;
      }
    });
    expect(error, isA<StateError>());
    expect(playback.isPlaying, isTrue);
    expect(playback.alertsBlocked, isFalse);
    expect(s.isActive, isFalse);
    playback.pause();
    playback.dispose();
    devices.dispose();
  });

  testWidgets('end is safe to repeat', (tester) async {
    await boot(tester);
    final s = session(tester);
    await tester.runAsync(s.start);
    await tester.runAsync(() => s.end());
    await tester.runAsync(() => s.end());
    expect(device.writes.where((w) => w.$2 is Map && (w.$2 as Map)['live'] == false), hasLength(1));
    playback.dispose();
    devices.dispose();
  });

  for (final (label, on, bri) in [('off', false, 128), ('very dim', true, 10)]) {
    testWidgets('a device that is $label is lit for the test and put back after', (tester) async {
      await boot(tester);
      device.state['on'] = on;
      device.state['bri'] = bri;
      final s = session(tester);
      await tester.runAsync(s.start);
      expect(device.state['on'], isTrue);
      expect(device.state['bri'], 64);
      await tester.runAsync(() => s.end());
      expect(device.state['on'], on);
      expect(device.state['bri'], bri);
      playback.dispose();
      devices.dispose();
    });
  }

  testWidgets('a bright device is left alone', (tester) async {
    await boot(tester);
    final s = session(tester);
    await tester.runAsync(s.start);
    await tester.runAsync(() => s.end());
    expect(device.writes.where((w) => w.$2 is Map && (w.$2 as Map).containsKey('bri')), isEmpty);
    playback.dispose();
    devices.dispose();
  });
}
