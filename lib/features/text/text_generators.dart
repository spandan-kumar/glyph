import 'dart:math';

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import 'fonts.dart';
import 'text_render.dart';
import 'text_settings.dart';

const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

String _two(int v) => v.toString().padLeft(2, '0');

/// Hour, minute and second strings. 24h hours are zero-padded, 12h are not.
({String hh, String mm, String ss, String ampm}) clockParts(DateTime t,
    {required bool hour24}) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return (
    hh: hour24 ? _two(t.hour) : '$h12',
    mm: _two(t.minute),
    ss: _two(t.second),
    ampm: t.hour < 12 ? 'AM' : 'PM',
  );
}

/// Layout candidates for [fitText], most detailed first.
List<List<List<String>>> clockGroups(({String hh, String mm, String ss, String ampm}) p,
        {required bool seconds}) =>
    [
      if (seconds) [
        ['${p.hh}:${p.mm}:${p.ss}'],
        ['${p.hh}:${p.mm}', p.ss],
        [p.hh, p.mm, p.ss],
      ],
      [
        ['${p.hh}:${p.mm}'],
        [p.hh, p.mm],
      ],
    ];

/// Date line options, longest first.
List<String> dateVariants(DateTime t, {String suffix = ''}) {
  final wd = _weekdays[t.weekday - 1], mo = _months[t.month - 1];
  final sfx = suffix.isEmpty ? '' : ' $suffix';
  return [
    '$wd ${t.day} $mo$sfx',
    '$wd ${t.day}$sfx',
    '${t.day} $mo',
    '$wd ${t.day}',
    if (suffix.isNotEmpty) suffix,
    wd,
  ];
}

/// Remaining time split into units, rounding seconds up so the display
/// reaches 0 exactly when the countdown ends.
({int d, int h, int m, int s}) splitRemaining(Duration r) {
  final total = r.inMilliseconds <= 0 ? 0 : (r.inMilliseconds / 1000).ceil();
  return (d: total ~/ 86400, h: total % 86400 ~/ 3600, m: total % 3600 ~/ 60, s: total % 60);
}

List<List<List<String>>> countdownGroups(Duration r) {
  final (:d, :h, :m, :s) = splitRemaining(r);
  final mm = _two(m), ss = _two(s), hh = _two(h);
  if (d > 0) {
    return [
      [['${d}d $hh:$mm:$ss'], ['${d}d', '$hh:$mm:$ss']],
      [['${d}d $hh:$mm'], ['${d}d', '$hh:$mm']],
      [['${d}d ${h}h'], ['${d}d', '${h}h']],
      [['${d}d']],
    ];
  }
  if (h > 0) {
    return [
      [['$h:$mm:$ss'], ['$h:$mm', ss]],
      [['$h:$mm'], ['$h', mm]],
      [['${h}h']],
    ];
  }
  if (m > 0) {
    return [
      [['$m:$ss'], ['$m', ss]],
      [['${m}m']],
    ];
  }
  return [
    [['$s']],
  ];
}

/// Where the countdown counts to: a fixed date, or [Duration] from [now].
DateTime countdownTarget(TextSettings s, DateTime now) => s.useDuration || s.target == null
    ? now.add(Duration(seconds: max(1, s.durationSec)))
    : s.target!;

/// Scrolling (or static) text with optional background effect.
class ScrollingText extends Generator {
  ScrollingText(TextSettings settings) : settings = settings.copy();

  final TextSettings settings;

  @override
  String get id => '_text';
  @override
  String get name => settings.text.trim().isEmpty ? 'Text' : settings.text.trim();
  @override
  String get defaultPalette => settings.palette;

  @override
  EffectInstance create(int width, int height, int seed) =>
      TextInstance(settings, width, height);
}

class TextInstance extends EffectInstance {
  TextInstance(this.s, this.w, this.h) : _backdrop = Backdrop(s.background, w, h, s.bgDim) {
    _layout();
  }

  final TextSettings s;
  final int w;
  final int h;
  final Backdrop _backdrop;
  late BitmapFont _font;
  late int _scale;
  TextMask? _mask;
  Scroller? _scroller;
  int _visibleHeight = 0;

  /// True when the text sits still (it fits and the direction is static).
  bool get isStatic => _scroller == null;

  /// Seconds for one full pass of the scroll, or null when static.
  double? get loopSeconds {
    final m = _mask, sc = _scroller;
    if (m == null || sc == null) return null;
    final dist = sc.direction == 'up' ? m.height * _scale + h : m.width * _scale + w;
    return dist / s.pixelsPerSecond;
  }

  void _layout() {
    final fonts = fontFallbacks(s.font);
    _font = fontForHeight(fonts, h);
    final text = s.text.trim();
    if (text.isEmpty) return;
    final top = autoScale(_font, h, s.large);
    final dir = s.direction;

    if (dir == 'static' || dir == 'up') {
      for (var sc = top; sc >= 1; sc--) {
        final oneLine = !text.contains('\n') && _font.measure(text) * sc <= w;
        final lines = oneLine ? [text] : wrapText(_font, text, w ~/ sc);
        final m = TextMask.lines(_font, lines);
        final fits = m.width * sc <= w && _inkHeight(m, sc, lines.length) <= h;
        if (dir == 'static' && fits) {
          _set(m, sc, null);
          return;
        }
        if (dir == 'up' && (m.width * sc <= w || sc == 1)) {
          _set(m, sc, Scroller('up', w, h));
          return;
        }
      }
    }
    final line = TextMask.line(_font, text.replaceAll('\n', '  '));
    _set(line, top, Scroller(dir == 'right' ? 'right' : 'left', w, h));
  }

  int _inkHeight(TextMask m, int sc, int lines) =>
      (m.height - (_font.height - _font.capHeight)) * sc;

  void _set(TextMask m, int sc, Scroller? scroller) {
    _mask = m;
    _scale = sc;
    _scroller = scroller;
    _visibleHeight = _inkHeight(m, sc, 1);
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    _backdrop.render(out, t, dt);
    final m = _mask;
    if (m == null) return;
    final sc = _scroller;
    int ox, oy;
    if (sc == null) {
      ox = (w - m.width * _scale) ~/ 2;
      oy = (h - _visibleHeight) ~/ 2;
    } else {
      sc.advance(dt, s.pixelsPerSecond);
      (ox, oy) = sc.origin(m.width * _scale, sc.direction == 'up' ? m.height * _scale : _visibleHeight);
    }
    paintMask(out, m, ox, oy, _scale, textColorizer(s, w, t), effect: s.effect);
  }
}

/// Draws fixed-format strings (time, countdown) laid out by [fitText], or
/// scrolls them when nothing fits.
class _FittedText {
  _FittedText(this.s, this.w, this.h) : fonts = fontFallbacks(s.font);

  final TextSettings s;
  final int w;
  final int h;
  final List<BitmapFont> fonts;
  String _key = '';
  TextMask? _mask;
  Scroller? _scroller;
  BitmapFont? _scrollFont;
  int _scrollScale = 1;

  /// Draws [groups]; [below] is an optional smaller line under the main text.
  /// Returns the fit (null when scrolling).
  FitChoice? paint(Frame out, List<List<List<String>>> groups, double t, double dt,
      Colorizer color, {List<String> below = const [], String scrollExtra = ''}) {
    final fit = fitText(groups, fonts, w, h, maxScale: s.large ? 6 : 1);
    if (fit == null) {
      _paintScroll(out, '${groups.first.first.join(' ')}$scrollExtra', dt, color);
      return null;
    }
    final key = '${fit.font.id}|${fit.lines.join('\n')}';
    if (key != _key) {
      _key = key;
      _mask = TextMask.lines(fit.font, fit.lines, trim: true);
    }
    final m = _mask!;

    // Optional date line in the tiny font, when there is room.
    TextMask? sub;
    var subScale = 1;
    final room = h - fit.height() - 2;
    if (below.isNotEmpty && room >= tinyFont.capHeight) {
      for (final v in below) {
        for (var sc = min(2, room ~/ tinyFont.capHeight); sc >= 1; sc--) {
          if (tinyFont.measure(v) * sc <= w) {
            sub = TextMask.lines(tinyFont, [v], trim: true);
            subScale = sc;
            break;
          }
        }
        if (sub != null) break;
      }
    }
    final mainH = m.height * fit.scale;
    final subH = sub == null ? 0 : sub.height * subScale + max(2, fit.scale);
    final top = (h - mainH - subH) ~/ 2;
    paintMask(out, m, (w - m.width * fit.scale) ~/ 2, top, fit.scale, color, effect: s.effect);
    if (sub != null) {
      paintMask(out, sub, (w - sub.width * subScale) ~/ 2, top + mainH + max(2, fit.scale),
          subScale, (x, y, u, ch) => scaleColor(max(0, color(x, y, u, 0)), 0.65),
          effect: s.effect);
    }
    return fit;
  }

  void _paintScroll(Frame out, String text, double dt, Colorizer color) {
    final font = _scrollFont ??= fontForHeight(fonts, h);
    _scrollScale = autoScale(font, h, s.large);
    final sc = _scroller ??= Scroller(s.direction == 'right' ? 'right' : 'left', w, h);
    final key = 'scroll|$text';
    if (key != _key) {
      _key = key;
      _mask = TextMask.line(font, text);
    }
    final m = _mask!;
    sc.advance(dt, s.pixelsPerSecond);
    final (ox, oy) = sc.origin(m.width * _scrollScale, font.capHeight * _scrollScale);
    paintMask(out, m, ox, oy, _scrollScale, color, effect: s.effect);
  }
}

/// Point [i] of [n] around the matrix edge, clockwise from top centre.
(int, int) perimeterPoint(int i, int n, int w, int h) {
  final per = 2 * (w + h) - 4;
  var p = ((i / n) * per).floor() % per;
  p = (p + w ~/ 2) % per;
  if (p < w) return (p, 0);
  p -= w;
  if (p < h - 1) return (w - 1, p + 1);
  p -= h - 1;
  if (p < w - 1) return (w - 2 - p, h - 1);
  p -= w - 1;
  return (0, h - 2 - p);
}

class ClockGenerator extends Generator {
  ClockGenerator(TextSettings settings, {DateTime Function()? now})
      : settings = settings.copy(),
        now = now ?? DateTime.now;

  final TextSettings settings;
  final DateTime Function() now;

  @override
  String get id => '_clock';
  @override
  String get name => 'Clock';
  @override
  String get defaultPalette => settings.palette;

  @override
  EffectInstance create(int width, int height, int seed) =>
      _ClockInstance(settings, width, height, now);
}

/// Analog face needs a roughly square matrix of at least 16×16.
bool analogFits(int w, int h) => min(w, h) >= 16 && (w - h).abs() <= min(w, h) ~/ 2;

class _ClockInstance extends EffectInstance {
  _ClockInstance(this.s, this.w, this.h, this.now)
      : _backdrop = Backdrop(s.background, w, h, s.bgDim),
        _text = _FittedText(s, w, h);

  final TextSettings s;
  final int w;
  final int h;
  final DateTime Function() now;
  final Backdrop _backdrop;
  final _FittedText _text;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    _backdrop.render(out, t, dt);
    final n = now();
    final base = textColorizer(s, w, t);
    if (s.analog && analogFits(w, h)) {
      _analog(out, n, base);
      return;
    }
    final parts = clockParts(n, hour24: s.hour24);
    final colonOn = !s.blink || n.millisecond < 500;
    // Reads the mask at call time: paint() swaps it in before drawing.
    int color(int x, int y, double u, int ch) {
      final mask = _text._mask;
      if (!colonOn && mask != null && ch < mask.chars.length && mask.chars[ch] == 0x3A) {
        return -1;
      }
      return base(x, y, u, ch);
    }

    final suffix = s.hour24 ? '' : parts.ampm;
    final below = s.date ? dateVariants(n, suffix: suffix) : [if (suffix.isNotEmpty) suffix];
    final fit = _text.paint(out, clockGroups(parts, seconds: s.seconds), t, dt, color,
        below: below, scrollExtra: s.date ? '  ${dateVariants(n, suffix: suffix).first}' : '');
    // Seconds that didn't fit as digits run around the edge instead.
    if (s.seconds && fit != null && !fit.lines.any((l) => l.endsWith(parts.ss))) {
      final per = 2 * (w + h) - 4;
      final (x, y) = perimeterPoint(n.second * per ~/ 60, per, w, h);
      out.set(x, y, max(0, base(x, y, 0.5, 0)));
    }
  }

  void _analog(Frame out, DateTime n, Colorizer color) {
    final size = min(w, h);
    final cx = (w - 1) / 2, cy = (h - 1) / 2, r = size / 2 - 0.5;
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      final x = (cx + sin(a) * r).round(), y = (cy - cos(a) * r).round();
      final c = max(0, color(x, y, i / 12, i));
      out.set(x, y, i % 3 == 0 ? c : scaleColor(c, 0.35));
    }
    void hand(double a, double len, int ch, double bright) {
      for (var d = 0.0; d <= len; d += 0.4) {
        final x = (cx + sin(a) * d).round(), y = (cy - cos(a) * d).round();
        out.set(x, y, scaleColor(max(0, color(x, y, d / r, ch)), bright));
      }
    }

    final sec = n.second + n.millisecond / 1000;
    hand((n.hour % 12 + n.minute / 60) * pi / 6, r * 0.5, 0, 1);
    hand((n.minute + sec / 60) * pi / 30, r * 0.8, 1, 0.8);
    if (s.seconds) {
      final a = n.second * pi / 30;
      out.set((cx + sin(a) * r * 0.85).round(), (cy - cos(a) * r * 0.85).round(), 0xFF3355);
    }
  }
}

class CountdownGenerator extends Generator {
  CountdownGenerator(TextSettings settings, {DateTime Function()? now})
      : settings = settings.copy(),
        now = now ?? DateTime.now {
    target = countdownTarget(this.settings, this.now());
  }

  final TextSettings settings;
  final DateTime Function() now;
  late final DateTime target;

  @override
  String get id => '_countdown';
  @override
  String get name => 'Timer';
  @override
  String get defaultPalette => settings.palette;

  @override
  EffectInstance create(int width, int height, int seed) =>
      CountdownInstance(settings, width, height, now, target);
}

class CountdownInstance extends EffectInstance {
  CountdownInstance(this.s, this.w, this.h, this.now, this.target)
      : _backdrop = Backdrop(s.background, w, h, s.bgDim),
        _text = _FittedText(s, w, h);

  final TextSettings s;
  final int w;
  final int h;
  final DateTime Function() now;
  final DateTime target;
  final Backdrop _backdrop;
  final _FittedText _text;
  TextInstance? _party;
  double _partyT = 0;

  bool get isCelebrating => _party != null;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final left = target.difference(now());
    if (left.inMilliseconds <= 0) {
      _celebrate(out, dt, p, pal);
      return;
    }
    _backdrop.render(out, t, dt);
    final base = textColorizer(s, w, t);
    final secs = left.inMilliseconds / 1000;
    // The last ten seconds pulse.
    final pulse = secs <= 10 ? 0.55 + 0.45 * cos((secs - secs.floor()) * 2 * pi) : 1.0;
    _text.paint(out, countdownGroups(left), t, dt,
        (x, y, u, ch) => scaleColor(base(x, y, u, ch), pulse));
  }

  void _celebrate(Frame out, double dt, Params p, Palette pal) {
    final party = _party ??= TextInstance(
      TextSettings.fromJson({
        ...s.toJson(),
        'text': s.doneText.trim().isEmpty ? 'Time!' : s.doneText,
        'colorMode': 'rainbow',
        'direction': 'static',
        'background': 'fireworks',
        'bgDim': 0.9,
        'effect': 'outline',
      }),
      w,
      h,
    );
    _partyT += dt;
    party.render(out, _partyT, dt, p, pal);
    if (_partyT < 0.8) {
      final f = 1 - _partyT / 0.8;
      for (var i = 0; i < out.rgb.length; i++) {
        out.rgb[i] = (out.rgb[i] + (255 - out.rgb[i]) * f).toInt();
      }
    }
  }
}
