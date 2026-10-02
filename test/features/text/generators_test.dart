import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/gif_baker.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/features/text/fonts.dart';
import 'package:glyph/features/text/text_generators.dart';
import 'package:glyph/features/text/text_render.dart';
import 'package:glyph/features/text/text_settings.dart';

const sizes = [(16, 16), (32, 8), (8, 8), (32, 32)];

int lit(Frame f) {
  var n = 0;
  for (var i = 0; i < f.pixelCount; i++) {
    if (f.get(i % f.width, i ~/ f.width) != 0) n++;
  }
  return n;
}

/// Renders [seconds] and returns the frame with the most lit pixels.
Frame run(Generator g, int w, int h, {double seconds = 2, Params? p}) {
  final inst = g.create(w, h, 1);
  final out = Frame(w, h);
  Frame best = out.copy();
  for (var i = 0; i < seconds * 20; i++) {
    inst.render(out, i / 20, 0.05, p ?? Params({}), palettes.first);
    if (lit(out) > lit(best)) best = out.copy();
  }
  return best;
}

String ascii(Frame f) => [
      for (var y = 0; y < f.height; y++)
        [for (var x = 0; x < f.width; x++) f.get(x, y) == 0 ? '.' : '#'].join(),
    ].join('\n');

void main() {
  final fixed = DateTime(2026, 10, 2, 9, 41, 7);

  group('rendering at every size', () {
    final variants = <String, TextSettings>{
      'plain': TextSettings(text: 'Hello Glyph'),
      'static': TextSettings(text: 'Hi', direction: 'static'),
      'up': TextSettings(text: 'Happy Birthday', direction: 'up'),
      'right rainbow': TextSettings(text: 'On Air', direction: 'right', colorMode: 'rainbow'),
      'gradient outline bg': TextSettings(
          text: 'Open', colorMode: 'gradient', effect: 'outline', background: 'plasma'),
      'animated shadow': TextSettings(text: '♥ ★ °', colorMode: 'animated', effect: 'shadow'),
      'tiny': TextSettings(text: 'tiny text 123', font: 'tiny'),
      'bold': TextSettings(text: 'BOLD', font: 'bold', large: false),
    };
    for (final (w, h) in sizes) {
      for (final MapEntry(:key, :value) in variants.entries) {
        test('text $key at ${w}x$h', () {
          expect(lit(run(ScrollingText(value), w, h)), greaterThan(0));
        });
      }
      test('clock variants at ${w}x$h', () {
        for (final s in [
          TextSettings(),
          TextSettings(hour24: false, seconds: true),
          TextSettings(seconds: true, date: false, font: 'tiny'),
          TextSettings(analog: true, seconds: true),
        ]) {
          expect(lit(run(ClockGenerator(s, now: () => fixed), w, h)), greaterThan(0));
        }
      });
      test('countdown at ${w}x$h', () {
        for (final secs in [5, 125, 3 * 3600 + 7, 2 * 86400 + 3600]) {
          final s = TextSettings(durationSec: secs);
          expect(lit(run(CountdownGenerator(s, now: () => fixed), w, h)), greaterThan(0),
              reason: '$secs s');
        }
      });
    }
  });

  test('empty text renders blank without throwing', () {
    expect(lit(run(ScrollingText(TextSettings(text: '  ')), 16, 16)), 0);
  });

  test('static text that fits is centred and does not move', () {
    final g = ScrollingText(TextSettings(text: 'Hi', direction: 'static', large: false));
    final inst = g.create(16, 16, 1) as TextInstance;
    expect(inst.isStatic, isTrue);
    final a = Frame(16, 16), b = Frame(16, 16);
    inst.render(a, 0, 0.05, Params({}), palettes.first);
    inst.render(b, 3, 3, Params({}), palettes.first);
    expect(b.rgb, a.rgb);
    // "Hi" = 5 + 1 + 1 px wide in classic, centred → columns 4..10.
    final cols = {for (var i = 0; i < 256; i++) if (a.get(i % 16, i ~/ 16) != 0) i % 16};
    expect(cols.reduce((x, y) => x < y ? x : y), 4);
    expect(cols.reduce((x, y) => x > y ? x : y), 10);
  });

  test('scrolling text moves and loops', () {
    final inst = ScrollingText(TextSettings(text: 'Hello world', speed: 0.5)).create(16, 16, 1)
        as TextInstance;
    expect(inst.isStatic, isFalse);
    expect(inst.loopSeconds, greaterThan(1));
    final a = Frame(16, 16), b = Frame(16, 16);
    inst.render(a, 0, 1.0, Params({}), palettes.first);
    inst.render(b, 0, 0.3, Params({}), palettes.first);
    expect(b.rgb, isNot(a.rgb));
  });

  test('large text scales up on 32x32', () {
    final small = run(ScrollingText(TextSettings(text: 'A', direction: 'static', large: false)), 32, 32);
    final big = run(ScrollingText(TextSettings(text: 'A', direction: 'static')), 32, 32);
    expect(lit(big), greaterThan(lit(small) * 4));
  });

  group('clock formatting', () {
    test('24h pads hours, 12h does not', () {
      final p24 = clockParts(fixed, hour24: true);
      expect('${p24.hh}:${p24.mm}:${p24.ss}', '09:41:07');
      final p12 = clockParts(DateTime(2026, 1, 1, 21, 5), hour24: false);
      expect('${p12.hh}:${p12.mm} ${p12.ampm}', '9:05 PM');
      expect(clockParts(DateTime(2026, 1, 1, 0, 0), hour24: false).hh, '12');
      expect(clockParts(DateTime(2026, 1, 1, 12, 0), hour24: false).ampm, 'PM');
    });

    test('fits one line on 32x8, stacks on 16x16, scrolls on 8x8', () {
      final groups = clockGroups(clockParts(fixed, hour24: true), seconds: false);
      final wide = fitText(groups, fontFallbacks('classic'), 32, 8)!;
      expect(wide.lines, ['09:41']);
      expect(wide.font, classicFont);
      final square = fitText(groups, fontFallbacks('classic'), 16, 16)!;
      expect(square.lines, ['09', '41']);
      expect(square.font, classicFont);
      expect(fitText(groups, fontFallbacks('classic'), 8, 8), isNull);
      final big = fitText(groups, fontFallbacks('bold'), 32, 32)!;
      expect(big.scale, 2);
      expect(big.lines, ['09', '41']);
    });

    test('seconds drop to the tiny font, or off, when space is short', () {
      final groups = clockGroups(clockParts(fixed, hour24: true), seconds: true);
      final wide = fitText(groups, fontFallbacks('classic'), 32, 8)!;
      expect(wide.lines, ['09:41:07']);
      expect(wide.font, tinyFont);
      final square = fitText(groups, fontFallbacks('classic'), 16, 16)!;
      expect(square.lines, ['09', '41']);
    });

    test('date variants shrink', () {
      final v = dateVariants(fixed, suffix: 'AM');
      expect(v.first, 'FRI 2 OCT AM');
      expect(v.last, 'FRI');
    });

    test('perimeter points stay on the edge', () {
      for (var i = 0; i < 60; i++) {
        final (x, y) = perimeterPoint(i, 60, 16, 16);
        expect(x == 0 || y == 0 || x == 15 || y == 15, isTrue);
        expect(x, inInclusiveRange(0, 15));
        expect(y, inInclusiveRange(0, 15));
      }
      expect(perimeterPoint(0, 60, 16, 16), (8, 0));
    });
  });

  group('countdown math', () {
    test('splits and rounds seconds up', () {
      expect(splitRemaining(const Duration(days: 2, hours: 3, minutes: 4, seconds: 5)),
          (d: 2, h: 3, m: 4, s: 5));
      expect(splitRemaining(const Duration(milliseconds: 4100)), (d: 0, h: 0, m: 0, s: 5));
      expect(splitRemaining(const Duration(milliseconds: 59500)), (d: 0, h: 0, m: 1, s: 0));
      expect(splitRemaining(-const Duration(seconds: 3)), (d: 0, h: 0, m: 0, s: 0));
    });

    test('labels by magnitude', () {
      expect(countdownGroups(const Duration(seconds: 9)).first.first, ['9']);
      expect(countdownGroups(const Duration(minutes: 4, seconds: 5)).first.first, ['4:05']);
      expect(countdownGroups(const Duration(hours: 3, minutes: 4, seconds: 5)).first.first, ['3:04:05']);
      expect(countdownGroups(const Duration(days: 1, hours: 2)).first.first, ['1d 02:00:00']);
    });

    test('target from duration or date', () {
      final now = DateTime(2026, 1, 1);
      expect(countdownTarget(TextSettings(durationSec: 90), now), now.add(const Duration(seconds: 90)));
      final t = DateTime(2026, 12, 31, 23, 59);
      expect(countdownTarget(TextSettings(useDuration: false, target: t), now), t);
    });

    test('celebrates at zero', () {
      var clock = DateTime(2026, 1, 1, 0, 0, 0);
      final g = CountdownGenerator(TextSettings(durationSec: 2, doneText: 'Go!'), now: () => clock);
      final inst = g.create(16, 16, 1) as CountdownInstance;
      final out = Frame(16, 16);
      inst.render(out, 0, 0.05, Params({}), palettes.first);
      expect(inst.isCelebrating, isFalse);
      clock = clock.add(const Duration(seconds: 3));
      for (var i = 0; i < 40; i++) {
        inst.render(out, i * 0.05, 0.05, Params({}), palettes.first);
      }
      expect(inst.isCelebrating, isTrue);
      expect(lit(out), greaterThan(0));
    });
  });

  test('wrapText splits words and long words', () {
    expect(wrapText(classicFont, 'Happy Birthday', 32), ['Happy', 'Birthd', 'ay']);
    final lines = wrapText(classicFont, 'Happy Birthday', 16);
    expect(lines.every((l) => classicFont.measure(l) <= 16), isTrue);
    expect(lines.join(), 'HappyBirthday');
    expect(wrapText(tinyFont, 'HI YOU', 32), ['HI YOU']);
  });

  test('bakes frames for a creation', () {
    final frames = renderFrames(
        generator: ScrollingText(TextSettings(text: 'Bake')),
        params: Params({}),
        palette: palettes.first,
        width: 16,
        height: 16,
        seconds: 1,
        warmup: 0);
    expect(frames.length, 20);
    expect(frames.any((f) => lit(f) > 0), isTrue);
  });

  test('settings JSON round-trip', () {
    final s = TextSettings(
      text: 'Round ♥ trip',
      font: 'bold',
      large: false,
      colorMode: 'animated',
      color: 0x123456,
      palette: 'ocean',
      speed: 0.9,
      direction: 'up',
      background: 'fire',
      bgDim: 0.5,
      effect: 'shadow',
      hour24: false,
      seconds: true,
      blink: false,
      date: false,
      analog: true,
      target: DateTime(2027, 1, 1, 0, 0),
      durationSec: 42,
      useDuration: false,
      doneText: 'Yay',
    );
    final j = jsonDecode(jsonEncode({...s.toJson(), 'mode': 'clock'})) as Map<String, dynamic>;
    final back = TextSettings.fromJson(j);
    expect(back.toJson(), s.toJson());
    expect(TextSettings.fromJson({'speed': 1, 'color': 'bad'}).speed, 1.0);
    expect(TextSettings.fromJson({}).toJson(), TextSettings().toJson());
  });

  test('preview prints', () {
    // Handy when tuning layouts: flutter test --plain-name 'preview prints'
    for (final (w, h) in sizes) {
      for (final g in <Generator>[
        ClockGenerator(TextSettings(font: 'bold', seconds: true), now: () => fixed),
        ClockGenerator(TextSettings(analog: true, seconds: true), now: () => fixed),
        CountdownGenerator(TextSettings(durationSec: 3 * 3600 + 7), now: () => fixed),
        ScrollingText(TextSettings(text: 'Hi', direction: 'static', font: 'bold')),
      ]) {
        final f = run(g, w, h, seconds: 0.1);
        expect(ascii(f).split('\n').length, h);
        // ignore: avoid_print
        if (const bool.fromEnvironment('PRINT')) print('${g.name} ${w}x$h\n${ascii(f)}\n');
      }
    }
  });
}
