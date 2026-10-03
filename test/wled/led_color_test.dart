import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/led_gamma.dart';
import 'package:glyph/wled/ddp.dart';
import 'package:glyph/wled/ddp_group.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// cfg of the real 16x16 panel (WLED 16.0.1), trimmed to what matters.
Map<String, dynamic> _cfg({Object col = 2.2, Object val = 2.2, Object? noGc = true}) => {
      'light': {
        'gc': {'bri': 1, 'col': col, 'val': val},
      },
      'if': {
        'live': {'en': true, 'timeout': 25, 'no-gc': ?noGc},
      },
    };

/// The first DDP frame (payloads joined up to the push packet).
Future<Uint8List> _receiveOne(RawDatagramSocket socket) async {
  final pending = <int>[];
  await for (final e in socket) {
    if (e != RawSocketEvent.read) continue;
    final d = socket.receive();
    if (d == null) continue;
    pending.addAll(d.data.sublist(ddpHeaderLength));
    if (d.data[0] & 0x01 == 1) break;
  }
  return Uint8List.fromList(pending);
}

Future<Uint8List> _stream(Frame f, {LedColorConfig? color}) async {
  final rx = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final got = _receiveOne(rx).timeout(const Duration(seconds: 2));
  final g = DdpGroupSender([DdpTarget('127.0.0.1', port: rx.port, color: color)]);
  await g.open();
  g.send(f);
  final bytes = await got;
  g.close();
  rx.close();
  return bytes;
}

/// App red, the old #0E0E0E background, a palette dark end, 31 and 32 grey.
Frame _swatch() => Frame(6, 1)
  ..set(0, 0, 0xE8283C)
  ..set(1, 0, 0x0E0E0E)
  ..set(2, 0, 0x1A0033)
  ..set(3, 0, 0x1F1F1F)
  ..set(4, 0, 0x200000)
  ..set(5, 0, 0xFFFFFF);

void main() {
  tearDown(knownLedColor.clear);

  group('LedColorConfig.fromConfig (cfg.cpp deserializeConfig)', () {
    test('the panel: gamma 2.2 on colours, none on realtime', () {
      final c = LedColorConfig.fromConfig(_cfg());
      expect(c.gamma, 2.2);
      expect(c.gammaOnLive, isFalse);
      expect(c.streamCorrection().applyGamma, isTrue);
    });

    test('no-gc off: WLED corrects live data itself', () {
      final c = LedColorConfig.fromConfig(_cfg(noGc: false));
      expect(c.gammaOnLive, isTrue);
      expect(c.streamCorrection().applyGamma, isFalse);
    });

    test('colour gamma switched off or out of range means none', () {
      expect(LedColorConfig.fromConfig(_cfg(col: 1, noGc: false)), const LedColorConfig(gamma: 1));
      expect(LedColorConfig.fromConfig(_cfg(col: 5, val: 5)).gamma, 1);
      expect(LedColorConfig.fromConfig(_cfg(col: 2.8, val: 2.8)).gamma, 2.8);
    });

    test('missing keys fall back to WLED defaults', () {
      expect(LedColorConfig.fromConfig(const {}), LedColorConfig.unknown);
      expect(LedColorConfig.fromConfig(_cfg(noGc: null)).gammaOnLive, isFalse);
    });
  });

  test('WledClient.ledColorConfig reads /json/cfg; null when unreadable', () async {
    var status = 200;
    final c = WledClient('192.168.29.6', client: MockClient((r) async {
      expect(r.url.path, '/json/cfg');
      return http.Response(jsonEncode(_cfg()), status);
    }));
    expect(await c.ledColorConfig(), const LedColorConfig(gamma: 2.2));
    status = 401;
    expect(await c.ledColorConfig(), isNull);
  });

  group('DDP bytes', () {
    test('gamma applied and near-black off when the device skips live gamma (no-gc)', () async {
      final bytes = await _stream(_swatch(), color: LedColorConfig.fromConfig(_cfg()));
      expect(bytes, [
        207, 3, 11, // #E8283C: G and B nearly off, no longer pink
        0, 0, 0, // #0E0E0E: off
        2, 0, 7, // #1A0033: a real (dim) colour, kept
        0, 0, 0, // 31 → level 2: off
        3, 0, 0, // 32 → level 3: lit
        255, 204, 255, // white: WS2812 green x0.8
      ]);
    });

    test('no gamma when the device corrects live data; floor and balance still apply', () async {
      final bytes = await _stream(_swatch(), color: const LedColorConfig(gammaOnLive: true));
      expect(bytes, [
        0xE8, 36, 0x3C, // green x0.8^(1/2.2) before the device's gamma
        0, 0, 0,
        0x1A, 0x00, 0x33,
        0, 0, 0,
        0x20, 0, 0,
        255, 230, 255,
      ]);
      const plain = LedColorConfig(gammaOnLive: true, balance: neutralWhiteBalance);
      expect(await _stream(Frame(1, 1)..set(0, 0, 0xE8283C), color: plain), [0xE8, 0x28, 0x3C]);
    });

    test('a target without a config uses the one read from its host, else 2.2', () async {
      final f = Frame(1, 1)..set(0, 0, 0xE8283C);
      expect(await _stream(f), [207, 3, 11], reason: 'unknown: WLED defaults');
      knownLedColor['127.0.0.1'] = const LedColorConfig(gammaOnLive: true);
      expect(await _stream(f), [0xE8, 36, 0x3C]);
    });

    test('the rendered frame itself is not modified', () async {
      final f = _swatch();
      final before = Uint8List.fromList(f.rgb);
      await _stream(f);
      expect(f.rgb, before);
    });
  });
}
