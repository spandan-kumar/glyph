import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/device/device_time.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<(String, Map<String, dynamic>)> posts;
  late Map<String, dynamic> cfg;
  var failState = false, failCfg = false;
  final now = DateTime.utc(2026, 10, 11, 12, 30, 5);

  WledClient client() => WledClient(
    '192.168.1.5',
    client: MockClient((r) async {
      if (r.method == 'GET') {
        if (failCfg) return http.Response('no', 500);
        return http.Response(jsonEncode(cfg), 200);
      }
      if (r.url.path == '/json/state' && failState) {
        return http.Response('no', 500);
      }
      posts.add((r.url.path, jsonDecode(r.body) as Map<String, dynamic>));
      return http.Response('{"success":true}', 200);
    }),
  );

  setUp(() {
    posts = [];
    failState = failCfg = false;
    cfg = {
      'if': {
        'ntp': {'en': false, 'host': '0.wled.pool.ntp.org', 'tz': 0},
      },
    };
  });

  const nyc = (iana: 'America/New_York', offset: Duration(hours: -4));

  test(
    'NTP off: enables it with the phone zone, then sets the clock',
    () async {
      expect(await ensureDeviceTime(client(), phone: nyc, now: now), isTrue);
      expect(posts[0].$1, '/json/cfg');
      expect(posts[0].$2, {
        'if': {
          'ntp': {'en': true, 'tz': 4, 'offset': 0},
        },
      });
      expect(posts[1].$1, '/json/state');
      expect(posts[1].$2, {'time': now.millisecondsSinceEpoch ~/ 1000});
    },
  );

  test('unknown zone falls back to a fixed offset', () async {
    await ensureDeviceTime(
      client(),
      phone: (iana: null, offset: const Duration(hours: 5, minutes: 45)),
      now: now,
    );
    expect(((posts[0].$2['if'] as Map)['ntp'] as Map)['offset'], 20700);
  });

  test(
    'NTP already on: keeps the owner\'s zone, still sets the clock',
    () async {
      (cfg['if'] as Map)['ntp'] = {'en': true, 'tz': 8};
      expect(await ensureDeviceTime(client(), phone: nyc, now: now), isTrue);
      expect(posts.map((p) => p.$1), ['/json/state']);
    },
  );

  test('failures never throw and return false', () async {
    failState = true;
    expect(await ensureDeviceTime(client(), phone: nyc, now: now), isFalse);
    expect(posts.map((p) => p.$1), [
      '/json/cfg',
    ], reason: 'timezone still written');
    failState = false;
    failCfg = true;
    expect(await ensureDeviceTime(client(), phone: nyc, now: now), isFalse);
  });
}
