import 'glance_model.dart';

enum WeatherFreshness { fresh, stale, unavailable }

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.observed,
    required this.fetched,
    required this.celsius,
    required this.code,
    required this.isDay,
    this.high,
    this.low,
    this.forecastDay,
    this.utcOffsetSeconds = 0,
  });
  final DateTime observed, fetched;
  final double celsius;
  final int code;
  final bool isDay;
  final double? high, low;
  final String? forecastDay;
  final int utcOffsetSeconds;
  bool dailyIsToday(DateTime now) {
    final local = now.toUtc().add(Duration(seconds: utcOffsetSeconds));
    return forecastDay ==
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  double temperature(bool fahrenheit) =>
      fahrenheit ? celsius * 9 / 5 + 32 : celsius;

  /// Fresh readings are 15-minute buckets, so age is measured from when we
  /// fetched (or from the observation plus one bucket, whichever is later).
  static const staleAfter = Duration(minutes: 45);
  WeatherFreshness freshness(DateTime now, {bool failed = false}) {
    final observedAge = now.toUtc().difference(observed.toUtc());
    final fetchAge = now.toUtc().difference(fetched.toUtc());
    if (observedAge < const Duration(minutes: -5) ||
        fetchAge.isNegative ||
        observedAge >= const Duration(hours: 2) ||
        fetchAge >= const Duration(hours: 2)) {
      return WeatherFreshness.unavailable;
    }
    return failed ||
            fetchAge >= staleAfter ||
            observedAge >= staleAfter + const Duration(minutes: 15)
        ? WeatherFreshness.stale
        : WeatherFreshness.fresh;
  }

  Map<String, Object> toJson() => {
    'observed': observed.toUtc().toIso8601String(),
    'fetched': fetched.toUtc().toIso8601String(),
    'temperature': celsius,
    'code': code,
    'day': isDay,
    'high': ?high,
    'low': ?low,
    'forecastDay': ?forecastDay,
    'utcOffset': utcOffsetSeconds,
  };
  factory WeatherSnapshot.fromJson(Map m) {
    final value = WeatherSnapshot(
      observed: DateTime.parse(m['observed'] as String),
      fetched: DateTime.parse(m['fetched'] as String),
      celsius: (m['temperature'] as num).toDouble(),
      code: (m['code'] as num).toInt(),
      isDay: m['day'] as bool,
      high: (m['high'] as num?)?.toDouble(),
      low: (m['low'] as num?)?.toDouble(),
      forecastDay: m['forecastDay'] as String?,
      utcOffsetSeconds: (m['utcOffset'] as num?)?.toInt() ?? 0,
    );
    if (value.utcOffsetSeconds.abs() > 14 * 3600 ||
        (value.forecastDay != null &&
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.forecastDay!)) ||
        !value.celsius.isFinite ||
        value.celsius < -100 ||
        value.celsius > 70 ||
        m['code'] != value.code ||
        !validWeatherCode(value.code) ||
        (value.high != null &&
            (!value.high!.isFinite ||
                value.high! < -100 ||
                value.high! > 70)) ||
        (value.low != null &&
            (!value.low!.isFinite || value.low! < -100 || value.low! > 70))) {
      throw const FormatException('Invalid weather');
    }
    return value;
  }
}

bool validWeatherCode(int code) => const {
  0,
  1,
  2,
  3,
  45,
  48,
  51,
  53,
  55,
  56,
  57,
  61,
  63,
  65,
  66,
  67,
  71,
  73,
  75,
  77,
  80,
  81,
  82,
  85,
  86,
  95,
  96,
  99,
}.contains(code);
String weatherDescription(int code) => switch (code) {
  0 => 'Clear',
  1 || 2 => 'Partly cloudy',
  3 => 'Cloudy',
  45 || 48 => 'Fog',
  >= 51 && <= 57 => 'Drizzle',
  >= 61 && <= 67 || >= 80 && <= 82 => 'Rain',
  >= 71 && <= 77 || 85 || 86 => 'Snow',
  95 || 96 || 99 => 'Thunderstorm',
  _ => 'Unavailable',
};

abstract interface class WeatherFeed {
  WeatherSnapshot? snapshot(WeatherPlace place);
  bool failed(WeatherPlace place);
}
