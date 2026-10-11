import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/features/glance/air_quality.dart';
import 'package:glyph/features/glance/air_quality_service.dart';
import 'package:glyph/features/glance/glance_generator.dart';
import 'package:glyph/features/glance/glance_model.dart';
import 'package:glyph/features/glance/weather.dart';
import 'package:glyph/features/glance/weather_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fixtures are real Open-Meteo responses (11 Oct 2026, 08:4x UTC) for public
// city coordinates; nothing personal is in them.
String fixture(String name) =>
    File('test/features/glance/fixtures/$name').readAsStringSync();

const berlin = WeatherPlace('Berlin', 52.52, 13.41, timezone: 'Europe/Berlin');
const delhi = WeatherPlace('Delhi', 28.61, 77.2);

class _Weather implements WeatherFeed {
  WeatherSnapshot? value;
  bool error = false;
  @override
  WeatherSnapshot? snapshot(WeatherPlace p) => value;
  @override
  bool failed(WeatherPlace p) => error;
}

class _Air implements AirFeed {
  AirSnapshot? value;
  bool error = false;
  @override
  AirSnapshot? snapshot(WeatherPlace p) => value;
  @override
  bool failed(WeatherPlace p) => error;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pal = palettes.first;
  // 08:46 UTC, 11 Oct 2026: shortly after the fixtures were captured.
  var now = DateTime.utc(2026, 10, 11, 8, 46);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 11, 8, 46);
  });

  group('forecast parsing', () {
    test('real response gives days in the place calendar and upcoming hours', () async {
      final api = WeatherApi(
        now: () => now,
        client: MockClient((r) async => http.Response.bytes(utf8.encode(fixture('open_meteo_forecast_berlin.json')), 200)),
      );
      addTearDown(api.dispose);
      final w = await api.fetch(berlin);
      expect(w.days.length, 4);
      expect(w.days.first.date, '2026-10-11');
      expect(w.days.first.high, 12.6);
      expect(w.days.first.low, 9.2);
      expect(w.days[1].weekday, 'MON');
      expect(w.hasForecast, true);
      final next = w.nextHours(now, 3);
      expect(next.length, 3);
      expect(next.first.time, DateTime.utc(2026, 10, 11, 9));
      expect(w.hourLabel(next.first), '11h'); // Berlin is UTC+2
      expect(w.upcomingDays(now, 2).map((d) => d.date), ['2026-10-11', '2026-10-12']);
      // Survives the cache round trip.
      final again = WeatherSnapshot.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map);
      expect(again.days.length, 4);
      expect(again.hours.length, 6);
    });

    test('missing or Fahrenheit forecast parts are dropped, never invented', () async {
      final raw = jsonDecode(fixture('open_meteo_forecast_berlin.json')) as Map;
      (raw['daily_units'] as Map)['temperature_2m_max'] = '°F';
      (raw['hourly'] as Map)['weather_code'] = [3, 80, null, 61, 80, 3];
      final api = WeatherApi(
        now: () => now,
        client: MockClient((r) async => http.Response.bytes(utf8.encode(jsonEncode(raw)), 200)),
      );
      addTearDown(api.dispose);
      final w = await api.fetch(berlin);
      expect(w.days, isEmpty);
      expect(w.hours.length, 5);
      expect(w.celsius, 10.9); // the current reading is unaffected
    });

    test('a reading cached before forecasts existed still loads', () {
      final old = WeatherSnapshot(observed: now, fetched: now, celsius: 5, code: 3, isDay: true);
      final json = old.toJson();
      expect(json.containsKey('days'), false);
      expect(WeatherSnapshot.fromJson(json).hasForecast, false);
    });
  });

  group('forecast card', () {
    late WeatherSnapshot snap;
    setUp(() async {
      final api = WeatherApi(
        now: () => now,
        client: MockClient((r) async => http.Response.bytes(utf8.encode(fixture('open_meteo_forecast_berlin.json')), 200)),
      );
      snap = await api.fetch(berlin);
      api.dispose();
    });
    GlanceCardGenerator gen(_Weather feed, {bool f = false}) => GlanceCardGenerator(
      GlanceCard(id: 'f', title: 'Berlin', kind: GlanceKind.forecast, place: berlin, fahrenheit: f),
      feed,
      now: () => now,
    );

    test('lights every supported size over its whole text cycle', () {
      final feed = _Weather()..value = snap;
      for (final size in [(8, 8), (32, 8), (16, 16), (32, 16), (32, 32)]) {
        final effect = gen(feed).create(size.$1, size.$2, 1), out = Frame(size.$1, size.$2);
        for (var t = 0.0; t < 60; t += 0.7) {
          effect.render(out, t, 0.1, Params({}), pal);
          expect(out.rgb.any((v) => v > 0), true, reason: '$size t=$t');
        }
      }
    });

    test('available only with a usable forecast; missing data is -- not zero', () {
      final feed = _Weather();
      final g = gen(feed);
      expect(g.available, false);
      feed.value = WeatherSnapshot(observed: now, fetched: now, celsius: 5, code: 3, isDay: true);
      expect(g.available, false); // a plain reading is not a forecast
      feed.value = snap;
      expect(g.available, true);
      feed.error = true;
      final out = Frame(16, 16);
      g.create(16, 16, 1).render(out, 0, 0, Params({}), pal);
      expect(out.get(15, 0), 0xffb347, reason: 'stale marker');
    });

    test('Fahrenheit and stale change the picture', () {
      final feed = _Weather()..value = snap;
      Frame draw(bool f, bool err) {
        feed.error = err;
        final out = Frame(32, 16);
        gen(feed, f: f).create(32, 16, 1).render(out, 0, 0, Params({}), pal);
        return out;
      }
      expect(draw(true, false).rgb.toList(), isNot(draw(false, false).rgb.toList()));
      expect(draw(false, true).get(31, 0), 0xffb347);
    });
  });

  group('air quality parsing', () {
    test('real batch response parses both indices and PM2.5 per place', () async {
      final api = AirQualityApi(
        WeatherApi(
          now: () => now,
          client: MockClient((r) async {
            expect(r.url.host, 'air-quality-api.open-meteo.com');
            expect(r.url.queryParameters['current'], 'european_aqi,us_aqi,pm2_5');
            expect(r.url.queryParameters['latitude'], '52.52,28.61');
            return http.Response.bytes(utf8.encode(fixture('open_meteo_air_quality_batch.json')), 200);
          }),
        ),
        now: () => now,
      );
      final r = await api.fetchMany([berlin, delhi]);
      final b = r[0] as AirSnapshot, d = r[1] as AirSnapshot;
      expect((b.euAqi, b.usAqi, b.pm25), (26, 29, 8.0));
      expect((d.euAqi, d.usAqi), (118, 157));
      expect(aqiLevel(AqiScale.us, d.usAqi!).word, 'Unhealthy');
      expect(aqiLevel(AqiScale.eu, d.euAqi!).word, 'Extreme');
    });

    test('null values are a coverage gap, not zero', () {
      final api = AirQualityApi(WeatherApi(), now: () => now);
      final s = api.parse({
        'current': {'time': 1791705600, 'european_aqi': null, 'us_aqi': null, 'pm2_5': null},
      });
      expect(s.hasData(AqiScale.us), false);
      expect(s.hasData(AqiScale.eu), false);
      expect(s.usAqi, isNull);
      expect(() => api.parse({'current': {'european_aqi': 3}}), throwsFormatException);
      expect(() => api.parse({'current': {'time': 1, 'us_aqi': 3}}), throwsFormatException);
    });

    test('scale follows the region unless set', () {
      expect(resolveAqiScale(AqiPref.auto, 'DE'), AqiScale.eu);
      expect(resolveAqiScale(AqiPref.auto, 'us'), AqiScale.us);
      expect(resolveAqiScale(AqiPref.auto, 'IN'), AqiScale.us);
      expect(resolveAqiScale(AqiPref.auto, null), AqiScale.us);
      expect(resolveAqiScale(AqiPref.eu, 'US'), AqiScale.eu);
      expect(resolveAqiScale(AqiPref.us, 'DE'), AqiScale.us);
    });

    test('level bands', () {
      expect(aqiLevel(AqiScale.us, 50).word, 'Good');
      expect(aqiLevel(AqiScale.us, 51).word, 'Moderate');
      expect(aqiLevel(AqiScale.us, 301).word, 'Hazardous');
      expect(aqiLevel(AqiScale.eu, 20).word, 'Good');
      expect(aqiLevel(AqiScale.eu, 21).word, 'Fair');
      expect(aqiLevel(AqiScale.eu, 101).word, 'Extreme');
    });

    test('freshness: stale after 90 minutes or a failed refresh, gone after 6 hours', () {
      final s = AirSnapshot(observed: now, fetched: now, usAqi: 40);
      expect(s.freshness(now), WeatherFreshness.fresh);
      expect(s.freshness(now, failed: true), WeatherFreshness.stale);
      expect(s.freshness(now.add(const Duration(minutes: 91))), WeatherFreshness.stale);
      expect(s.freshness(now.add(const Duration(hours: 6))), WeatherFreshness.unavailable);
    });
  });

  group('air quality card', () {
    GlanceCardGenerator gen(_Air air, {AqiPref pref = AqiPref.auto, String? region = 'DE'}) =>
        GlanceCardGenerator(
          GlanceCard(id: 'a', title: 'Berlin', kind: GlanceKind.airQuality, place: berlin, aqi: pref),
          _Weather(),
          air: air,
          region: () => region,
          now: () => now,
        );

    test('lights every supported size over its whole text cycle', () {
      final air = _Air()..value = AirSnapshot(observed: now, fetched: now, usAqi: 157, euAqi: 118, pm25: 68);
      for (final size in [(8, 8), (32, 8), (16, 16), (32, 16), (32, 32)]) {
        final effect = gen(air).create(size.$1, size.$2, 1), out = Frame(size.$1, size.$2);
        for (var t = 0.0; t < 40; t += 0.7) {
          effect.render(out, t, 0.1, Params({}), pal);
          expect(out.rgb.any((v) => v > 0), true, reason: '$size t=$t');
        }
      }
    });

    test('the number takes the level colour, and the chosen index decides it', () {
      final air = _Air()..value = AirSnapshot(observed: now, fetched: now, usAqi: 29, euAqi: 118);
      bool has(Frame f, int rgb) => f.rgb.toList().contains(rgb >> 16 & 255) && _hasPixel(f, rgb);
      final eu = Frame(16, 16), us = Frame(16, 16);
      gen(air, pref: AqiPref.eu).create(16, 16, 1).render(eu, 0, 0, Params({}), pal);
      gen(air, pref: AqiPref.us).create(16, 16, 1).render(us, 0, 0, Params({}), pal);
      expect(has(eu, 0xc77dff), true); // Extreme
      expect(has(us, 0x3ddc84), true); // Good
      expect(gen(air, region: 'US').scale, AqiScale.us);
      expect(gen(air).scale, AqiScale.eu);
    });

    test('no coverage or no data is skipped, shows -- and never crashes', () {
      final air = _Air();
      final g = gen(air);
      expect(g.available, false);
      air.value = AirSnapshot(observed: now, fetched: now); // gap: all null
      expect(g.available, false);
      for (final size in [(8, 8), (32, 8), (16, 16), (32, 32)]) {
        final out = Frame(size.$1, size.$2), e = g.create(size.$1, size.$2, 1);
        for (final t in [0.0, 4.0, 9.0]) {
          e.render(out, t, 0.1, Params({}), pal);
          expect(out.rgb.any((v) => v > 0), true);
        }
      }
      // No air feed at all (card used where none was wired) is the same.
      final bare = GlanceCardGenerator(
        const GlanceCard(id: 'b', title: 'B', kind: GlanceKind.airQuality, place: berlin),
        _Weather(),
        now: () => now,
      );
      expect(bare.available, false);
      bare.create(16, 16, 1).render(Frame(16, 16), 0, 0, Params({}), pal);
    });

    test('stale values stay visible and are marked', () {
      final air = _Air()
        ..value = AirSnapshot(observed: now, fetched: now, usAqi: 40, euAqi: 30)
        ..error = true;
      final g = gen(air);
      expect(g.available, true);
      final out = Frame(16, 16);
      g.create(16, 16, 1).render(out, 0, 0, Params({}), pal);
      expect(out.get(15, 0), 0xffb347);
      now = now.add(const Duration(hours: 7));
      expect(g.available, false);
    });
  });

  group('air quality service', () {
    AirQualityService service(MockClient client) => AirQualityService(
      now: () => now,
      api: AirQualityApi(WeatherApi(now: () => now, client: client), now: () => now),
    );
    String body() => jsonEncode({
      'utc_offset_seconds': 0,
      'current': {'time': now.millisecondsSinceEpoch ~/ 1000, 'european_aqi': 20, 'us_aqi': 30, 'pm2_5': 5.0},
    });

    test('nothing is requested unless a card watches, then once per cadence and shared', () async {
      var calls = 0;
      final s = service(MockClient((r) async {
        calls++;
        return http.Response(body(), 200);
      }));
      addTearDown(s.dispose);
      await s.load();
      expect(calls, 0);
      expect(s.isWatching, false);
      final a = Object(), b = Object();
      s.watch(a, [berlin]);
      s.watch(b, [berlin]);
      await Future<void>.delayed(Duration.zero);
      await s.refresh(berlin);
      expect(calls, 1);
      expect(s.snapshot(berlin)!.usAqi, 30);
      now = now.add(const Duration(minutes: 29));
      await s.refresh(berlin);
      expect(calls, 1);
      s.release(a);
      s.release(b);
      expect(s.isWatching, false);
      // A fresh service reads the cache without any request.
      final reload = service(MockClient((r) async {
        fail('Cache load must not fetch');
      }));
      addTearDown(reload.dispose);
      await reload.load();
      expect(reload.snapshot(berlin)!.euAqi, 20);
    });

    test('429 backs off for Retry-After, shows the cached value stale, then recovers', () async {
      var calls = 0, limited = false;
      final s = service(MockClient((r) async {
        calls++;
        if (limited) return http.Response('slow down', 429, headers: {'retry-after': '3600'});
        return http.Response(body(), 200);
      }));
      addTearDown(s.dispose);
      await s.refresh(berlin);
      limited = true;
      now = now.add(const Duration(minutes: 31));
      await s.refresh(berlin);
      expect(calls, 2);
      expect(s.failed(berlin), true);
      expect(s.freshness(berlin), WeatherFreshness.stale);
      expect(s.snapshot(berlin)!.usAqi, 30, reason: 'last value kept');
      now = now.add(const Duration(minutes: 45));
      await s.refresh(berlin);
      expect(calls, 2, reason: 'Retry-After of an hour beats the 30 minute backoff');
      limited = false;
      now = now.add(const Duration(minutes: 20));
      await s.refresh(berlin);
      expect(calls, 3);
      expect(s.failed(berlin), false);
    });

    test('offline with nothing cached backs off 10 s then 30 s and stays unavailable', () async {
      var calls = 0;
      final s = service(MockClient((r) async {
        calls++;
        throw http.ClientException('offline');
      }));
      addTearDown(s.dispose);
      await s.refresh(berlin);
      expect(s.freshness(berlin), WeatherFreshness.unavailable);
      await s.refresh(berlin);
      expect(calls, 1, reason: 'still backing off');
      now = now.add(const Duration(seconds: 11));
      await s.refresh(berlin);
      expect(calls, 2);
      now = now.add(const Duration(seconds: 20));
      await s.refresh(berlin);
      expect(calls, 2);
      now = now.add(const Duration(seconds: 11));
      await s.refresh(berlin);
      expect(calls, 3);
    });
  });

  group('card model', () {
    test('forecast and air quality cards round-trip; a plain card stays unchanged', () {
      final f = GlanceCard(id: 'f', title: 'Berlin', kind: GlanceKind.forecast, place: berlin, fahrenheit: true);
      final a = GlanceCard(id: 'a', title: 'Berlin', kind: GlanceKind.airQuality, place: berlin, aqi: AqiPref.eu);
      for (final c in [f, a]) {
        final back = GlanceCard.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map);
        expect((back.kind, back.fahrenheit, back.aqi), (c.kind, c.fahrenheit, c.aqi));
        expect(back.valid, true);
      }
      expect(f.toJson().containsKey('aqi'), false);
      expect(
        () => GlanceCard.fromJson({'id': 'x', 'title': 'x', 'kind': 'airQuality'}),
        throwsFormatException,
        reason: 'a place is required',
      );
      expect(() => GlanceCard.fromJson({...a.toJson(), 'aqi': 'moon'}), throwsArgumentError);
    });
  });
}

bool _hasPixel(Frame f, int rgb) {
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      if (f.get(x, y) == rgb) return true;
    }
  }
  return false;
}
