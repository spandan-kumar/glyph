import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/panel_setup.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> entry() => {
      'start': 0, 'len': 128, 'pin': [16], 'order': 1, 'rev': false, 'skip': 0,
      'type': 22, 'ref': false, 'rgbwm': 255, 'freq': 0, 'maxpwr': 0, 'ledma': 55, 'drv': 0, 'text': '',
    };

void main() {
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handler;
  final delays = <Duration>[];

  WledClient client() => WledClient('192.168.4.1', delay: (d) async => delays.add(d), client: MockClient((r) async {
        requests.add(r);
        return handler(r);
      }));

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  setUp(() {
    requests = [];
    delays.clear();
    handler = (r) async => http.Response('{"success":true}', 200);
  });

  group('scanNetworks', () {
    test('polls until the scan finishes, dedupes by name keeping the strongest', () async {
      var calls = 0;
      handler = (r) async {
        calls++;
        if (calls < 3) return http.Response('{"networks":[]}', 200);
        return http.Response(
            jsonEncode({
              'networks': [
                {'ssid': 'Home', 'rssi': -70, 'bssid': 'aa', 'channel': 1, 'enc': 3},
                {'ssid': 'Home', 'rssi': -50, 'bssid': 'bb', 'channel': 6, 'enc': 3},
                {'ssid': '', 'rssi': -30, 'bssid': 'cc', 'channel': 6, 'enc': 3},
                {'ssid': 'Cafe', 'rssi': -80, 'bssid': 'dd', 'channel': 11, 'enc': 0},
                {'ssid': 'Neighbour', 'rssi': -60, 'bssid': 'ee', 'channel': 3, 'enc': 4},
              ]
            }),
            200);
      };
      final nets = await client().scanNetworks();
      expect(calls, 3);
      expect(delays, [const Duration(seconds: 1), const Duration(seconds: 1)]);
      expect([for (final n in nets) n.ssid], ['Home', 'Neighbour', 'Cafe']);
      expect(nets.first.rssi, -50);
      expect(nets.first.bssid, 'bb');
      expect(nets.first.secure, isTrue);
      expect(nets.last.secure, isFalse);
      expect(requests.every((r) => r.url.path == '/json/net' && r.method == 'GET'), isTrue);
    });

    test('gives an empty list when nothing shows up in time', () async {
      handler = (r) async => http.Response('{"networks":[]}', 200);
      expect(await client().scanNetworks(timeout: const Duration(seconds: 3)), isEmpty);
      expect(delays.length, 3);
    });

    test('a link that never answers is an error', () async {
      handler = (r) async => http.Response('no', 500);
      await expectLater(client().scanNetworks(timeout: const Duration(seconds: 2)),
          throwsA(isA<WledException>()));
    });

    test('a stall in the middle of the scan is tolerated', () async {
      var calls = 0;
      handler = (r) async {
        calls++;
        if (calls <= 2) return http.Response('no', 500);
        return http.Response('{"networks":[{"ssid":"Home","rssi":-40,"enc":3}]}', 200);
      };
      final nets = await client().scanNetworks();
      expect(nets.single.ssid, 'Home');
    });
  });

  test('joinWifi writes only ssid and psk, then reboots', () async {
    await client().joinWifi('Home Net', 's3cret-pass');
    expect(requests.map((r) => '${r.method} ${r.url.path}'), ['POST /json/cfg', 'POST /json/state']);
    expect(body(requests[0]), {
      'nw': {
        'ins': [
          {'ssid': 'Home Net', 'psk': 's3cret-pass'}
        ]
      }
    });
    expect(body(requests[1]), {'rb': true});
  });

  test('joinWifi ignores a dropped reboot reply but not a refused config', () async {
    handler = (r) async => r.url.path == '/json/state'
        ? throw http.ClientException('connection closed')
        : http.Response('{"success":true}', 200);
    await client().joinWifi('Home', 'pw');
    handler = (r) async => http.Response('denied', 401);
    await expectLater(client().joinWifi('Home', 'pw'), throwsA(isA<WledException>()));
  });

  test('credentials never appear in errors', () async {
    handler = (r) async => http.Response('boom', 500);
    for (final run in [
      () => client().joinWifi('Home', 'hunter2-pw'),
      () => client().unlockSettings('4321'),
    ]) {
      try {
        await run();
        fail('should throw');
      } on WledException catch (e) {
        expect('$e ${e.message} ${e.cause}', isNot(contains('hunter2-pw')));
        expect('$e ${e.message} ${e.cause}', isNot(contains('4321')));
      }
    }
  });

  group('unlockSettings', () {
    test('posts the pin to /json/state and checks with a no-op config write', () async {
      await client().unlockSettings('1234');
      expect(requests[0].method, 'POST');
      expect(requests[0].url.path, '/json/state');
      expect(body(requests[0]), {'pin': '1234'});
      // Reading the config is never PIN-protected; only the write proves it.
      expect([for (final r in requests.skip(1)) '${r.method} ${r.url.path}'],
          ['GET /json/cfg', 'POST /json/cfg']);
      expect(body(requests[2]), {
        'if': {
          'live': {'rlm': true}
        }
      });
    });

    test('a wrong pin is reported', () async {
      handler = (r) async => r.url.path == '/json/cfg' && r.method == 'POST'
          ? http.Response('denied', 401)
          : http.Response('{"success":true}', 200);
      await expectLater(
          client().unlockSettings('0000'),
          throwsA(isA<WledException>().having((e) => e.cause, 'cause', 401)));
    });
  });

  group('setPanelLayout', () {
    test('posts a urlencoded form to /settings/2D', () async {
      handler = (r) async => http.Response('<html></html>', 200);
      await client().setPanelLayout(const DisplaySetup(
          16, 8, PanelWiring(corner: StartCorner.bottomRight, zigzag: true)));
      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.path, '/settings/2D');
      expect(r.headers['content-type'], startsWith('application/x-www-form-urlencoded'));
      expect(Uri.splitQueryString(r.body), {
        'SOMP': '1', 'MPC': '1', 'P0B': '1', 'P0R': '1', 'P0V': '0', 'P0S': 'on',
        'P0X': '0', 'P0Y': '0', 'P0W': '16', 'P0H': '8',
      });
    });

    test('null turns 2D off and a failure throws', () async {
      handler = (r) async => http.Response('<html></html>', 200);
      await client().setPanelLayout(null);
      expect(Uri.splitQueryString(requests.single.body), {'SOMP': '0'});
      handler = (r) async => http.Response('', 500);
      await expectLater(client().setPanelLayout(null), throwsA(isA<WledException>()));
    });
  });

  test('setRealtimeMaps writes if.live.rlm only', () async {
    await client().setRealtimeMaps(false);
    expect(body(requests.single), {
      'if': {
        'live': {'rlm': false}
      }
    });
    expect(requests.single.url.path, '/json/cfg');
  });

  test('setLedCount posts the complete entry with only len changed', () async {
    final original = entry();
    await client().setLedCount(256, original);
    final posted = body(requests.single);
    final ins = (posted['hw']['led']['ins'] as List).single as Map;
    expect(ins, {...original, 'len': 256});
    expect(original['len'], 128, reason: 'the caller\'s map is not modified');
    expect((posted['hw']['led'] as Map).keys.toList(), ['ins']);
    await expectLater(client().setLedCount(0, original), throwsA(isA<WledException>()));
    await expectLater(client().setLedCount(10, {}), throwsA(isA<WledException>()));
  });

  test('setCurrentLimit writes hw.led.maxpwr', () async {
    await client().setCurrentLimit(1700);
    expect(body(requests.single), {
      'hw': {
        'led': {'maxpwr': 1700}
      }
    });
  });

  test('reboot posts rb', () async {
    await client().reboot();
    expect(body(requests.single), {'rb': true});
  });

  group('setupState', () {
    const info = {
      'ver': '16.0.1', 'name': 'Desk', 'mac': '48e729a39308',
      'leds': {'count': 128, 'matrix': {'w': 16, 'h': 8}},
      'maps': [{'id': 0}],
    };
    final cfg = {
      'hw': {
        'led': {
          'maxpwr': 1000,
          'matrix': {
            'mpc': 1,
            'panels': [
              {'b': true, 'r': false, 'v': false, 's': true, 'x': 0, 'y': 0, 'w': 16, 'h': 8}
            ]
          },
          'ins': [entry()],
        }
      },
      'if': {
        'live': {'rlm': true, 'offset': 0}
      },
    };

    test('reads config and info', () async {
      handler = (r) async => http.Response(jsonEncode(r.url.path == '/json/info' ? info : cfg), 200);
      final s = await client().setupState();
      expect(s.isMatrix, isTrue);
      expect(s.wiring, const PanelWiring(corner: StartCorner.bottomLeft, zigzag: true));
      expect((s.width, s.height, s.ledCount, s.currentLimitMa), (16, 8, 128, 1000));
      expect(s.support, SetupSupport.supported);
    });

    test('reading never writes unless asked to check the lock', () async {
      handler = (r) async => http.Response(jsonEncode(r.url.path == '/json/info' ? info : cfg), 200);
      await client().setupState();
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    });

    test('a refused no-op write means the PIN is locked', () async {
      handler = (r) async => r.method == 'POST'
          ? http.Response('denied', 401)
          : http.Response(jsonEncode(r.url.path == '/json/info' ? info : cfg), 200);
      final s = await client().setupState(checkLock: true);
      expect(s.pinLocked, isTrue);
      expect(s.mac, '48e729a39308');
      expect(s.name, 'Desk');
    });

    test('other failures surface', () async {
      handler = (r) async => r.url.path == '/json/info' ? http.Response(jsonEncode(info), 200) : http.Response('x', 500);
      await expectLater(client().setupState(), throwsA(isA<WledException>()));
    });
  });
}
