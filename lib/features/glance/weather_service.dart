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
  Timer? _timer;
  bool _disposed = false;
  Future<void> _writing = Future.value();

  @override
  WeatherSnapshot? snapshot(WeatherPlace place) => _cache[place.key];
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
    }
  }

  void _tick() {
    if (_disposed) return;
    final places = {
      for (final list in _owners.values)
        for (final p in list) p.key: p,
    };
    for (final p in places.values) {
      unawaited(refresh(p));
    }
    // Expiry changes UI status even if refresh is backing off.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> refresh(WeatherPlace place, {bool force = false}) {
    if (_disposed || !place.valid) return Future.value();
    final key = place.key, pending = _pending[place.key];
    if (pending != null) return pending;
    final next = _next[key];
    if (!force && next != null && _now().isBefore(next)) return Future.value();
    final cached = _cache[key];
    if (!force &&
        cached != null &&
        !_errors.contains(key) &&
        _now().difference(cached.fetched) < cadence) {
      return Future.value();
    }
    // Explicit retries also have a one-minute floor.
    if (force &&
        _lastAttempt[key] != null &&
        _now().difference(_lastAttempt[key]!) < const Duration(minutes: 1)) {
      return Future.value();
    }
    if (_lastAttempt.length >= 64 && !_lastAttempt.containsKey(key)) {
      final oldest = _lastAttempt.keys.firstWhere(
        (k) => !_pending.containsKey(k),
        orElse: () => '',
      );
      if (oldest.isNotEmpty) {
        _lastAttempt.remove(oldest);
        _next.remove(oldest);
        _failures.remove(oldest);
        _errors.remove(oldest);
      }
    }
    _lastAttempt[key] = _now();
    final work = _fetch(place);
    _pending[key] = work;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
    return work;
  }

  Future<void> _fetch(WeatherPlace place) async {
    final key = place.key;
    try {
      final value = await api.fetch(place);
      if (_disposed) return;
      if (_cache.length >= 32 && !_cache.containsKey(key)) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = value;
      _errors.remove(key);
      _failures.remove(key);
      _next[key] = _now().add(cadence);
      await _save();
    } catch (_) {
      if (!_disposed) {
        _errors.add(key);
        final failures = (_failures[key] ?? 0) + 1;
        _failures[key] = failures.clamp(1, 3);
        _next[key] = _now().add(
          Duration(minutes: 15 * (1 << (failures - 1).clamp(0, 2))),
        );
      }
    } finally {
      _pending.remove(key);
      if (!_disposed) notifyListeners();
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
    _owners.clear();
    api.dispose();
    super.dispose();
  }
}
