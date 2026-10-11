import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'air_quality.dart';
import 'glance_model.dart';
import 'weather.dart';
import 'weather_api.dart';

/// Open-Meteo Air Quality API. Shares the bounded, timed HTTP path (and
/// User-Agent) of [WeatherApi]; one request covers up to [maxBatch] places.
class AirQualityApi {
  AirQualityApi(this._http, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final WeatherApi _http;
  final DateTime Function() _now;
  static const maxBatch = 10;

  static String keyFor(WeatherPlace p) => '${p.latitude},${p.longitude}';

  /// Each result is a snapshot or the error for that place.
  Future<List<Object>> fetchMany(List<WeatherPlace> places) async {
    final results = List<Object>.filled(
      places.length,
      const FormatException('Air quality unavailable'),
    );
    for (var s = 0; s < places.length; s += maxBatch) {
      final idx = [for (var i = s; i < places.length && i < s + maxBatch; i++) i];
      try {
        final data = await _http.getJson(
          Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
            'latitude': idx.map((i) => '${places[i].latitude}').join(','),
            'longitude': idx.map((i) => '${places[i].longitude}').join(','),
            'current': 'european_aqi,us_aqi,pm2_5',
            'timeformat': 'unixtime',
          }),
        );
        final list = data is List ? data : [data];
        for (var k = 0; k < idx.length; k++) {
          try {
            if (list.length != idx.length || list[k] is! Map) {
              throw const FormatException('Invalid air quality response');
            }
            results[idx[k]] = parse((list[k] as Map).cast<String, dynamic>());
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
    return results;
  }

  AirSnapshot parse(Map<String, dynamic> raw) {
    final c = raw['current'];
    if (c is! Map || c['time'] is! num) {
      throw const FormatException('Incomplete air quality response');
    }
    int? aqi(String k) => c[k] is num && (c[k] as num).isFinite ? (c[k] as num).round() : null;
    final v = AirSnapshot.fromJson({
      'observed': DateTime.fromMillisecondsSinceEpoch(
        (c['time'] as num).toInt() * 1000,
        isUtc: true,
      ).toIso8601String(),
      'fetched': _now().toUtc().toIso8601String(),
      'us': aqi('us_aqi'),
      'eu': aqi('european_aqi'),
      'pm25': c['pm2_5'] is num && (c['pm2_5'] as num).isFinite ? c['pm2_5'] : null,
    }..removeWhere((_, x) => x == null));
    if (v.freshness(_now()) == WeatherFreshness.unavailable) {
      throw const FormatException('Outdated air quality response');
    }
    return v;
  }
}

/// Owner-scoped refresh, like [WeatherService]: nothing is requested unless
/// an owner is watching a place, and rendering never touches the network.
class AirQualityService extends ChangeNotifier implements AirFeed {
  AirQualityService({
    AirQualityApi? api,
    WeatherApi? http,
    DateTime Function()? now,
    this.tickInterval = const Duration(minutes: 1),
  }) : api = api ?? AirQualityApi(http ?? WeatherApi(now: now), now: now),
       _now = now ?? DateTime.now;
  final AirQualityApi api;
  final DateTime Function() _now;
  final Duration tickInterval;

  /// The model updates hourly; half an hour keeps requests few.
  static const cadence = Duration(minutes: 30);
  static const _cacheKey = 'glance.air.v1';
  final _cache = <String, AirSnapshot>{};
  final _owners = <Object, List<WeatherPlace>>{};
  final _pending = <String, Future<void>>{};
  final _next = <String, DateTime>{};
  final _failures = <String, int>{};
  final _errors = <String>{};
  Timer? _timer;
  bool _disposed = false;
  Future<void> _writing = Future.value();

  @override
  AirSnapshot? snapshot(WeatherPlace place) => _cache[AirQualityApi.keyFor(place)];
  @override
  bool failed(WeatherPlace place) => _errors.contains(AirQualityApi.keyFor(place));
  bool refreshing(WeatherPlace place) => _pending.containsKey(AirQualityApi.keyFor(place));
  bool get isWatching => _owners.isNotEmpty;
  WeatherFreshness freshness(WeatherPlace place) =>
      snapshot(place)?.freshness(_now(), failed: failed(place)) ??
      WeatherFreshness.unavailable;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.length > 64 * 1024 || _disposed) return;
    try {
      for (final e in (jsonDecode(raw) as Map).entries.take(32)) {
        try {
          final v = AirSnapshot.fromJson(e.value as Map);
          if (v.freshness(_now()) != WeatherFreshness.unavailable) {
            _cache[e.key as String] = v;
          }
        } catch (_) {}
      }
    } catch (_) {}
    if (!_disposed) notifyListeners();
  }

  void watch(Object owner, Iterable<WeatherPlace> places) {
    if (_disposed) return;
    final valid = places.where((p) => p.valid).take(24).toList();
    if (valid.isEmpty) {
      release(owner);
      return;
    }
    _owners[owner] = valid;
    _timer ??= Timer.periodic(tickInterval, (_) => _tick());
    _tick();
  }

  void release(Object owner) {
    _owners.remove(owner);
    if (_owners.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _tick() {
    if (_disposed) return;
    final places = {
      for (final l in _owners.values)
        for (final p in l) AirQualityApi.keyFor(p): p,
    };
    final due = [
      for (final e in places.entries)
        if (!_pending.containsKey(e.key) && _due(e.key)) e.value,
    ];
    if (due.isNotEmpty) _start(due);
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  bool _due(String key, {bool force = false}) {
    final next = _next[key];
    if (next != null && _now().isBefore(next)) return false;
    final cached = _cache[key];
    if (!force &&
        cached != null &&
        !_errors.contains(key) &&
        _now().difference(cached.fetched) < cadence) {
      return false;
    }
    return true;
  }

  Future<void> refresh(WeatherPlace place) {
    final key = AirQualityApi.keyFor(place);
    if (_disposed || !place.valid) return Future.value();
    return _pending[key] ?? (_due(key, force: true) ? _start([place]) : Future.value());
  }

  Future<void> _start(List<WeatherPlace> places) {
    final keys = [for (final p in places) AirQualityApi.keyFor(p)];
    Future<List<Object>> request;
    try {
      request = api.fetchMany(places);
    } catch (e) {
      request = Future.value([for (final _ in places) e]);
    }
    final work = request
        .catchError((Object e) => [for (final _ in places) e])
        .then((results) async {
          if (_disposed) return;
          for (var i = 0; i < keys.length; i++) {
            final r = i < results.length ? results[i] : null;
            if (r is AirSnapshot) {
              _cache[keys[i]] = r;
              _errors.remove(keys[i]);
              _failures.remove(keys[i]);
              _next[keys[i]] = _now().add(cadence);
            } else {
              _fail(keys[i], r);
            }
          }
          while (_cache.length > 32) {
            _cache.remove(_cache.keys.first);
          }
          if (results.any((r) => r is AirSnapshot)) {
            try {
              await _save();
            } catch (_) {}
          }
        })
        .whenComplete(() {
          for (final k in keys) {
            _pending.remove(k);
          }
          if (!_disposed) notifyListeners();
        });
    for (final k in keys) {
      _pending[k] = work;
    }
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
    return work;
  }

  /// With a good cached value retry at 30/60/120 minutes; with none, after
  /// 10 s, 30 s, 60 s, then every 30 minutes. A 429's Retry-After wins when
  /// longer.
  void _fail(String key, Object? error) {
    _errors.add(key);
    final n = ((_failures[key] ?? 0) + 1).clamp(1, 4);
    _failures[key] = n;
    var wait = _cache.containsKey(key)
        ? Duration(minutes: 30 * (1 << (n.clamp(1, 3) - 1)))
        : const [
            Duration(seconds: 10),
            Duration(seconds: 30),
            Duration(seconds: 60),
            cadence,
          ][n - 1];
    if (error is WeatherHttpException &&
        error.retryAfter != null &&
        error.retryAfter! > wait) {
      wait = error.retryAfter!;
    }
    _next[key] = _now().add(wait);
  }

  Future<void> _save() {
    final raw = jsonEncode({
      for (final e in _cache.entries) e.key: e.value.toJson(),
    });
    _writing = _writing.catchError((_) {}).then((_) async {
      await (await SharedPreferences.getInstance()).setString(_cacheKey, raw);
    });
    return _writing;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _owners.clear();
    super.dispose();
  }
}
