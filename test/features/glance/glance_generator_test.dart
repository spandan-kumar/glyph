import 'package:flutter_test/flutter_test.dart';
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
    final g = PhoneShowGenerator(
      show,
      (e) => e.id == 'a'
          ? ShowLook(a, params: Params({'value': 0.8}), speed: 2)
          : ShowLook(b),
    );
    final effect = g.create(8, 8, 1), out = Frame(8, 8);
    effect.render(out, 0, 0, Params({}), pal);
    expect(out.get(0, 0), a.color);
    effect.render(out, 2.9, 2.9, Params({}), pal);
    expect(out.get(0, 0), a.color);
    expect(a.times.last, 5.8);
    expect(a.parameter, 0.8);
    effect.render(out, 3, 0.1, Params({}), pal);
    expect(out.get(0, 0), b.color);
    effect.render(out, 7.9, 4.9, Params({}), pal);
    expect(out.get(0, 0), b.color);
    effect.render(out, 8, 0.1, Params({}), pal);
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
}
