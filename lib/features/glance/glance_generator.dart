import 'dart:math';

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../text/fonts.dart';
import '../text/text_render.dart';
import 'glance_model.dart';
import 'weather.dart';

class GlanceCardGenerator extends Generator {
  GlanceCardGenerator(this.card, this.feed, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final GlanceCard card;
  final WeatherFeed feed;
  final DateTime Function() now;
  @override
  String get id => 'glance:${card.id}';
  @override
  String get name => card.title;
  @override
  bool get liveOnly => true;
  bool get available {
    if (card.kind == GlanceKind.counter) return true;
    final snapshot = feed.snapshot(card.place!);
    return snapshot != null &&
        snapshot.freshness(now(), failed: feed.failed(card.place!)) !=
            WeatherFreshness.unavailable;
  }

  @override
  EffectInstance create(int width, int height, int seed) => _CardEffect(this);
}

class _CardEffect extends EffectInstance {
  _CardEffect(this.generator);
  final GlanceCardGenerator generator;
  final _text = _CardText();
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    out.fill(0);
    final c = generator.card, now = generator.now();
    String value, label;
    WeatherSnapshot? weather;
    var stale = false;
    if (c.kind == GlanceKind.counter) {
      final days = c.days(now);
      value = days == 0 ? 'TODAY' : '${days.abs()}';
      label = days == 0 ? c.title : c.counterLabel(now);
    } else {
      weather = generator.feed.snapshot(c.place!);
      final status =
          weather?.freshness(now, failed: generator.feed.failed(c.place!)) ??
          WeatherFreshness.unavailable;
      if (status == WeatherFreshness.unavailable) {
        value = '--';
        label = 'NO DATA';
        weather = null;
      } else {
        stale = status == WeatherFreshness.stale;
        value =
            '${weather!.temperature(c.fahrenheit).round()}${c.fahrenheit ? 'F' : 'C'}';
        label = stale
            ? 'OLD ${weatherDescription(weather.code)}'
            : weatherDescription(weather.code);
      }
    }
    final hiLo =
        weather != null &&
            weather.high != null &&
            weather.low != null &&
            weather.dailyIsToday(now)
        ? 'H ${_temp(weather.high!, c.fahrenheit)} L ${_temp(weather.low!, c.fahrenheit)}'
        : null;
    // Strips cycle value, title, label (and high/low); square devices keep the
    // value on top and cycle the small texts below it. Every segment lasts
    // long enough to scroll its whole text.
    if (out.height < 13) {
      final icon = weather != null && out.width < 16;
      final shown = _text.sequence(
        out,
        [
          (value, true, 0xe8f6ef, 5.0),
          (c.title, false, 0xe8f6ef, 3.5),
          if (label != c.title) (label, false, 0xe8f6ef, 3.5),
          ?(hiLo == null ? null : (hiLo, false, 0xe8f6ef, 3.5)),
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
        [(value, true, 0xe8f6ef, 1.0)],
        top,
        out.height - top - 7,
        t,
      );
      final color = stale ? 0xffb347 : 0x80b3bd;
      _text.sequence(
        out,
        [
          (c.title, false, color, 4.0),
          if (label != c.title) (label, false, color, 4.0),
          ?(hiLo == null ? null : (hiLo, false, color, 4.0)),
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
