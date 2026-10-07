import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'glance_model.dart';
import 'weather.dart';

class WeatherApi {
  WeatherApi({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;
  final http.Client _client;
  final DateTime Function() _now;
  static const maxBytes = 64 * 1024;
  static const timeout = Duration(seconds: 12);

  Future<Map<String, dynamic>> _get(Uri uri) async {
    return (() async {
      final response = await _client.send(http.Request('GET', uri));
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > maxBytes) {
        throw const FormatException('Weather unavailable');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const FormatException('Weather response too large');
        }
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid weather response');
      }
      return data;
    })().timeout(timeout);
  }

  Future<List<WeatherPlace>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final raw = await _get(
      Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': q.substring(0, q.length.clamp(0, 100)),
        'count': '8',
        'language': 'en',
        'format': 'json',
      }),
    );
    final out = <WeatherPlace>[];
    for (final m
        in (raw['results'] as List? ?? const []).take(8).whereType<Map>()) {
      try {
        final label = [
          m['name'],
          m['admin1'],
          m['country'],
        ].whereType<String>().where((v) => v.isNotEmpty).toSet().join(', ');
        final p = WeatherPlace(
          label,
          (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(),
          timezone: m['timezone'] as String? ?? 'auto',
        );
        if (p.valid) out.add(p);
      } catch (_) {
        /* Skip incomplete locations, never substitute zero coordinates. */
      }
    }
    return out;
  }

  Future<WeatherSnapshot> fetch(WeatherPlace place) async {
    if (!place.valid) throw ArgumentError('Invalid place');
    final raw = await _get(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '${place.latitude}',
        'longitude': '${place.longitude}',
        'current': 'temperature_2m,weather_code,is_day',
        'daily': 'temperature_2m_max,temperature_2m_min',
        'forecast_days': '1',
        'timezone': place.timezone,
        'timeformat': 'unixtime',
        'temperature_unit': 'celsius',
      }),
    );
    final current = raw['current'] as Map;
    if (current['time'] is! num ||
        current['temperature_2m'] is! num ||
        current['weather_code'] is! num ||
        (current['is_day'] != 0 && current['is_day'] != 1) ||
        (raw['current_units'] as Map?)?['temperature_2m'] != '°C') {
      throw const FormatException('Incomplete weather response');
    }
    double? daily(String key) {
      if ((raw['daily_units'] as Map?)?[key] != '°C') return null;
      final values = (raw['daily'] as Map?)?[key];
      return values is List && values.isNotEmpty && values.first is num
          ? (values.first as num).toDouble()
          : null;
    }

    final dailyTimes = (raw['daily'] as Map?)?['time'];
    final offset = (raw['utc_offset_seconds'] as num?)?.toInt();
    String? forecastDay;
    if (dailyTimes is List &&
        dailyTimes.isNotEmpty &&
        dailyTimes.first is num &&
        offset != null &&
        offset.abs() <= 14 * 3600) {
      forecastDay = DateTime.fromMillisecondsSinceEpoch(
        ((dailyTimes.first as num).toInt() + offset) * 1000,
        isUtc: true,
      ).toIso8601String().substring(0, 10);
    }
    final result = WeatherSnapshot.fromJson({
      'observed': DateTime.fromMillisecondsSinceEpoch(
        (current['time'] as num).toInt() * 1000,
        isUtc: true,
      ).toIso8601String(),
      'fetched': _now().toUtc().toIso8601String(),
      'temperature': current['temperature_2m'],
      'code': current['weather_code'],
      'day': current['is_day'] == 1,
      'forecastDay': ?forecastDay,
      'utcOffset': offset ?? 0,
      if (daily('temperature_2m_max') != null)
        'high': daily('temperature_2m_max'),
      if (daily('temperature_2m_min') != null)
        'low': daily('temperature_2m_min'),
    });
    if (result.freshness(_now()) == WeatherFreshness.unavailable) {
      throw const FormatException('Outdated weather response');
    }
    return result;
  }

  void dispose() => _client.close();
}
