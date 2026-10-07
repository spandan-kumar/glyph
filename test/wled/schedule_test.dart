import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/schedule.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'manage_fixtures.dart';

void main() {
  final readBack = (jsonDecode(timersBackV16) as List).cast<Map<String, dynamic>>();

  test('real config: no timers, boot preset 102, NTP on, no location', () {
    final s = WledSchedule.fromConfig(jsonDecode(cfgV16));
    expect(s.timers, isEmpty);
    expect(s.bootPreset, 102);
    expect(s.ntpEnabled, isTrue);
    expect(s.hasLocation, isFalse);
    expect(s.isEditable, isTrue);
  });

  test('parses timers the device read back', () {
    final s = WledSchedule.fromConfig({
      ...jsonDecode(cfgV16) as Map<String, dynamic>,
      'timers': {'ins': readBack},
    });
    final [a, b, c] = s.timers;
    expect(a.trigger, TimerTrigger.time);
    expect((a.hour, a.minute, a.presetId, a.enabled), (3, 7, 200, false));
    expect(
      [for (var d = 1; d <= 7; d++) a.runsOn(d)],
      [true, false, true, false, true, false, false],
      reason: 'dow 21 = Mon, Wed, Fri',
    );
    expect(a.allYear, isTrue);
    expect(b.trigger, TimerTrigger.sunset);
    expect(b.minute, -30);
    expect(b.allYear, isFalse);
    expect((b.startMonth, b.startDay, b.endMonth, b.endDay), (11, 2, 2, 20));
    expect(c.trigger, TimerTrigger.everyHour);
    expect(c.minute, 15);
  });

  test('toJson is exactly what serializeConfig returns', () {
    final timers = [for (final j in readBack) WledTimer.fromJson(j)];
    expect([for (final t in timers) t.toJson()], readBack);
    expect(WledSchedule.timersPatch(timers), {
      'timers': {'ins': readBack},
    });
    expect(WledSchedule.bootPresetPatch(7), {
      'def': {'ps': 7},
    });
  });

  test('missing keys use cfg.cpp defaults', () {
    final t = WledTimer.fromJson({'hour': 6, 'macro': 3});
    expect((t.minute, t.enabled, t.weekdays), (0, false, WledTimer.allDays));
    expect((t.startMonth, t.startDay, t.endMonth, t.endDay), (1, 1, 12, 31));
  });

  test('pre-16 configs: second hour-255 timer is sunset', () {
    final s = WledSchedule.fromConfig({
      'vid': 2412100,
      'timers': {
        'ins': [
          {'en': 1, 'hour': 7, 'min': 0, 'macro': 1},
          {'en': 1, 'hour': 255, 'min': 10, 'macro': 2},
          {'en': 1, 'hour': 255, 'min': -5, 'macro': 3},
        ],
      },
    });
    expect(s.timers.map((t) => t.trigger), [
      TimerTrigger.time,
      TimerTrigger.sunrise,
      TimerTrigger.sunset,
    ]);
    expect(s.isEditable, isFalse);
  });

  test('validation mirrors addTimer limits; offsets clamp', () {
    expect(const WledTimer(presetId: 0).validate(), isNotNull);
    expect(const WledTimer(presetId: 1, hour: 25).validate(), isNotNull);
    expect(const WledTimer(presetId: 1, minute: 60).validate(), isNotNull);
    expect(const WledTimer(presetId: 1, weekdays: 0).validate(), isNotNull);
    expect(
      const WledTimer(presetId: 1, hour: WledTimer.sunriseHour, minute: -90).validate(),
      isNull,
    );
    expect(
      const WledTimer(presetId: 1, hour: WledTimer.sunriseHour, minute: 300).toJson()['min'],
      WledTimer.maxSunOffset,
    );
  });

  group('client', () {
    late List<http.Request> posts;
    var status = 200;

    WledClient client() => WledClient(
      '192.168.29.6',
      delay: (_) async {},
      client: MockClient((r) async {
        if (r.method == 'POST') {
          posts.add(r);
          return http.Response(status == 200 ? '{"success":true}' : '{"error":11}', status);
        }
        return r.url.path == '/json/cfg'
            ? http.Response(cfgV16, 200)
            : http.Response('Not found', 404);
      }),
    );

    setUp(() {
      posts = [];
      status = 200;
    });

    test('saveTimers / setBootPreset / setDeviceName post partial /json/cfg', () async {
      final c = client();
      await c.saveTimers([WledTimer.fromJson(readBack.first)]);
      await c.setBootPreset(0);
      await c.setDeviceName('  ${'L' * 40} ');
      expect(posts.map((r) => r.url.path), everyElement('/json/cfg'));
      expect(jsonDecode(posts[0].body), {
        'timers': {
          'ins': [readBack.first],
        },
      });
      expect(jsonDecode(posts[1].body), {
        'def': {'ps': 0},
      });
      expect(jsonDecode(posts[2].body), {
        'id': {'name': 'L' * 32},
      });
      expect((await c.schedule()).bootPreset, 102);
    });

    test('invalid timers are rejected before any write', () {
      expect(
        () => client().saveTimers([const WledTimer(presetId: 0)]),
        throwsA(isA<WledException>()),
      );
      expect(
        () => client().saveTimers(
          List.filled(WledSchedule.maxTimers + 1, const WledTimer(presetId: 1)),
        ),
        throwsA(isA<WledException>()),
      );
      expect(() => client().setDeviceName('  '), throwsA(isA<WledException>()));
      expect(posts, isEmpty);
    });

    test('PIN-locked settings give a clear error', () async {
      status = 401;
      await expectLater(
        client().setBootPreset(1),
        throwsA(isA<WledException>().having((e) => e.message, 'message', contains('PIN'))),
      );
    });
  });
}
