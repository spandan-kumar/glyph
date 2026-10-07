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
    for (var i = 0; i < 6; i++) {
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
          (r) async => http.Response.bytes(
            utf8.encode(jsonEncode(raw)),
            i == 5 ? 503 : 200,
          ),
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
    now = now.add(const Duration(minutes: 30));
    expect(reload.freshness(place), WeatherFreshness.stale);
    now = now.add(const Duration(minutes: 90));
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
}
