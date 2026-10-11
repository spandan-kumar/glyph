import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/make/led_loop.dart';
import 'package:glyph/ui/make/studio_kit.dart';

import '../app/playback_resources_test.dart' show CountingGenerator;

void main() {
  testWidgets('live status pulse remains still under reduced motion', (tester) async {
    Widget screen(bool still) => MaterialApp(home: MediaQuery(
      data: MediaQueryData(size: const Size(800, 600), disableAnimations: still),
      child: const Scaffold(body: LivePulse()),
    ));
    await tester.pumpWidget(screen(false));
    final painter = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(LivePulse), matching: find.byType(CustomPaint))).painter!;
    var ticks = 0;
    painter.addListener(() => ticks++);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ticks, greaterThan(0));
    await tester.pumpWidget(screen(true));
    final held = ticks;
    await tester.pump(const Duration(milliseconds: 500));
    expect(ticks, held);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(screen(false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ticks, greaterThan(held));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'live status pulse shares the preview clock and pauses when hidden',
    (tester) async {
      Widget screen(bool enabled) => MaterialApp(
        home: Scaffold(
          body: TickerMode(enabled: enabled, child: const LivePulse()),
        ),
      );
      await tester.pumpWidget(screen(true));
      final painter = tester
          .widget<CustomPaint>(find.descendant(of: find.byType(LivePulse), matching: find.byType(CustomPaint)))
          .painter!;
      var ticks = 0;
      painter.addListener(() => ticks++);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
      expect(ticks, greaterThan(0));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(screen(false));
      final hidden = ticks;
      await tester.pump(const Duration(milliseconds: 500));
      expect(ticks, hidden);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(screen(true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(ticks, greaterThan(hidden));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'previews batch work without a continuous ticker or starving tiles',
    (tester) async {
      final generators = List.generate(10, (_) => CountingGenerator());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                for (final g in generators)
                  SizedBox(width: 60, height: 60, child: LedLoop(generator: g)),
              ],
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        final before = generators.fold<int>(0, (sum, g) => sum + g.renders);
        await tester.pump(const Duration(milliseconds: 100));
        final after = generators.fold<int>(0, (sum, g) => sum + g.renders);
        expect(after - before, lessThanOrEqualTo(4));
        expect(tester.binding.transientCallbackCount, 0);
      }
      expect(generators.every((g) => g.renders > 1), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a mounted off-screen preview stops and resumes when scrolled into view',
    (tester) async {
      final g = CountingGenerator(), scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 1200),
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: LedLoop(generator: g),
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.renders, 1);
      scroll.jumpTo(1100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.renders, greaterThan(1));
      scroll.jumpTo(0);
      await tester.pump();
      final hidden = g.renders;
      await tester.pump(const Duration(milliseconds: 300));
      expect(g.renders, hidden);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
}
