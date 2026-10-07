import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glance_model.dart';
import 'weather.dart';
import 'weather_api.dart';

/// Shared, owner-scoped refresh. Rendering never performs network work.
class WeatherService extends ChangeNotifier implements WeatherFeed {
  WeatherService({
    WeatherApi? api,
    DateTime Function()? now,
    this.tickInterval = const Duration(minutes: 1),
  }) : api = api ?? WeatherApi(now: now),
       _now = now ?? DateTime.now;
  final WeatherApi api;
  final DateTime Function() _now;
  final Duration tickInterval;
  static const cadence = Duration(minutes: 15);
  static const _cacheKey = 'glance.weather.v1';
  final _cache = <String, WeatherSnapshot>{};
  final _owners = <Object, List<WeatherPlace>>{};
  final _pending = <String, Future<void>>{};
  final _lastAttempt = <String, DateTime>{};
  final _next = <String, DateTime>{};
  final _failures = <String, int>{};
  final _errors = <String>{};
  final _used = <String, int>{};
  int _useClock = 0;
  Timer? _timer, _retryTimer;
  bool _disposed = false;
  Future<void> _writing = Future.value();

  @override
  WeatherSnapshot? snapshot(WeatherPlace place) {
    final value = _cache[place.key];
    if (value != null) _used[place.key] = ++_useClock;
    return value;
  }

  @override
  bool failed(WeatherPlace place) => _errors.contains(place.key);
  bool refreshing(WeatherPlace place) => _pending.containsKey(place.key);
  WeatherFreshness freshness(WeatherPlace place) =>
      snapshot(place)?.freshness(_now(), failed: failed(place)) ??
      WeatherFreshness.unavailable;
  bool get isWatching => _owners.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.length > 256 * 1024 || _disposed) return;
    try {
      final data = jsonDecode(raw) as Map;
      for (final e in data.entries.take(32)) {
        try {
          final value = WeatherSnapshot.fromJson(e.value as Map);
          if (value.freshness(_now()) != WeatherFreshness.unavailable) {
            final key = e.key as String, existing = _cache[e.key];
            if (existing == null || existing.fetched.isBefore(value.fetched)) {
              _cache[key] = value;
            }
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
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  void _tick() {
    if (_disposed) return;
    final places = {
      for (final list in _owners.values)
        for (final p in list) p.key: p,
    };
    final due = [
      for (final p in places.values)
        if (!_pending.containsKey(p.key) && _due(p, force: false)) p,
    ];
    if (due.isNotEmpty) _start(due);
    // Expiry changes UI status even if refresh is backing off.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  bool _due(WeatherPlace place, {required bool force}) {
    final key = place.key, next = _next[key], cached = _cache[key];
    if (!force && next != null && _now().isBefore(next)) return false;
    if (!force &&
        cached != null &&
        !_errors.contains(key) &&
        _now().difference(cached.fetched) < cadence) {
      return false;
    }
    // Explicit retries also have a one-minute floor.
    if (force &&
        _lastAttempt[key] != null &&
        _now().difference(_lastAttempt[key]!) < const Duration(minutes: 1)) {
      return false;
    }
    return true;
  }

  Future<void> refresh(WeatherPlace place, {bool force = false}) {
    if (_disposed || !place.valid) return Future.value();
    final pending = _pending[place.key];
    if (pending != null) return pending;
    if (!_due(place, force: force)) return Future.value();
    return _start([place]);
  }

  void _pruneAttempts() {
    // Only forget attempts whose backoff window has passed, so eviction never
    // resets an active backoff.
    final now = _now();
    for (final k in _lastAttempt.keys.toList()) {
      if (_lastAttempt.length < 64) break;
      final next = _next[k];
      if (_pending.containsKey(k) || (next != null && now.isBefore(next))) {
        continue;
      }
      _lastAttempt.remove(k);
      _next.remove(k);
    }
  }

  Future<void> _start(List<WeatherPlace> places) {
    final now = _now();
    for (final p in places) {
      if (_lastAttempt.length >= 64 && !_lastAttempt.containsKey(p.key)) {
        _pruneAttempts();
      }
      _lastAttempt[p.key] = now;
    }
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
          for (var i = 0; i < places.length; i++) {
            final r = i < results.length ? results[i] : null;
            if (r is WeatherSnapshot) {
              _store(places[i].key, r);
            } else {
              _fail(places[i].key, r);
            }
          }
          _scheduleRetry();
          if (results.any((r) => r is WeatherSnapshot)) {
            try {
              await _save();
            } catch (_) {}
          }
        })
        .whenComplete(() {
          for (final p in places) {
            _pending.remove(p.key);
          }
          if (!_disposed) notifyListeners();
        });
    for (final p in places) {
      _pending[p.key] = work;
    }
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
    return work;
  }

  void _store(String key, WeatherSnapshot value) {
    if (_cache.length >= 32 && !_cache.containsKey(key)) {
      final watched = {
        for (final l in _owners.values)
          for (final p in l) p.key,
      };
      String? victim;
      for (final k in _cache.keys) {
        final better =
            victim == null ||
            (watched.contains(victim) && !watched.contains(k)) ||
            (watched.contains(victim) == watched.contains(k) &&
                (_used[k] ?? 0) < (_used[victim] ?? 0));
        if (better) victim = k;
      }
      if (victim != null) {
        _cache.remove(victim);
        _used.remove(victim);
      }
    }
    _cache[key] = value;
    _used[key] = ++_useClock;
    _errors.remove(key);
    _failures.remove(key);
    _next[key] = _now().add(cadence);
  }

  /// With a good cached value, retry slowly (15/30/60 min); with none the
  /// card shows no data, so retry quickly (10 s, 30 s, 60 s, then 15 min).
  /// A 429's Retry-After is honoured when longer.
  void _fail(String key, Object? error) {
    _errors.add(key);
    final failures = ((_failures[key] ?? 0) + 1).clamp(1, 4);
    _failures[key] = failures;
    var wait = _cache.containsKey(key)
        ? Duration(minutes: 15 * (1 << (failures.clamp(1, 3) - 1)))
        : const [
            Duration(seconds: 10),
            Duration(seconds: 30),
            Duration(seconds: 60),
            cadence,
          ][failures - 1];
    if (error is WeatherHttpException &&
        error.retryAfter != null &&
        error.retryAfter! > wait) {
      wait = error.retryAfter!;
    }
    _next[key] = _now().add(wait);
  }

  /// The periodic tick is a minute apart; short backoffs need their own wake-up.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_owners.isEmpty) return;
    final now = _now();
    Duration? soonest;
    for (final list in _owners.values) {
      for (final p in list) {
        final next = _next[p.key];
        if (next == null || !next.isAfter(now)) {
          continue;
        }
        final d = next.difference(now);
        if (d < tickInterval && (soonest == null || d < soonest)) soonest = d;
      }
    }
    if (soonest != null) {
      _retryTimer = Timer(soonest + const Duration(milliseconds: 50), _tick);
    }
  }

  Future<void> _save() {
    final raw = jsonEncode({
      for (final e in _cache.entries) e.key: e.value.toJson(),
    });
    _writing = _writing.catchError((_) {}).then((_) async {
      final p = await SharedPreferences.getInstance();
      await p.setString(_cacheKey, raw);
    });
    return _writing;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _retryTimer?.cancel();
    _owners.clear();
    api.dispose();
    super.dispose();
  }
}
