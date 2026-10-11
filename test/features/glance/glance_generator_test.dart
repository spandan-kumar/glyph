import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/text/fonts.dart';
import 'package:glyph/features/text/text_render.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/features/glance/glance_generator.dart';
import 'package:glyph/features/glance/glance_model.dart';
import 'package:glyph/features/glance/weather.dart';

class Feed implements WeatherFeed {
  WeatherSnapshot? value;
  bool error = false;
  @override
  WeatherSnapshot? snapshot(WeatherPlace p) => value;
  @override
  bool failed(WeatherPlace p) => error;
}

class Solid extends Generator {
  Solid(this.color);
  final int color;
  final times = <double>[];
  int creates = 0;
  double? parameter;
  @override
  String get id => '$color';
  @override
  String get name => id;
  @override
  EffectInstance create(int w, int h, int seed) {
    creates++;
    return SolidEffect(this);
  }
}

class SolidEffect extends EffectInstance {
  SolidEffect(this.g);
  final Solid g;
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    g.times.add(t);
    g.parameter = p['value'];
    out.fill(g.color);
  }
}

void main() {
  final pal = palettes.first;
  const place = WeatherPlace('Delhi', 28.6, 77.2);
  test(
    'weather and counters light each supported size; unavailable is never zero',
    () {
      final now = DateTime(2026, 10, 7, 12), feed = Feed();
      final weather = GlanceCardGenerator(
        const GlanceCard(
          id: 'w',
          title: 'Weather',
          kind: GlanceKind.weather,
          place: place,
        ),
        feed,
        now: () => now,
      );
      final counter = GlanceCardGenerator(
        GlanceCard(
          id: 'c',
          title: 'Trip',
          kind: GlanceKind.counter,
          date: DateTime(2026, 11, 7),
        ),
        feed,
        now: () => now,
      );
      for (final size in [(8, 8), (32, 8), (16, 16), (32, 32)]) {
        for (final g in [weather, counter]) {
          final out = Frame(size.$1, size.$2),
              effect = g.create(size.$1, size.$2, 7);
          for (final t in [0.0, 3.0, 8.0]) {
            effect.render(out, t, 0.025, Params({}), pal);
            expect(out.rgb.any((v) => v > 0), true, reason: '${g.id} $size $t');
          }
        }
      }
      expect(weather.available, false);
      expect(weather.liveOnly, true);
      feed.value = WeatherSnapshot(
        observed: now,
        fetched: now,
        celsius: 0,
        code: 0,
        isDay: true,
      );
      expect(weather.available, true);
      feed.error = true;
      final out = Frame(16, 16);
      weather.create(16, 16, 1).render(out, 0, 0, Params({}), pal);
      expect(out.get(15, 0), 0xffb347);
    },
  );
  test('counter updates at local midnight without rebuilding the effect', () {
    var now = DateTime(2026, 10, 7, 23, 59);
    final g = GlanceCardGenerator(
      GlanceCard(
        id: 'c',
        title: 'Trip',
        kind: GlanceKind.counter,
        date: DateTime(2026, 10, 8),
      ),
      Feed(),
      now: () => now,
    );
    final effect = g.create(16, 16, 1), out = Frame(16, 16);
    effect.render(out, 0, 0, Params({}), pal);
    final before = out.rgb.toList();
    now = DateTime(2026, 10, 8);
    effect.render(out, 0, 0, Params({}), pal);
    expect(out.rgb.toList(), isNot(before));
  });
  test('Show preserves order, duration, per-look parameters and speed', () {
    final a = Solid(0xff0000), b = Solid(0x00ff00);
    final show = PhoneShow(
      id: 's',
      title: 'Show',
      entries: [
        const PhoneShowEntry(ShowEntryKind.library, 'a', seconds: 3),
        const PhoneShowEntry(ShowEntryKind.library, 'b', seconds: 5),
      ],
    );
    var wall = DateTime(2026, 10, 7, 12);
    final g = PhoneShowGenerator(
      show,
      (e) => e.id == 'a'
          ? ShowLook(a, params: Params({'value': 0.8}), speed: 2)
          : ShowLook(b),
      now: () => wall,
    );
    final effect = g.create(8, 8, 1), out = Frame(8, 8);
    void step(double seconds, double dt) {
      wall = wall.add(Duration(milliseconds: (seconds * 1000).round()));
      effect.render(out, 0, dt, Params({}), pal);
    }

    step(0, 0);
    expect(out.get(0, 0), a.color);
    // Frame dt (clamped, time-scaled) does not decide when an entry ends.
    for (var i = 0; i < 29; i++) {
      step(0.1, 0.1);
    }
    expect(out.get(0, 0), a.color);
    expect(a.parameter, 0.8);
    expect(a.times.last, closeTo(5.8, 1e-9));
    step(0.1, 0.1);
    expect(out.get(0, 0), b.color);
    for (var i = 0; i < 49; i++) {
      step(0.1, 0.1);
    }
    expect(out.get(0, 0), b.color);
    step(0.1, 0.1);
    expect(out.get(0, 0), a.color);
    expect(a.creates, 2);
    expect(g.pauseDuringAlert, true);
    expect(g.liveOnly, true);
  });
  test(
    'Show skips missing/deleted looks and bounds all-unavailable retries',
    () {
      final a = Solid(0xff0000), b = Solid(0x00ff00);
      var available = true, resolves = 0;
      final show = PhoneShow(
        id: 's',
        title: 's',
        entries: [
          const PhoneShowEntry(ShowEntryKind.card, 'missing'),
          const PhoneShowEntry(ShowEntryKind.card, 'a'),
          const PhoneShowEntry(ShowEntryKind.card, 'b'),
        ],
      );
      final g = PhoneShowGenerator(show, (e) {
        resolves++;
        return e.id == 'missing'
            ? null
            : ShowLook(e.id == 'a' ? a : b, available: () => available);
      });
      final effect = g.create(8, 8, 1), out = Frame(8, 8);
      effect.render(out, 0, 0, Params({}), pal);
      expect(out.get(0, 0), a.color);
      available = false;
      effect.render(out, .025, .025, Params({}), pal);
      final count = resolves;
      for (var i = 0; i < 80; i++) {
        effect.render(out, i * .025, .025, Params({}), pal);
      }
      expect(resolves, count);
      expect(out.rgb.any((v) => v > 0), true);
      available = true;
      effect.render(out, 4, 1.1, Params({}), pal);
      expect(out.get(0, 0), b.color);
    },
  );
  test('Show entry time ignores slow-motion dt and gaps while paused for an alert', () {
    final a = Solid(0xff0000), b = Solid(0x00ff00);
    var wall = DateTime(2026, 10, 7, 12);
    final g = PhoneShowGenerator(
      PhoneShow(
        id: 's',
        title: 's',
        entries: [
          const PhoneShowEntry(ShowEntryKind.library, 'a', seconds: 3),
          const PhoneShowEntry(ShowEntryKind.library, 'b', seconds: 3),
        ],
      ),
      (e) => ShowLook(e.id == 'a' ? a : b),
      now: () => wall,
    );
    final effect = g.create(8, 8, 1), out = Frame(8, 8);
    void step(int ms, double dt) {
      wall = wall.add(Duration(milliseconds: ms));
      effect.render(out, 0, dt, Params({}), pal);
    }

    step(0, 0);
    // Half-speed playback (tiny dt) still ends the entry after 3 real seconds.
    for (var i = 0; i < 20; i++) {
      step(100, 0.05);
    }
    expect(out.get(0, 0), a.color);
    // An alert owns the display for a minute: no renders, then one resumes.
    wall = wall.add(const Duration(minutes: 1));
    step(40, 0.04);
    expect(out.get(0, 0), a.color);
    for (var i = 0; i < 8; i++) {
      step(100, 0.1);
    }
    expect(out.get(0, 0), a.color);
    for (var i = 0; i < 3; i++) {
      step(100, 0.1);
    }
    expect(out.get(0, 0), b.color);
  });

  // Does any frame in a long run show the last [out.width] columns of
  // [text] (tiny font) in the rows starting at [top] with [height]?
  bool endShown(Generator g, int w, int h, String text, int top, int height) {
    final mask = TextMask.lines(tinyFont, [text], trim: true);
    expect(mask.width, greaterThan(w), reason: 'test text must overflow');
    final y0 = top + (height - mask.height) ~/ 2;
    final effect = g.create(w, h, 1), out = Frame(w, h);
    for (var t = 0.0; t < 240; t += 0.05) {
      effect.render(out, t, 0.05, Params({}), pal);
      var ok = true;
      for (var y = 0; y < mask.height && ok; y++) {
        for (var x = 0; x < w; x++) {
          final lit = mask.idx[y * mask.width + mask.width - w + x] >= 0;
          final px = out.get(x, y0 + y) != 0;
          if (lit != px) {
            ok = false;
            break;
          }
        }
      }
      if (ok) return true;
    }
    return false;
  }

  GlanceCardGenerator counterCard(String title) => GlanceCardGenerator(
    GlanceCard(
      id: 'c',
      title: title,
      kind: GlanceKind.counter,
      date: DateTime(2026, 11, 7),
    ),
    Feed(),
    now: () => DateTime(2026, 10, 7, 12),
  );
  test('long titles scroll until their last letters are visible', () {
    const title = 'Trip to the mountains soon';
    expect(endShown(counterCard(title), 16, 16, title, 10, 5), true);
    const wide = 'Anniversary of the long hills trip';
    expect(endShown(counterCard(wide), 32, 8, wide, 0, 8), true);
    expect(endShown(counterCard(title), 8, 8, title, 0, 8), true);
    expect(endShown(counterCard(title), 32, 32, title, 26, 5), true);
  });
  test('a stale long label ("OLD Thunderstorm") is fully seen on 8x8', () {
    final now = DateTime.utc(2026, 10, 7, 12);
    final feed = Feed()
      ..error = true
      ..value = WeatherSnapshot(
        observed: now,
        fetched: now,
        celsius: 20,
        code: 95,
        isDay: true,
      );
    final g = GlanceCardGenerator(
      const GlanceCard(
        id: 'w',
        title: 'W',
        kind: GlanceKind.weather,
        place: place,
      ),
      feed,
      now: () => now,
    );
    expect(endShown(g, 8, 8, 'OLD Thunderstorm', 0, 8), true);
    expect(endShown(g, 16, 16, 'OLD Thunderstorm', 10, 5), true);
  });
  test("today's high and low are shown when known and current", () {
    final now = DateTime.utc(2026, 10, 7, 12);
    WeatherSnapshot snap({String? day}) => WeatherSnapshot(
      observed: now,
      fetched: now,
      celsius: 20,
      code: 0,
      isDay: true,
      high: 30.4,
      low: 18.6,
      forecastDay: day,
    );
    GlanceCardGenerator gen(WeatherSnapshot s, {bool f = false}) =>
        GlanceCardGenerator(
          GlanceCard(
            id: 'w',
            title: 'W',
            kind: GlanceKind.weather,
            place: place,
            fahrenheit: f,
          ),
          Feed()..value = s,
          now: () => now,
        );
    expect(
      endShown(gen(snap(day: '2026-10-07')), 8, 8, 'H 30 L 19', 0, 8),
      true,
    );
    expect(
      endShown(gen(snap(day: '2026-10-07'), f: true), 8, 8, 'H 87 L 65', 0, 8),
      true,
    );
    expect(
      endShown(gen(snap(day: '2026-10-06')), 8, 8, 'H 30 L 19', 0, 8),
      false,
    );
  });
}
