import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/glance/glance_model.dart';
import 'package:glyph/features/glance/weather.dart';

void main() {
  GlanceCard card(DateTime date, {CounterMode mode = CounterMode.until}) =>
      GlanceCard(
        id: 'c',
        title: 'Trip',
        kind: GlanceKind.counter,
        date: date,
        mode: mode,
      );
  test(
    'counters use local calendar days across midnight, leap day and DST',
    () {
      if (Platform.environment['TZ'] == 'America/New_York') {
        expect(
          DateTime(2026, 3, 9).difference(DateTime(2026, 3, 8)).inHours,
          23,
        );
        expect(
          DateTime(2026, 11, 2).difference(DateTime(2026, 11, 1)).inHours,
          25,
        );
      }
      final c = card(DateTime(2026, 3, 9));
      expect(c.days(DateTime(2026, 3, 8, 0, 1)), 1);
      expect(c.days(DateTime(2026, 3, 8, 23, 59)), 1);
      expect(c.days(DateTime(2026, 3, 9)), 0);
      expect(card(DateTime(2024, 3, 1)).days(DateTime(2024, 2, 28, 23, 59)), 2);
      expect(card(DateTime(2026, 11, 2)).days(DateTime(2026, 11, 1)), 1);
      expect(c.days(DateTime(2026, 3, 8, 2).toUtc()), 1);
    },
  );
  test('reached, past and future dates have explicit labels in both modes', () {
    final c = card(DateTime(2026, 3, 9));
    expect(c.counterLabel(DateTime(2026, 3, 8)), '1 day to go');
    expect(c.counterLabel(DateTime(2026, 3, 9)), 'Today');
    expect(c.counterLabel(DateTime(2026, 3, 11)), '2 days ago');
    final since = card(DateTime(2026, 3, 9), mode: CounterMode.since);
    expect(since.counterLabel(DateTime(2026, 3, 8)), 'In 1 day');
    expect(since.counterLabel(DateTime(2026, 3, 11)), '2 days since');
  });
  test(
    'card and Show definitions round trip without counter timezone setting',
    () {
      final c = card(DateTime(2026, 3, 9));
      expect(GlanceCard.fromJson(c.toJson()).date!.year, c.date!.year);
      expect(GlanceCard.fromJson(c.toJson()).date!.month, c.date!.month);
      expect(GlanceCard.fromJson(c.toJson()).date!.day, c.date!.day);
      expect(c.toJson().containsKey('zone'), false);
      final s = PhoneShow(
        id: 's',
        title: 'Morning',
        entries: [const PhoneShowEntry(ShowEntryKind.card, 'c', seconds: 30)],
      );
      expect(PhoneShow.fromJson(s.toJson()).entries.single.seconds, 30);
    },
  );
  test('invalid dates, places and entry durations are rejected', () {
    final raw = card(DateTime(2026, 3, 9)).toJson()..['date'] = '2026-02-30';
    expect(() => GlanceCard.fromJson(raw), throwsFormatException);
    expect(const WeatherPlace('bad', double.nan, 10).valid, false);
    expect(const WeatherPlace('bad', 91, 10).valid, false);
    expect(const WeatherPlace('bad', 10, -181).valid, false);
    expect(
      () => PhoneShowEntry.fromJson({'kind': 'card', 'id': 'a', 'seconds': 0}),
      throwsFormatException,
    );
    expect(PhoneShow(id: 's', title: 's', entries: []).valid, false);
  });
  test('weather has fresh, stale, failed-cache and unavailable boundaries', () {
    final now = DateTime.utc(2026, 10, 7, 12);
    final w = WeatherSnapshot(
      observed: now,
      fetched: now,
      celsius: -5,
      code: 0,
      isDay: true,
    );
    expect(w.temperature(true), 23);
    expect(w.freshness(now), WeatherFreshness.fresh);
    expect(w.freshness(now, failed: true), WeatherFreshness.stale);
    expect(
      w.freshness(now.add(const Duration(minutes: 30))),
      WeatherFreshness.stale,
    );
    expect(
      w.freshness(now.add(const Duration(hours: 2))),
      WeatherFreshness.unavailable,
    );
    expect(
      w.freshness(now.subtract(const Duration(minutes: 6))),
      WeatherFreshness.unavailable,
    );
    expect(
      () => WeatherSnapshot.fromJson(w.toJson()..['code'] = 0.5),
      throwsFormatException,
    );
  });
  test('daily forecasts stop claiming today after the chosen place crosses midnight', () {
    final now = DateTime.utc(2026, 10, 7, 18, 29);
    final w = WeatherSnapshot(
      observed: now,
      fetched: now,
      celsius: 25,
      code: 0,
      isDay: false,
      high: 30,
      low: 20,
      forecastDay: '2026-10-07',
      utcOffsetSeconds: 19800,
    );
    expect(w.dailyIsToday(now), true);
    expect(w.dailyIsToday(now.add(const Duration(minutes: 1))), false);
    final cached = WeatherSnapshot.fromJson(w.toJson());
    expect(cached.dailyIsToday(now), true);
  });
}
