import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/glance/glance_model.dart';
import 'package:glyph/features/glance/weather.dart';
import 'package:glyph/features/glance/weather_api.dart';
import 'package:glyph/features/glance/weather_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const place = WeatherPlace('Delhi', 28.6, 77.2, timezone: 'Asia/Kolkata');
  late DateTime now;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 7, 12);
  });
  Map<String, Object> response() => {
    'current_units': {'temperature_2m': '°C'},
    'current': {
      'time': now.millisecondsSinceEpoch ~/ 1000,
      'temperature_2m': 25.5,
      'weather_code': 61,
      'is_day': 1,
    },
    'utc_offset_seconds': 19800,
    'daily_units': {'temperature_2m_max': '°C', 'temperature_2m_min': '°C'},
    'daily': {
      'time': [
        DateTime.utc(2026, 10, 6, 18, 30).millisecondsSinceEpoch ~/ 1000,
      ],
      'temperature_2m_max': [30],
      'temperature_2m_min': [19],
    },
  };
  test('forecast requests only required fields, uses UTC timestamps and chosen timezone', () async {
    final api = WeatherApi(
      now: () => now,
      client: MockClient((r) async {
        expect(r.url.host, 'api.open-meteo.com');
        expect(
          r.url.queryParameters['current'],
          'temperature_2m,weather_code,is_day',
        );
        expect(r.url.queryParameters['timezone'], 'Asia/Kolkata');
        expect(r.url.queryParameters['forecast_days'], '1');
        expect(r.url.queryParameters['timeformat'], 'unixtime');
        return http.Response.bytes(utf8.encode(jsonEncode(response())), 200);
      }),
    );
    addTearDown(api.dispose);
    final value = await api.fetch(place);
    expect(value.observed, now);
    expect(value.celsius, 25.5);
    expect(value.high, 30);
    expect(value.low, 19);
    expect(value.dailyIsToday(now), true);
  });
  test('missing temperatures, invalid codes, stale dates, units and status never invent data', () async {
    for (var i = 0; i < 5; i++) {
      final raw = response(), current = raw['current'] as Map;
      switch (i) {
        case 0:
          current.remove('temperature_2m');
        case 1:
          current['weather_code'] = 4;
        case 2:
          current['weather_code'] = 61.5;
        case 3:
          current['time'] =
              now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch ~/
              1000;
        case 4:
          (raw['current_units'] as Map)['temperature_2m'] = '°F';
      }
      final api = WeatherApi(
        now: () => now,
        client: MockClient(
          (r) async => http.Response.bytes(utf8.encode(jsonEncode(raw)), 200),
        ),
      );
      await expectLater(api.fetch(place), throwsFormatException);
      api.dispose();
    }
  });
  test('bounded response parsing rejects oversized streamed bodies', () async {
    final api = WeatherApi(
      client: MockClient.streaming(
        (r, body) async => http.StreamedResponse(
          Stream.value(List.filled(WeatherApi.maxBytes + 1, 32)),
          200,
        ),
      ),
    );
    addTearDown(api.dispose);
    await expectLater(api.fetch(place), throwsFormatException);
  });
  test('search names ambiguous places and skips missing coordinates', () async {
    final api = WeatherApi(
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'results': [
              {
                'name': 'Springfield',
                'admin1': 'Illinois',
                'country': 'US',
                'latitude': 39.8,
                'longitude': -89.6,
                'timezone': 'America/Chicago',
              },
              {'name': 'Missing', 'latitude': 1},
            ],
          }),
          200,
        ),
      ),
    );
    addTearDown(api.dispose);
    expect(await api.search('x'), isEmpty);
    final places = await api.search('Springfield');
    expect(places.single.name, 'Springfield, Illinois, US');
    expect(places.single.longitude, -89.6);
  });
  test('owners share inflight requests, cadence, timestamped cache and last-owner release', () async {
    var calls = 0;
    final gate = Completer<void>();
    final service = WeatherService(
      now: () => now,
      api: WeatherApi(
        now: () => now,
        client: MockClient((r) async {
          calls++;
          await gate.future;
          return http.Response.bytes(utf8.encode(jsonEncode(response())), 200);
        }),
      ),
    );
    addTearDown(service.dispose);
    final a = Object(), b = Object();
    service.watch(a, [place]);
    service.watch(b, [place]);
    final pending = service.refresh(place);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    gate.complete();
    await pending;
    expect(service.snapshot(place)!.celsius, 25.5);
    await service.refresh(place);
    expect(calls, 1);
    service.release(a);
    expect(service.isWatching, true);
    service.release(b);
    expect(service.isWatching, false);
    final reload = WeatherService(
      now: () => now,
      api: WeatherApi(
        client: MockClient((r) async {
          fail('Cache load must not fetch');
        }),
      ),
    );
    addTearDown(reload.dispose);
    await reload.load();
    expect(reload.snapshot(place)!.celsius, 25.5);
    expect(reload.isWatching, false);
    now = now.add(const Duration(minutes: 45));
    expect(reload.freshness(place), WeatherFreshness.stale);
    now = now.add(const Duration(minutes: 75));
    expect(reload.freshness(place), WeatherFreshness.unavailable);
  });
  test(
    'offline failure retains cache, backs off and throttles explicit retries',
    () async {
      var calls = 0, offline = false;
      final service = WeatherService(
        now: () => now,
        api: WeatherApi(
          now: () => now,
          client: MockClient((r) async {
            calls++;
            if (offline) throw http.ClientException('offline');
            return http.Response.bytes(
              utf8.encode(jsonEncode(response())),
              200,
            );
          }),
        ),
      );
      addTearDown(service.dispose);
      await service.refresh(place);
      offline = true;
      now = now.add(const Duration(minutes: 15));
      await service.refresh(place);
      expect(calls, 2);
      expect(service.freshness(place), WeatherFreshness.stale);
      await service.refresh(place, force: true);
      expect(calls, 2);
      now = now.add(const Duration(minutes: 1));
      await service.refresh(place, force: true);
      expect(calls, 3);
      now = now.add(const Duration(minutes: 20));
      await service.refresh(place);
      expect(calls, 3);
      now = now.add(const Duration(minutes: 10));
      await service.refresh(place);
      expect(calls, 4);
      expect(service.snapshot(place)!.celsius, 25.5);
      now = now.add(const Duration(hours: 2));
      expect(service.freshness(place), WeatherFreshness.unavailable);
    },
  );

  group('retry and batching', () {
    http.Response ok([Object? body]) =>
        http.Response.bytes(utf8.encode(jsonEncode(body ?? response())), 200);
    WeatherService service(http.Client client) {
      final s = WeatherService(
        now: () => now,
        api: WeatherApi(now: () => now, client: client),
      );
      addTearDown(s.dispose);
      return s;
    }

    test(
      'with no cache a failure retries after 10 s, 30 s, 60 s, then 15 min',
      () async {
        var calls = 0, fail = true;
        final s = service(
          MockClient((r) async {
            calls++;
            if (fail) throw http.ClientException('blip');
            return ok();
          }),
        );
        await s.refresh(place);
        expect(calls, 1);
        expect(s.snapshot(place), isNull);
        now = now.add(const Duration(seconds: 9));
        await s.refresh(place);
        expect(calls, 1);
        now = now.add(const Duration(seconds: 1));
        await s.refresh(place);
        expect(calls, 2);
        now = now.add(const Duration(seconds: 30));
        await s.refresh(place);
        expect(calls, 3);
        now = now.add(const Duration(seconds: 60));
        await s.refresh(place);
        expect(calls, 4);
        now = now.add(const Duration(minutes: 14));
        await s.refresh(place);
        expect(calls, 4);
        now = now.add(const Duration(minutes: 1));
        fail = false;
        await s.refresh(place);
        expect(calls, 5);
        expect(s.snapshot(place)!.celsius, 25.5);
      },
    );

    testWidgets(
      'a short backoff wakes itself without waiting for the minute tick',
      (tester) async {
        var calls = 0;
        final s = service(
          MockClient((r) async {
            calls++;
            if (calls == 1) throw http.ClientException('blip');
            return ok();
          }),
        );
        final owner = Object();
        s.watch(owner, [place]);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        expect(calls, 1);
        now = now.add(const Duration(seconds: 11));
        await tester.pump(const Duration(seconds: 11));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        expect(calls, 2);
        expect(s.snapshot(place), isNotNull);
        s.release(owner);
      },
    );

    test('429 honours Retry-After; 5xx is transient', () async {
      var calls = 0, status = 429;
      final s = service(
        MockClient((r) async {
          calls++;
          return status == 200
              ? ok()
              : http.Response(
                  '',
                  status,
                  headers: status == 429 ? {'retry-after': '600'} : {},
                );
        }),
      );
      await s.refresh(place);
      now = now.add(const Duration(minutes: 9));
      await s.refresh(place);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 1));
      status = 503;
      await s.refresh(place);
      expect(calls, 2);
      expect(s.failed(place), true);
      now = now.add(const Duration(seconds: 30));
      status = 200;
      await s.refresh(place);
      expect(calls, 3);
      expect(s.failed(place), false);
    });

    test('with a good cache failures back off 15/30/60 minutes', () async {
      var calls = 0, offline = false;
      final s = service(
        MockClient((r) async {
          calls++;
          if (offline) throw http.ClientException('offline');
          return ok();
        }),
      );
      await s.refresh(place);
      offline = true;
      now = now.add(const Duration(minutes: 15));
      await s.refresh(place);
      expect(calls, 2);
      now = now.add(const Duration(minutes: 14));
      await s.refresh(place);
      expect(calls, 2);
      now = now.add(const Duration(minutes: 1));
      await s.refresh(place);
      expect(calls, 3);
      now = now.add(const Duration(minutes: 29));
      await s.refresh(place);
      expect(calls, 3);
    });

    test('several places share one request per timezone', () async {
      final urls = <Uri>[];
      const other = WeatherPlace('Pune', 18.5, 73.8, timezone: 'Asia/Kolkata');
      const far = WeatherPlace('Oslo', 59.9, 10.7, timezone: 'Europe/Oslo');
      final s = service(
        MockClient((r) async {
          urls.add(r.url);
          final n = r.url.queryParameters['latitude']!.split(',').length;
          return ok(
            n == 1
                ? response()
                : [
                    for (var i = 0; i < n; i++)
                      response()
                        ..['current'] = {
                          ...(response()['current'] as Map),
                          'temperature_2m': 10.0 + i,
                        },
                  ],
          );
        }),
      );
      final owner = Object();
      s.watch(owner, [place, other, far]);
      await Future.wait([
        for (final p in [place, other, far]) s.refresh(p),
      ]);
      expect(urls.length, 2);
      final shared = urls.firstWhere(
        (u) => u.queryParameters['timezone'] == 'Asia/Kolkata',
      );
      expect(shared.queryParameters['latitude'], '28.6,18.5');
      expect(shared.queryParameters['longitude'], '77.2,73.8');
      expect(s.snapshot(place)!.celsius, 10);
      expect(s.snapshot(other)!.celsius, 11);
      expect(s.snapshot(far)!.celsius, 25.5);
      s.release(owner);
    });

    test('eviction is least-recently-used and keeps active backoff', () async {
      var requests = 0;
      final s = service(
        MockClient((r) async {
          if (r.url.queryParameters['latitude'] == '1.0') {
            requests++;
            return http.Response('', 503);
          }
          return ok();
        }),
      );
      WeatherPlace at(int i) =>
          WeatherPlace('P$i', 10.0 + i, 20, timezone: 'UTC');
      const bad = WeatherPlace('Bad', 1, 2, timezone: 'UTC');
      await s.refresh(bad);
      for (var i = 0; i < 32; i++) {
        await s.refresh(at(i));
      }
      s.snapshot(at(0));
      await s.refresh(at(40));
      expect(s.snapshot(at(0)), isNotNull);
      expect(s.snapshot(at(1)), isNull);
      for (var i = 41; i < 110; i++) {
        await s.refresh(at(i));
      }
      // The failing place stays inside its backoff window on the real service.
      await s.refresh(bad);
      expect(s.failed(bad), true);
      expect(requests, 1);
    });
  });

  group('api details', () {
    test('sends a descriptive User-Agent and drains non-200 bodies', () async {
      var listened = false;
      String? agent;
      final api = WeatherApi(
        client: MockClient.streaming((r, body) async {
          agent = r.headers['User-Agent'];
          return http.StreamedResponse(
            Stream.fromIterable([
              [1, 2, 3],
            ]).map((e) {
              listened = true;
              return e;
            }),
            429,
            headers: {'retry-after': '120'},
          );
        }),
      );
      addTearDown(api.dispose);
      await expectLater(
        api.fetch(place),
        throwsA(
          isA<WeatherHttpException>()
              .having((e) => e.status, 'status', 429)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 120),
              ),
        ),
      );
      expect(listened, true);
      expect(agent, startsWith('Glyph'));
      expect(agent, contains('github.com/spandan-kumar/glyph'));
    });
  });

  test('every WMO code Open-Meteo can return has a real description', () {
    for (var code = 0; code <= 99; code++) {
      if (validWeatherCode(code)) {
        expect(weatherDescription(code), isNot('Unavailable'), reason: '$code');
      }
    }
    expect(weatherDescription(4), 'Unavailable');
    expect(validWeatherCode(3), true);
  });
}
