import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'glance_model.dart';
import 'weather.dart';

/// A non-200 reply. [retryAfter] carries a server-requested pause (429/503).
class WeatherHttpException implements Exception {
  const WeatherHttpException(this.status, [this.retryAfter]);
  final int status;
  final Duration? retryAfter;
  bool get transient => status == 429 || status >= 500;
  @override
  String toString() => 'Weather unavailable (HTTP $status)';
}

class WeatherApi {
  WeatherApi({http.Client? client, DateTime Function()? now})
    : _client =
          client ??
          IOClient(
            HttpClient()..connectionTimeout = const Duration(seconds: 8),
          ),
      _now = now ?? DateTime.now {
    _lookupVersion();
  }
  final http.Client _client;
  final DateTime Function() _now;
  static const maxBytes = 64 * 1024;
  static const timeout = Duration(seconds: 12);
  static const maxBatch = 10;
  static const _repo = 'https://github.com/spandan-kumar/glyph';
  static String _version = '';
  static bool _versionAsked = false;

  /// The app version is looked up once in the background; requests made
  /// before it arrives identify as plain "Glyph".
  static void _lookupVersion() {
    if (_versionAsked) return;
    _versionAsked = true;
    unawaited(
      PackageInfo.fromPlatform().then(
        (i) => _version = '/${i.version}',
        onError: (Object _) {},
      ),
    );
  }

  static String get userAgent => 'Glyph$_version (+$_repo)';

  static Duration? parseRetryAfter(String? raw) {
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds != null) return Duration(seconds: seconds.clamp(0, 3600));
    try {
      final d = HttpDate.parse(raw).difference(DateTime.now().toUtc());
      return d.isNegative
          ? Duration.zero
          : (d > const Duration(hours: 1) ? const Duration(hours: 1) : d);
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _get(Uri uri) async {
    final abort = Completer<void>();
    return (() async {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..headers['User-Agent'] = userAgent;
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        await response.stream.drain<void>().catchError((Object _) {});
        throw WeatherHttpException(
          response.statusCode,
          parseRetryAfter(response.headers['retry-after']),
        );
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        await response.stream.drain<void>().catchError((Object _) {});
        throw const FormatException('Weather response too large');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const FormatException('Weather response too large');
        }
        bytes.addAll(chunk);
      }
      return jsonDecode(utf8.decode(bytes));
    })().timeout(
      timeout,
      onTimeout: () {
        if (!abort.isCompleted) abort.complete();
        throw TimeoutException('Weather request timed out');
      },
    );
  }

  Future<Map<String, dynamic>> _getMap(Uri uri) async {
    final data = await _get(uri);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid weather response');
    }
    return data;
  }

  Future<List<WeatherPlace>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final raw = await _getMap(
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
    final r = (await fetchMany([place])).single;
    if (r is WeatherSnapshot) return r;
    throw r;
  }

  /// One request per timezone group (Open-Meteo takes comma-separated
  /// coordinates). Each result is a snapshot or the error for that place.
  Future<List<Object>> fetchMany(List<WeatherPlace> places) async {
    for (final p in places) {
      if (!p.valid) throw ArgumentError('Invalid place');
    }
    final results = List<Object>.filled(
      places.length,
      const FormatException('Weather unavailable'),
    );
    final groups = <String, List<int>>{};
    for (var i = 0; i < places.length; i++) {
      groups.putIfAbsent(places[i].timezone, () => []).add(i);
    }
    for (final entry in groups.entries) {
      for (var s = 0; s < entry.value.length; s += maxBatch) {
        final idx = entry.value.skip(s).take(maxBatch).toList();
        try {
          final data = await _get(
            Uri.https('api.open-meteo.com', '/v1/forecast', {
              'latitude': idx.map((i) => '${places[i].latitude}').join(','),
              'longitude': idx.map((i) => '${places[i].longitude}').join(','),
              'current': 'temperature_2m,weather_code,is_day',
              'daily': 'temperature_2m_max,temperature_2m_min',
              'forecast_days': '1',
              'timezone': entry.key,
              'timeformat': 'unixtime',
              'temperature_unit': 'celsius',
            }),
          );
          final list = data is List ? data : [data];
          for (var k = 0; k < idx.length; k++) {
            try {
              if (list.length != idx.length || list[k] is! Map) {
                throw const FormatException('Invalid weather response');
              }
              results[idx[k]] = _parse(
                (list[k] as Map).cast<String, dynamic>(),
              );
            } catch (e) {
              results[idx[k]] = e;
            }
          }
        } catch (e) {
          for (final i in idx) {
            results[i] = e;
          }
        }
      }
    }
    return results;
  }

  WeatherSnapshot _parse(Map<String, dynamic> raw) {
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
