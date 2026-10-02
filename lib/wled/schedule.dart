/// Time-based preset triggers ("timers") and the boot preset, which WLED runs
/// on its own clock without the phone.
///
/// Read from GET /json/cfg and written with a partial POST /json/cfg:
/// `{"timers":{"ins":[…]}}` clears and re-adds every timer, `{"def":{"ps":n}}`
/// sets the boot preset (wled/WLED v16.0.1 wled00/cfg.cpp deserializeConfig,
/// serializeConfig; wled_server.cpp "/json" handler). The format below is the
/// v16 one (cfg "vid" ≥ 2605010): sunrise is hour 255 and sunset hour 254
/// (fcn_declare.h TH_SUNRISE/TH_SUNSET). Older firmware used fixed slots with
/// hour 255 for both, so editing is only offered on v16+.
library;

enum TimerTrigger { time, everyHour, sunrise, sunset }

class WledTimer {
  const WledTimer({
    required this.presetId,
    this.enabled = true,
    this.hour = 8,
    this.minute = 0,
    this.weekdays = allDays,
    this.startMonth = 1,
    this.startDay = 1,
    this.endMonth = 12,
    this.endDay = 31,
  });

  static const sunriseHour = 255;
  static const sunsetHour = 254;
  static const everyHourValue = 24;

  /// Bit 0 = Monday … bit 6 = Sunday (ntp.cpp checkTimers shifts the stored
  /// mask by weekdayMondayFirst()).
  static const allDays = 0x7F;
  static const weekdaysOnly = 0x1F;
  static const weekend = 0x60;

  /// Sunrise/sunset offsets are clamped to ±120 min (ntp.cpp addTimer).
  static const maxSunOffset = 120;

  final int presetId;
  final bool enabled;

  /// 0–23, [everyHourValue], [sunriseHour] or [sunsetHour].
  final int hour;

  /// 0–59, or the offset in minutes for sunrise/sunset.
  final int minute;
  final int weekdays;
  final int startMonth, startDay, endMonth, endDay;

  TimerTrigger get trigger => switch (hour) {
    sunriseHour => TimerTrigger.sunrise,
    sunsetHour => TimerTrigger.sunset,
    everyHourValue => TimerTrigger.everyHour,
    _ => TimerTrigger.time,
  };

  bool get isSunBased => trigger == TimerTrigger.sunrise || trigger == TimerTrigger.sunset;

  /// WLED skips the date check when the start month or day is 0
  /// (ntp.cpp isTodayInDateRange).
  bool get allYear =>
      startMonth == 0 ||
      startDay == 0 ||
      (startMonth == 1 && startDay == 1 && endMonth == 12 && endDay == 31);

  bool runsOn(int weekday) => (weekdays >> (weekday - 1)) & 1 == 1;

  WledTimer copyWith({
    int? presetId,
    bool? enabled,
    int? hour,
    int? minute,
    int? weekdays,
    int? startMonth,
    int? startDay,
    int? endMonth,
    int? endDay,
  }) => WledTimer(
    presetId: presetId ?? this.presetId,
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    weekdays: weekdays ?? this.weekdays,
    startMonth: startMonth ?? this.startMonth,
    startDay: startDay ?? this.startDay,
    endMonth: endMonth ?? this.endMonth,
    endDay: endDay ?? this.endDay,
  );

  /// Same defaults as cfg.cpp: missing keys become hour 0, min 0, preset 0,
  /// every day, disabled, all year.
  factory WledTimer.fromJson(Map<String, dynamic> j) {
    int i(Object? v, int d) => v is num
        ? v.toInt()
        : v is bool
        ? (v ? 1 : 0)
        : d;
    final start = j['start'] is Map ? (j['start'] as Map) : const {};
    final end = j['end'] is Map ? (j['end'] as Map) : const {};
    return WledTimer(
      presetId: i(j['macro'], 0),
      enabled: i(j['en'], 0) != 0,
      hour: i(j['hour'], 0),
      minute: i(j['min'], 0),
      weekdays: i(j['dow'], allDays) & allDays,
      startMonth: i(start['mon'], 1),
      startDay: i(start['day'], 1),
      endMonth: i(end['mon'], 12),
      endDay: i(end['day'], 31),
    );
  }

  Map<String, dynamic> toJson() => {
    'en': enabled ? 1 : 0,
    'hour': hour,
    'min': isSunBased ? minute.clamp(-maxSunOffset, maxSunOffset) : minute.clamp(0, 59),
    'macro': presetId,
    'dow': weekdays & allDays,
    'start': {'mon': startMonth, 'day': startDay},
    'end': {'mon': endMonth, 'day': endDay},
  };

  /// Rejected by addTimer() on the device, so caught before saving.
  String? validate() {
    if (presetId < 1 || presetId > 250) return 'Pick a preset';
    if (hour > everyHourValue && !isSunBased) return 'Invalid hour';
    if (!isSunBased && (minute < 0 || minute > 59)) return 'Invalid minute';
    if (startMonth > 12 || endMonth > 12) return 'Invalid month';
    if (startDay > 31 || endDay > 31) return 'Invalid day';
    if (weekdays & allDays == 0) return 'Pick at least one day';
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is WledTimer &&
      other.presetId == presetId &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute &&
      other.weekdays == weekdays &&
      other.startMonth == startMonth &&
      other.startDay == startDay &&
      other.endMonth == endMonth &&
      other.endDay == endDay;

  @override
  int get hashCode => Object.hash(
    presetId,
    enabled,
    hour,
    minute,
    weekdays,
    startMonth,
    startDay,
    endMonth,
    endDay,
  );
}

/// The schedule-related parts of the device config.
class WledSchedule {
  const WledSchedule({
    required this.timers,
    this.bootPreset = 0,
    this.ntpEnabled = false,
    this.latitude = 0,
    this.longitude = 0,
    this.configVersion = 0,
  });

  /// WLED_MAX_TIMERS is 16 on ESP8266 and 64 elsewhere (const.h); the app
  /// keeps to the lower limit.
  static const maxTimers = 16;

  /// First cfg "vid" with the v16 timer format (cfg.cpp legacy migration).
  static const v16Vid = 2605010;

  final List<WledTimer> timers;

  /// Applied at power-on; 0 = none (cfg "def"."ps").
  final int bootPreset;
  final bool ntpEnabled;
  final double latitude, longitude;
  final int configVersion;

  /// Sunrise/sunset need a location in Time & Macros settings.
  bool get hasLocation => latitude != 0 || longitude != 0;

  /// Whether this firmware uses the timer format the app writes.
  bool get isEditable => configVersion >= v16Vid;

  factory WledSchedule.fromConfig(Map<String, dynamic> cfg) {
    Map m(Object? v) => v is Map ? v : const {};
    final vid = cfg['vid'] is num ? (cfg['vid'] as num).toInt() : 0;
    final ins = m(cfg['timers'])['ins'];
    final timers = [
      for (final t in ins is List ? ins : const [])
        if (t is Map) WledTimer.fromJson(t.cast<String, dynamic>()),
    ];
    // Pre-16 configs store sunrise and sunset both as hour 255; the second
    // one is sunset (same migration as cfg.cpp).
    if (vid < v16Vid) {
      var seenSunrise = false;
      for (var i = 0; i < timers.length; i++) {
        if (timers[i].hour != WledTimer.sunriseHour) continue;
        if (seenSunrise) {
          timers[i] = timers[i].copyWith(hour: WledTimer.sunsetHour);
        }
        seenSunrise = true;
      }
    }
    final ntp = m(m(cfg['if'])['ntp']);
    double d(Object? v) => v is num ? v.toDouble() : 0;
    final ps = m(cfg['def'])['ps'];
    return WledSchedule(
      timers: timers,
      bootPreset: ps is num ? ps.toInt() : 0,
      ntpEnabled: ntp['en'] == true,
      latitude: d(ntp['lt']),
      longitude: d(ntp['ln']),
      configVersion: vid,
    );
  }

  /// Body for POST /json/cfg replacing every timer.
  static Map<String, dynamic> timersPatch(List<WledTimer> timers) => {
    'timers': {
      'ins': [for (final t in timers) t.toJson()],
    },
  };

  static Map<String, dynamic> bootPresetPatch(int presetId) => {
    'def': {'ps': presetId.clamp(0, 250)},
  };
}
