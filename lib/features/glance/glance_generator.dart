import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../text/fonts.dart';
import '../text/text_render.dart';
import 'air_quality.dart';
import 'glance_model.dart';
import 'weather.dart';

class GlanceCardGenerator extends Generator {
  @override
  int get streamFps => 10;
  GlanceCardGenerator(
    this.card,
    this.feed, {
    this.air,
    String? Function()? region,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       region = region ?? _phoneRegion;
  final GlanceCard card;
  final WeatherFeed feed;
  final AirFeed? air;
  final DateTime Function() now;

  /// The phone's country code, used only to pick the air quality index.
  final String? Function() region;
  @override
  String get id => 'glance:${card.id}';
  @override
  String get name => card.title;
  @override
  bool get liveOnly => true;
  AqiScale get scale => resolveAqiScale(card.aqi, region());
  bool get available {
    switch (card.kind) {
      case GlanceKind.counter:
        return true;
      case GlanceKind.airQuality:
        final s = air?.snapshot(card.place!);
        return s != null &&
            s.hasData(scale) &&
            s.freshness(now(), failed: air!.failed(card.place!)) !=
                WeatherFreshness.unavailable;
      case GlanceKind.weather || GlanceKind.forecast:
        final snapshot = feed.snapshot(card.place!);
        return snapshot != null &&
            (card.kind == GlanceKind.weather || snapshot.hasForecast) &&
            snapshot.freshness(now(), failed: feed.failed(card.place!)) !=
                WeatherFreshness.unavailable;
    }
  }

  @override
  EffectInstance create(int width, int height, int seed) => _CardEffect(this);
}

String? _phoneRegion() => PlatformDispatcher.instance.locale.countryCode;

/// What one card says: a big value and the small texts that follow it.
class _Content {
  _Content(this.value, this.texts, {this.valueColor = 0xe8f6ef, this.icon, this.stale = false});
  final String value;
  final int valueColor;

  /// Small texts; a null colour takes the layout's default.
  final List<(String, int?)> texts;
  final WeatherSnapshot? icon;
  final bool stale;
}

class _CardEffect extends EffectInstance {
  _CardEffect(this.generator);
  final GlanceCardGenerator generator;
  final _text = _CardText();

  _Content _content(DateTime now) {
    final c = generator.card;
    switch (c.kind) {
      case GlanceKind.counter:
        final days = c.days(now);
        final label = days == 0 ? c.title : c.counterLabel(now);
        return _Content(days == 0 ? 'TODAY' : '${days.abs()}', [
          (c.title, null),
          if (label != c.title) (label, null),
        ]);
      case GlanceKind.airQuality:
        final scale = generator.scale, air = generator.air;
        final s = air?.snapshot(c.place!);
        final status =
            s?.freshness(now, failed: air!.failed(c.place!)) ??
            WeatherFreshness.unavailable;
        final value = s?.aqi(scale);
        if (status == WeatherFreshness.unavailable || value == null) {
          return _Content('--', [(c.title, null), ('NO AIR DATA', null)]);
        }
        final level = aqiLevel(scale, value);
        final stale = status == WeatherFreshness.stale;
        return _Content(
          '$value',
          [
            (c.title, null),
            (stale ? 'OLD ${level.word}' : level.word, level.color),
            (scale.label, null),
            if (s!.pm25 != null) ('PM2.5 ${s.pm25!.round()}', null),
          ],
          valueColor: level.color,
          stale: stale,
        );
      case GlanceKind.weather || GlanceKind.forecast:
        var weather = generator.feed.snapshot(c.place!);
        final status =
            weather?.freshness(now, failed: generator.feed.failed(c.place!)) ??
            WeatherFreshness.unavailable;
        final forecast = c.kind == GlanceKind.forecast;
        if (status == WeatherFreshness.unavailable ||
            (forecast && !weather!.hasForecast)) {
          return _Content('--', [
            (c.title, null),
            (forecast ? 'NO FORECAST' : 'NO DATA', null),
          ]);
        }
        weather = weather!;
        final stale = status == WeatherFreshness.stale;
        final fahrenheit = c.fahrenheit;
        final unit = fahrenheit ? 'F' : 'C';
        if (!forecast) {
          final desc = weatherDescription(weather.code);
          final label = stale ? 'OLD $desc' : desc;
          final hiLo =
              weather.high != null && weather.low != null && weather.dailyIsToday(now)
              ? 'H ${_temp(weather.high!, fahrenheit)} L ${_temp(weather.low!, fahrenheit)}'
              : null;
          return _Content(
            '${weather.temperature(fahrenheit).round()}$unit',
            [
              (c.title, null),
              if (label != c.title) (label, null),
              ?(hiLo == null ? null : (hiLo, null)),
            ],
            icon: weather,
            stale: stale,
          );
        }
        // Forecast: today's high/low big; then the next hours and days.
        final today = weather.placeToday(now);
        final day = weather.days.where((d) => d.date == today).firstOrNull;
        final desc = weatherDescription(day?.code ?? weather.code);
        final hours = weather.nextHours(now, 3);
        final next = [
          for (final d in weather.days)
            if (d.date.compareTo(today) > 0) d,
        ].take(3);
        return _Content(
          day == null
              ? '${weather.temperature(fahrenheit).round()}$unit'
              : '${_temp(day.high, fahrenheit)}/${_temp(day.low, fahrenheit)}',
          [
            (c.title, null),
            (stale ? 'OLD $desc' : desc, null),
            if (hours.isNotEmpty)
              (
                [
                  for (final h in hours)
                    '${weather.hourLabel(h)} ${_temp(h.celsius, fahrenheit)}',
                ].join('  '),
                null,
              ),
            if (next.isNotEmpty)
              (
                [
                  for (final d in next)
                    '${d.weekday} ${_temp(d.high, fahrenheit)}/${_temp(d.low, fahrenheit)}',
                ].join('  '),
                null,
              ),
          ],
          icon: weather,
          stale: stale,
        );
    }
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    out.fill(0);
    final content = _content(generator.now());
    final weather = content.icon, stale = content.stale;
    // Strips cycle value, then the small texts; square devices keep the value
    // on top and cycle the small texts below it. Every segment lasts long
    // enough to scroll its whole text.
    if (out.height < 13) {
      final icon = weather != null && out.width < 16;
      final shown = _text.sequence(
        out,
        [
          (content.value, true, content.valueColor, 5.0),
          for (final (text, color) in content.texts)
            (text, false, color ?? 0xe8f6ef, 3.5),
        ],
        0,
        out.height,
        t,
        lead: icon ? 2 : 0,
      );
      if (!shown) {
        _weatherIcon(
          out,
          weather!,
          (out.width - 7) ~/ 2,
          (out.height - 7) ~/ 2,
          t,
        );
      }
    } else {
      var top = 0;
      if (weather != null && out.height >= 24) {
        _weatherIcon(out, weather, (out.width - 7) ~/ 2, 1, t);
        top = 9;
      }
      _text.sequence(
        out,
        [(content.value, true, content.valueColor, 1.0)],
        top,
        out.height - top - 7,
        t,
      );
      final color = stale ? 0xffb347 : 0x80b3bd;
      _text.sequence(
        out,
        [
          for (final (text, c) in content.texts) (text, false, c ?? color, 4.0),
        ],
        out.height - 6,
        5,
        t,
      );
    }
    if (stale) out.set(out.width - 1, 0, 0xffb347);
  }
}

String _temp(double celsius, bool fahrenheit) =>
    '${(fahrenheit ? celsius * 9 / 5 + 32 : celsius).round()}';

class _Fit {
  const _Fit(this.mask, this.scale);
  final TextMask mask;
  final int scale;
  int get width => mask.width * scale;
  int get height => mask.height * scale;
}

/// (text, large, colour, minimum seconds on screen)
typedef _Entry = (String, bool, int, double);

class _CardText {
  static const _hold = 1.5, _speed = 8.0;
  final _fits = <(String, int, int, bool), _Fit>{};

  _Fit _fit(String text, int width, int height, bool large) {
    final k = (text, width, height, large);
    final cached = _fits[k];
    if (cached != null) return cached;
    if (_fits.length >= 48) _fits.clear();
    final fit = fitText(
      [
        [
          [text],
        ],
      ],
      large ? [boldFont, classicFont, tinyFont] : [tinyFont],
      width,
      height,
      maxScale: large ? 6 : 1,
    );
    final font = fit?.font ?? tinyFont;
    return _fits[k] = _Fit(
      TextMask.lines(font, [text], trim: true),
      fit?.scale ?? 1,
    );
  }

  /// A segment shows overflowing text from its start, scrolls to its end and
  /// holds there, so the whole string is always seen before the next segment.
  static double _seconds(_Fit fit, int width, double minimum) {
    final overflow = max(0, fit.width - width);
    return overflow == 0
        ? minimum
        : max(minimum, overflow / _speed + 2 * _hold);
  }

  /// Plays [entries] one after another on a looping clock. The first [lead]
  /// seconds of each loop are left to the caller (returns false then).
  bool sequence(
    Frame out,
    List<_Entry> entries,
    int top,
    int height,
    double t, {
    double lead = 0,
  }) {
    if (height < 1 || entries.isEmpty) return true;
    final fits = [for (final e in entries) _fit(e.$1, out.width, height, e.$2)];
    final spans = [
      for (var i = 0; i < entries.length; i++)
        _seconds(fits[i], out.width, entries[i].$4),
    ];
    final cycle = lead + spans.fold<double>(0, (a, b) => a + b);
    var local = t % cycle - lead;
    if (local < 0) return false;
    var i = 0;
    while (i < entries.length - 1 && local >= spans[i]) {
      local -= spans[i++];
    }
    _paint(out, fits[i], top, height, local, entries[i].$3);
    return true;
  }

  void _paint(
    Frame out,
    _Fit fit,
    int top,
    int height,
    double local,
    int color,
  ) {
    final overflow = max(0, fit.width - out.width);
    final offset = overflow == 0
        ? 0
        : ((local - _hold) * _speed).clamp(0.0, overflow.toDouble()).floor();
    paintMask(
      out,
      fit.mask,
      overflow == 0 ? (out.width - fit.width) ~/ 2 : -offset,
      top + (height - fit.height) ~/ 2,
      fit.scale,
      (x, y, u, ch) => color,
    );
  }
}

// Original seven-pixel geometry; no downloaded icon pack is needed.
void _weatherIcon(
  Frame out,
  WeatherSnapshot weather,
  int ox,
  int oy,
  double t,
) {
  void dot(int x, int y, int color) => out.set(ox + x, oy + y, color);
  final code = weather.code;
  if (code <= 2) {
    for (var y = 1; y <= 5; y++) {
      for (var x = 1; x <= 5; x++) {
        if ((x - 3) * (x - 3) + (y - 3) * (y - 3) <= 4 &&
            (weather.isDay || x <= 3)) {
          dot(x, y, weather.isDay ? 0xffbf47 : 0x99bbff);
        }
      }
    }
    if (weather.isDay) {
      dot(3, 0, 0xffbf47);
      dot(3, 6, 0xffbf47);
      dot(0, 3, 0xffbf47);
      dot(6, 3, 0xffbf47);
    }
    if (code == 0) return;
  }
  for (var y = 2; y <= 4; y++) {
    for (var x = 0; x < 7; x++) {
      if (y >= 3 || x >= 2 && x <= 4) dot(x, y, 0x99aabb);
    }
  }
  if (code == 45 || code == 48) {
    for (var x = 0; x < 7; x += 2) {
      dot(x, 6, 0x7a8999);
    }
  } else if (code >= 51) {
    final snow = code >= 71 && code <= 77 || code == 85 || code == 86;
    for (var x = 1; x < 7; x += 2) {
      dot(x, 5 + ((t * 2).floor() + x) % 2, snow ? 0xffffff : 0x4c91ff);
    }
    if (code >= 95) {
      dot(3, 4, 0xffbf47);
      dot(2, 5, 0xffbf47);
      dot(3, 6, 0xffbf47);
    }
  }
}

class ShowLook {
  ShowLook(
    this.generator, {
    Params? params,
    Palette? palette,
    this.speed = 1,
    bool Function()? available,
  }) : params = params ?? Params.defaultsFor(generator),
       palette = palette ?? paletteById(generator.defaultPalette),
       available = available ?? (() => true);
  final Generator generator;
  final Params params;
  final Palette palette;
  final double speed;
  final bool Function() available;
}

typedef ShowResolver = ShowLook? Function(PhoneShowEntry entry);

class PhoneShowGenerator extends Generator {
  PhoneShowGenerator(this.show, this.resolve, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final PhoneShow show;
  final ShowResolver resolve;

  /// Entry durations run on this wall clock, not on frame time.
  final DateTime Function() now;
  @override
  String get id => 'phone-show:${show.id}';
  @override
  String get name => show.title;
  @override
  bool get liveOnly => true;
  @override
  bool get pauseDuringAlert => true;
  @override
  int get streamFps => show.entries.every((e) => e.kind == ShowEntryKind.card) ? 10 : 40;
  @override
  EffectInstance create(int width, int height, int seed) =>
      _ShowEffect(this, width, height, seed);
}

class _ShowEffect extends EffectInstance {
  _ShowEffect(this.generator, this.width, this.height, this.seed);
  final PhoneShowGenerator generator;
  final int width, height, seed;
  int _index = -1;
  ShowLook? _look;
  EffectInstance? _effect;
  double _elapsed = 0, _effectTime = 0, _retry = 0;
  DateTime? _lastWall;
  final _text = _CardText();

  static const _maxGap = 0.5;

  void _next() {
    final entries = generator.show.entries;
    _look = null;
    _effect = null;
    _elapsed = 0;
    _effectTime = 0;
    for (var checked = 0; checked < entries.length; checked++) {
      _index = (_index + 1) % entries.length;
      final look = generator.resolve(entries[_index]);
      if (look == null || !look.available()) continue;
      _look = look;
      _effect = look.generator.create(width, height, seed);
      return;
    }
    _retry = 3;
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    // Entry time is wall-clock seconds. Rendering stops while an alert has the
    // display (pauseDuringAlert) or playback is paused; a gap that long is
    // not counted, so the entry resumes where it left off.
    final wall = generator.now(), last = _lastWall;
    _lastWall = wall;
    if (last != null) {
      final gap = wall.difference(last).inMicroseconds / 1e6;
      if (gap > 0 && gap <= _maxGap) _elapsed += gap;
    }
    if (_look != null &&
        (!_look!.available() ||
            _elapsed >= generator.show.entries[_index].seconds - 1e-6)) {
      _next();
    }
    if (_look == null) {
      _retry -= dt;
      if (_retry <= 0) _next();
    }
    final look = _look;
    if (look == null) {
      out.fill(0);
      _text.sequence(out, [('--', true, 0xffb347, 1.0)], 0, out.height, t);
      return;
    }
    _effectTime += dt * look.speed;
    _effect!.render(
      out,
      _effectTime,
      dt * look.speed,
      look.params,
      look.palette,
    );
  }
}
