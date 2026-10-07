import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/led_gamma.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/wled/ddp.dart';
import 'package:glyph/wled/ddp_group.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/wled/layout.dart';

/// Collects DDP frames (joined payloads up to each push packet).
class _Receiver {
  _Receiver._(this.socket) {
    socket.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = socket.receive();
      if (d == null) return;
      _pending.addAll(d.data.sublist(ddpHeaderLength));
      if (d.data[0] & 0x01 == 1) {
        frames.add(Uint8List.fromList(_pending));
        _pending.clear();
      }
    });
  }

  static Future<_Receiver> bind({InternetAddress? address}) async =>
      _Receiver._(await RawDatagramSocket.bind(address ?? InternetAddress.loopbackIPv4, 0));

  final RawDatagramSocket socket;
  final frames = <Uint8List>[];
  final _pending = <int>[];

  int get port => socket.port;

  Future<void> waitFor(int n) async {
    for (var i = 0; i < 200 && frames.length < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void close() => socket.close();
}

/// Paints pixel (x, y) with colour (x, y, 7).
class _Coords extends Generator {
  @override
  String get id => '_coords';
  @override
  String get name => 'Coords';
  @override
  EffectInstance create(int width, int height, int seed) => _CoordsFx();
}

class _CoordsFx extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        out.set(x, y, rgb(x, y, 7));
      }
    }
  }
}

Frame _coordsFrame(int w, int h) {
  final f = Frame(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      f.set(x, y, rgb(x, y, 7));
    }
  }
  return f;
}

void main() {
  test('temporary logo goes only to selected host, mirrors retain base pixels', () async {
    final a = await _Receiver.bind(), b = await _Receiver.bind(address: InternetAddress.loopbackIPv6);
    const raw = LedColorConfig(gamma: 1, balance: neutralWhiteBalance);
    final group = DdpGroupSender([
      DdpTarget('127.0.0.1', port: a.port, color: raw),
      DdpTarget('::1', port: b.port, color: raw),
    ]);
    addTearDown(() { group.close(); a.close(); b.close(); });
    await group.open();
    group.send(Frame(2, 2)..fill(0xff0000), overrideFrame: Frame(2, 2)..fill(0x00ff00), overrideHost: '127.0.0.1');
    await a.waitFor(1); await b.waitFor(1);
    expect(a.frames.single, [for (var i = 0; i < 4; i++) ...[0, 255, 0]]);
    expect(b.frames.single, [for (var i = 0; i < 4; i++) ...[255, 0, 0]]);
  });

  test('nearest scaling duplicates on 2x and samples centres on downscale', () {
    final src = _coordsFrame(4, 4);
    final up = scaleFrameNearest(src, 8, 8);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        expect(up.get(x, y), src.get(x ~/ 2, y ~/ 2));
      }
    }
    final down = scaleFrameNearest(_coordsFrame(16, 16), 8, 4);
    expect(down.get(0, 0), rgb(1, 2, 7));
    expect(down.get(7, 3), rgb(15, 14, 7));
    final strip = scaleFrameNearest(src, 6, 1);
    expect(strip.height, 1);
    expect(strip.get(0, 0), src.get(0, 2));
  });

  test('group sends each target its own size and layout; dedupes hosts', () async {
    final a = await _Receiver.bind(), b = await _Receiver.bind(), c = await _Receiver.bind();
    // Gamma 1, no white balance: geometry only (colour correction is
    // covered in led_color_test.dart); the blue 7s clear the black floor.
    const raw = LedColorConfig(gamma: 1, balance: neutralWhiteBalance);
    final group = DdpGroupSender([
      DdpTarget('127.0.0.1', port: a.port, color: raw),
      DdpTarget(
        '127.0.0.1',
        port: b.port,
        width: 32,
        height: 32,
        layout: const MatrixLayout(flipX: true),
        color: raw,
      ),
      DdpTarget('127.0.0.1', port: c.port, width: 8, height: 8, color: raw),
      // Same host and port as the primary: dropped.
      DdpTarget('127.0.0.1', port: a.port, width: 4, height: 4),
    ]);
    expect(group.targets, hasLength(3));
    await group.open();
    expect(group.activeHosts, hasLength(3));
    final f = _coordsFrame(16, 16);
    group.send(f);
    group.send(f);
    await Future.wait([a.waitFor(2), b.waitFor(2), c.waitFor(2)]);
    expect(group.framesSent, 2);
    expect(group.errors, 0);
    group.close();
    for (final r in [a, b, c]) {
      r.close();
    }

    expect(a.frames.first, f.rgb);
    final big = b.frames.first;
    expect(big.length, 32 * 32 * 3);
    // flipX: logical (0,0) → LED (31,0); logical (0,0) is source (0,0).
    expect(big.sublist(31 * 3, 31 * 3 + 3), [0, 0, 7]);
    expect(big.sublist(0, 3), [15, 0, 7]);
    final small = c.frames.first;
    expect(small.length, 8 * 8 * 3);
    expect(small.sublist(0, 3), [1, 1, 7]);
  });

  test('unreachable secondary is skipped; unreachable primary throws', () async {
    final a = await _Receiver.bind();
    final ok = DdpGroupSender([
      DdpTarget('127.0.0.1', port: a.port),
      const DdpTarget('not a valid host!', width: 8, height: 8),
    ]);
    await ok.open();
    expect(ok.activeHosts, ['127.0.0.1']);
    expect(ok.failedHosts, ['not a valid host!']);
    ok.close();
    a.close();

    final bad = DdpGroupSender([const DdpTarget('not a valid host!')]);
    await expectLater(bad.open(), throwsA(anything));
    expect(bad.isOpen, isFalse);
  });

  test('PlaybackController streams to a group and keeps the old API', () async {
    final a = await _Receiver.bind(), b = await _Receiver.bind();
    final p = PlaybackController(width: 16, height: 16);
    addTearDown(() {
      p.pause();
      p.dispose();
      a.close();
      b.close();
    });
    p.playGenerator(_Coords());

    await p.startStreamingTo([
      DdpTarget('127.0.0.1', port: a.port),
      DdpTarget('127.0.0.1', port: b.port, width: 8, height: 8),
    ]);
    expect(p.isStreaming, isTrue);
    expect(p.streamingHosts, ['127.0.0.1', '127.0.0.1']);
    await Future.wait([a.waitFor(3), b.waitFor(3)]);
    expect(a.frames.last.length, 16 * 16 * 3);
    expect(b.frames.last.length, 8 * 8 * 3);
    expect(p.framesSent, greaterThanOrEqualTo(3));

    // Old single-target API on the default DDP port; mirrors ride along.
    await p.setMirrors([DdpTarget('127.0.0.1', port: b.port, width: 4, height: 4)]);
    expect(p.isStreaming, isTrue, reason: 'setMirrors reopened the group');
    expect(p.targets.last.width, 4);
    await p.stopStreaming();
    expect(p.isStreaming, isFalse);
    expect(p.framesSent, 0);

    b.frames.clear();
    await p.startStreaming('127.0.0.1', MatrixLayout.identity);
    expect(p.targets.map((t) => t.port), [ddpPort, b.port]);
    await b.waitFor(2);
    expect(b.frames.last.length, 4 * 4 * 3);

    await p.setMirrors(const []);
    expect(p.targets, hasLength(1));
    await p.stopStreaming();
  });

  test('a held stream (device switched off) sends nothing until released', () async {
    final a = await _Receiver.bind();
    final p = PlaybackController(width: 16, height: 16);
    addTearDown(() {
      p.pause();
      p.dispose();
      a.close();
    });
    p.playGenerator(_Coords());
    await p.startStreamingTo([DdpTarget('127.0.0.1', port: a.port)]);
    await a.waitFor(2);

    p.streamHeld = true;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final heldAt = a.frames.length;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(a.frames.length, heldAt, reason: 'nothing reaches an off device');
    expect(p.isStreaming, isTrue, reason: 'the stream stays open, ready to resume');
    expect(p.isPlaying, isTrue, reason: 'the phone keeps rendering');

    p.streamHeld = false;
    await a.waitFor(heldAt + 3);
    expect(a.frames.length, greaterThan(heldAt));
    await p.stopStreaming();
  });
}
