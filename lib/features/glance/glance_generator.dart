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
    // Strips alternate a whole-width value and label; square devices stack them.
    if (out.height < 13) {
      final phase = t % 12;
      if (weather != null && phase < 2 && out.width < 16) {
        _weatherIcon(
          out,
          weather,
          (out.width - 7) ~/ 2,
          (out.height - 7) ~/ 2,
          t,
        );
      } else {
        _text.draw(
          out,
          phase < 7 ? value : ((t / 12).floor().isEven ? c.title : label),
          0,
          out.height,
          phase < 7 ? phase : phase - 7,
          large: phase < 7,
        );
      }
    } else {
      var top = 0;
      if (weather != null && out.height >= 24) {
        _weatherIcon(out, weather, (out.width - 7) ~/ 2, 1, t);
        top = 9;
      }
      _text.draw(out, value, top, out.height - top - 7, t, large: true);
      _text.draw(
        out,
        t % 8 < 4 ? c.title : label,
        out.height - 6,
        5,
        t % 4,
        color: stale ? 0xffb347 : 0x80b3bd,
      );
    }
    if (stale) out.set(out.width - 1, 0, 0xffb347);
  }
}

class _CardText {
  final _masks = <String, TextMask>{};
  void draw(
    Frame out,
    String text,
    int top,
    int height,
    double t, {
    bool large = false,
    int color = 0xe8f6ef,
  }) {
    if (height < 1) return;
    final fit = fitText(
      [
        [
          [text],
        ],
      ],
      large ? [boldFont, classicFont, tinyFont] : [tinyFont],
      out.width,
      height,
      maxScale: large ? 6 : 1,
    );
    final font = fit?.font ?? tinyFont, scale = fit?.scale ?? 1;
    final key = '${font.id}:$text';
    if (_masks.length >= 16 && !_masks.containsKey(key)) _masks.clear();
    final mask = _masks.putIfAbsent(
      key,
      () => TextMask.lines(font, [text], trim: true),
    );
    final w = mask.width * scale, h = mask.height * scale;
    // Begin with visible letters; hold at either end of overflowing text.
    final overflow = max(0, w - out.width);
    final period = overflow / 8 + 3;
    final offset = ((t % period - 1.5) * 8)
        .clamp(0.0, overflow.toDouble())
        .floor();
    paintMask(
      out,
      mask,
      overflow == 0 ? (out.width - w) ~/ 2 : -offset,
      top + (height - h) ~/ 2,
      scale,
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
  PhoneShowGenerator(this.show, this.resolve);
  final PhoneShow show;
  final ShowResolver resolve;
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
  final _text = _CardText();

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
    _elapsed += dt;
    if (_look != null &&
        (!_look!.available() ||
            _elapsed >= generator.show.entries[_index].seconds)) {
      _next();
    }
    if (_look == null) {
      _retry -= dt;
      if (_retry <= 0) _next();
    }
    final look = _look;
    if (look == null) {
      out.fill(0);
      _text.draw(out, '--', 0, out.height, t, large: true, color: 0xffb347);
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
