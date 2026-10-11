import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/timezone.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('zones map to the WLED entry for their rules', () {
    const cases = {
      'Europe/London': 1,
      'Europe/Dublin': 1,
      'Europe/Lisbon': 1,
      'Europe/Berlin': 2,
      'Europe/Paris': 2,
      'Europe/Madrid': 2,
      'Europe/Zurich': 2,
      'Europe/Athens': 3,
      'Europe/Kyiv': 3,
      'Europe/Helsinki': 3,
      'America/New_York': 4,
      'America/Toronto': 4,
      'America/Chicago': 5,
      'America/Denver': 6,
      'America/Phoenix': 7,
      'America/Los_Angeles': 8,
      'Asia/Shanghai': 9,
      'Asia/Singapore': 9,
      'Asia/Tokyo': 10,
      'Asia/Seoul': 10,
      'Australia/Sydney': 11,
      'Pacific/Auckland': 12,
      'Asia/Kolkata': 14,
      'Asia/Calcutta': 14,
      'America/Regina': 15,
      'Australia/Darwin': 16,
      'Australia/Adelaide': 17,
      'Pacific/Honolulu': 18,
      'Asia/Novosibirsk': 19,
      'America/Anchorage': 20,
      'America/Mexico_City': 21,
      'Asia/Karachi': 22,
      'America/Sao_Paulo': 23,
      'Australia/Perth': 24,
      'UTC': 0,
      'Etc/UTC': 0,
    };
    cases.forEach((zone, tz) {
      expect(wledTimezoneFor(zone, const Duration(hours: 3)), (
        tz: tz,
        offsetSeconds: 0,
      ), reason: zone);
    });
  });

  test('unmatched zones fall back to UTC plus the current offset', () {
    expect(
      wledTimezoneFor('Asia/Kathmandu', const Duration(hours: 5, minutes: 45)),
      (tz: 0, offsetSeconds: 20700),
    );
    expect(wledTimezoneFor('Australia/Brisbane', const Duration(hours: 10)), (
      tz: 0,
      offsetSeconds: 36000,
    ));
    expect(
      wledTimezoneFor(
        'America/St_Johns',
        const Duration(hours: -2, minutes: -30),
      ),
      (tz: 0, offsetSeconds: -9000),
    );
    expect(wledTimezoneFor(null, const Duration(hours: -3)), (
      tz: 0,
      offsetSeconds: -10800,
    ));
    expect(wledTimezoneFor('', Duration.zero), (tz: 0, offsetSeconds: 0));
  });

  test('every table entry is mapped, and its standard offset matches the WLED rule', () {
    // Standard offset in minutes of a representative zone per WLED entry.
    const standard = {
      'Europe/Lisbon': 0,
      'Europe/Berlin': 60,
      'Europe/Athens': 120,
      'America/New_York': -300,
      'America/Chicago': -360,
      'America/Denver': -420,
      'America/Phoenix': -420,
      'America/Los_Angeles': -480,
      'Asia/Hong_Kong': 480,
      'Asia/Manila': 480,
      'Asia/Seoul': 540,
      'Australia/Hobart': 600,
      'Pacific/Auckland': 720,
      'Asia/Colombo': 330,
      'America/Regina': -360,
      'Australia/Darwin': 570,
      'Australia/Broken_Hill': 570,
      'Pacific/Honolulu': -600,
      'Asia/Bangkok': 420,
      'America/Juneau': -540,
      'America/Monterrey': -360,
      'Asia/Karachi': 300,
      'America/Bahia': -180,
      'Australia/Perth': 480,
      'Etc/UTC': 0,
    };
    standard.forEach((zone, minutes) {
      final i = wledTimezoneIndex(zone)!;
      expect(wledStandardOffsetMinutes[i], minutes, reason: zone);
    });
    expect(wledStandardOffsetMinutes, hasLength(25));
    // Entry 13 (North Korea, +8:30) is obsolete: Pyongyang uses Japan's +9.
    expect(wledTimezoneIndex('Asia/Pyongyang'), 10);
  });

  group('WledClient', () {
    late List<http.Request> sent;
    WledClient client() => WledClient(
      '192.168.1.5',
      client: MockClient((r) async {
        sent.add(r);
        return http.Response('{"success":true}', 200);
      }),
    );
    setUp(() => sent = []);

    test('setInternetTime enables NTP with tz and offset only', () async {
      await client().setInternetTime(tz: 4, offsetSeconds: 0);
      expect(sent.single.url.path, '/json/cfg');
      expect(jsonDecode(sent.single.body), {
        'if': {
          'ntp': {'en': true, 'tz': 4, 'offset': 0},
        },
      });
    });

    test('setClock posts unix seconds in UTC', () async {
      await client().setClock(DateTime.utc(2026, 10, 11, 12, 30, 5, 999));
      expect(sent.single.url.path, '/json/state');
      expect(jsonDecode(sent.single.body), {'time': 1791721805});
    });
  });
}
