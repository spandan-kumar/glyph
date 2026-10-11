import 'glance_model.dart';
import 'weather.dart';

/// Which index a card shows. [auto] follows the phone's region.
enum AqiPref { auto, us, eu }

enum AqiScale {
  us('US AQI'),
  eu('EAQI');

  const AqiScale(this.label);
  final String label;
}

/// A qualitative band: the word is always shown next to the colour, so the
/// colour never carries the meaning alone.
class AqiLevel {
  const AqiLevel(this.word, this.color);
  final String word;
  final int color;
}

const _europe = {
  'AD', 'AL', 'AT', 'BA', 'BE', 'BG', 'BY', 'CH', 'CY', 'CZ', 'DE', 'DK', 'EE',
  'ES', 'FI', 'FR', 'GB', 'GR', 'HR', 'HU', 'IE', 'IS', 'IT', 'LI', 'LT', 'LU',
  'LV', 'MC', 'MD', 'ME', 'MK', 'MT', 'NL', 'NO', 'PL', 'PT', 'RO', 'RS', 'SE',
  'SI', 'SK', 'SM', 'UA', 'VA', 'XK',
};

/// European Air Quality Index in Europe, US AQI everywhere else (it is the
/// one with worldwide use). [pref] overrides the region.
AqiScale resolveAqiScale(AqiPref pref, String? countryCode) => switch (pref) {
  AqiPref.us => AqiScale.us,
  AqiPref.eu => AqiScale.eu,
  AqiPref.auto =>
    _europe.contains(countryCode?.toUpperCase()) ? AqiScale.eu : AqiScale.us,
};

AqiLevel aqiLevel(AqiScale scale, int value) {
  if (scale == AqiScale.us) {
    return switch (value) {
      <= 50 => const AqiLevel('Good', 0x3ddc84),
      <= 100 => const AqiLevel('Moderate', 0xffd23f),
      <= 150 => const AqiLevel('Sensitive', 0xff8a3d),
      <= 200 => const AqiLevel('Unhealthy', 0xff4d4d),
      <= 300 => const AqiLevel('Very bad', 0xc77dff),
      _ => const AqiLevel('Hazardous', 0xd0455a),
    };
  }
  return switch (value) {
    <= 20 => const AqiLevel('Good', 0x3ddc84),
    <= 40 => const AqiLevel('Fair', 0xb6e03d),
    <= 60 => const AqiLevel('Moderate', 0xffd23f),
    <= 80 => const AqiLevel('Poor', 0xff8a3d),
    <= 100 => const AqiLevel('Very poor', 0xff4d4d),
    _ => const AqiLevel('Extreme', 0xc77dff),
  };
}

/// Open-Meteo returns `null` for places the model does not cover; that is
/// kept as "no data", never as zero.
class AirSnapshot {
  const AirSnapshot({
    required this.observed,
    required this.fetched,
    this.usAqi,
    this.euAqi,
    this.pm25,
  });
  final DateTime observed, fetched;
  final int? usAqi, euAqi;
  final double? pm25;

  int? aqi(AqiScale scale) => scale == AqiScale.us ? usAqi : euAqi;
  bool hasData(AqiScale scale) => aqi(scale) != null;

  static const staleAfter = Duration(minutes: 90);
  WeatherFreshness freshness(DateTime now, {bool failed = false}) {
    final observedAge = now.toUtc().difference(observed.toUtc());
    final fetchAge = now.toUtc().difference(fetched.toUtc());
    if (observedAge < const Duration(minutes: -5) ||
        fetchAge.isNegative ||
        observedAge >= const Duration(hours: 8) ||
        fetchAge >= const Duration(hours: 6)) {
      return WeatherFreshness.unavailable;
    }
    return failed ||
            fetchAge >= staleAfter ||
            observedAge >= const Duration(hours: 3)
        ? WeatherFreshness.stale
        : WeatherFreshness.fresh;
  }

  Map<String, Object> toJson() => {
    'observed': observed.toUtc().toIso8601String(),
    'fetched': fetched.toUtc().toIso8601String(),
    'us': ?usAqi,
    'eu': ?euAqi,
    'pm25': ?pm25,
  };
  factory AirSnapshot.fromJson(Map m) {
    final v = AirSnapshot(
      observed: DateTime.parse(m['observed'] as String),
      fetched: DateTime.parse(m['fetched'] as String),
      usAqi: (m['us'] as num?)?.toInt(),
      euAqi: (m['eu'] as num?)?.toInt(),
      pm25: (m['pm25'] as num?)?.toDouble(),
    );
    bool bad(int? a) => a != null && (a < 0 || a > 1000);
    if (bad(v.usAqi) ||
        bad(v.euAqi) ||
        (v.pm25 != null && (!v.pm25!.isFinite || v.pm25! < 0 || v.pm25! > 2000))) {
      throw const FormatException('Invalid air quality');
    }
    return v;
  }
}

abstract interface class AirFeed {
  AirSnapshot? snapshot(WeatherPlace place);
  bool failed(WeatherPlace place);
}
