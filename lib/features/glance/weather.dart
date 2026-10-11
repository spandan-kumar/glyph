import 'glance_model.dart';

enum WeatherFreshness { fresh, stale, unavailable }

/// One forecast day in the place's own calendar (`date` is `YYYY-MM-DD`).
class DailyForecast {
  const DailyForecast(this.date, this.high, this.low, this.code);
  final String date;
  final double high, low;
  final int code;
  Map<String, Object> toJson() => {'d': date, 'h': high, 'l': low, 'c': code};
  factory DailyForecast.fromJson(Map m) {
    final v = DailyForecast(
      m['d'] as String,
      (m['h'] as num).toDouble(),
      (m['l'] as num).toDouble(),
      (m['c'] as num).toInt(),
    );
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v.date) ||
        !_validTemp(v.high) ||
        !_validTemp(v.low) ||
        !validWeatherCode(v.code)) {
      throw const FormatException('Invalid forecast day');
    }
    return v;
  }

  /// Three-letter weekday, from the civil date.
  String get weekday {
    final p = date.split('-').map(int.parse).toList();
    return const [
      'MON',
      'TUE',
      'WED',
      'THU',
      'FRI',
      'SAT',
      'SUN',
    ][DateTime.utc(p[0], p[1], p[2]).weekday - 1];
  }
}

/// One forecast hour; `time` is the UTC instant it starts.
class HourlyForecast {
  const HourlyForecast(this.time, this.celsius, this.code);
  final DateTime time;
  final double celsius;
  final int code;
  Map<String, Object> toJson() => {
    't': time.toUtc().toIso8601String(),
    'c': celsius,
    'w': code,
  };
  factory HourlyForecast.fromJson(Map m) {
    final v = HourlyForecast(
      DateTime.parse(m['t'] as String),
      (m['c'] as num).toDouble(),
      (m['w'] as num).toInt(),
    );
    if (!_validTemp(v.celsius) || !validWeatherCode(v.code)) {
      throw const FormatException('Invalid forecast hour');
    }
    return v;
  }
}

bool _validTemp(double v) => v.isFinite && v >= -100 && v <= 70;

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
    this.days = const [],
    this.hours = const [],
  });
  final DateTime observed, fetched;
  final double celsius;
  final int code;
  final bool isDay;
  final double? high, low;
  final String? forecastDay;
  final int utcOffsetSeconds;

  /// Today and the next days, and the current and next hours. Empty when the
  /// response had none (or an older cached reading predates them).
  final List<DailyForecast> days;
  final List<HourlyForecast> hours;
  bool get hasForecast => days.isNotEmpty || hours.isNotEmpty;

  String placeToday(DateTime now) {
    final local = now.toUtc().add(Duration(seconds: utcOffsetSeconds));
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  /// Days from the place's today onwards, at most [count].
  List<DailyForecast> upcomingDays(DateTime now, int count) {
    final today = placeToday(now);
    return [
      for (final d in days)
        if (d.date.compareTo(today) >= 0) d,
    ].take(count).toList();
  }

  /// The next [count] hours that start after [now].
  List<HourlyForecast> nextHours(DateTime now, int count) => [
    for (final h in hours)
      if (h.time.isAfter(now.toUtc())) h,
  ].take(count).toList();

  /// "15h" in the place's local time ("20:30" in half-hour zones).
  String hourLabel(HourlyForecast h) {
    final l = h.time.toUtc().add(Duration(seconds: utcOffsetSeconds));
    return l.minute == 0 ? '${l.hour}h' : '${l.hour}:${l.minute.toString().padLeft(2, '0')}';
  }

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
    if (days.isNotEmpty) 'days': [for (final d in days) d.toJson()],
    if (hours.isNotEmpty) 'hours': [for (final h in hours) h.toJson()],
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
      days: [
        for (final d in m['days'] as List? ?? const [])
          DailyForecast.fromJson(d as Map),
      ],
      hours: [
        for (final h in m['hours'] as List? ?? const [])
          HourlyForecast.fromJson(h as Map),
      ],
    );
    if (value.days.length > 7 || value.hours.length > 48) {
      throw const FormatException('Invalid forecast');
    }
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
