import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/intro_splash.dart';

void main() {
  Widget host(Widget child, {bool reduceMotion = false}) => MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(textDirection: TextDirection.ltr, child: child),
      );

  testWidgets('reduced motion: finished logo held briefly, then done', (tester) async {
    var done = 0;
    await tester.pumpWidget(host(IntroSplash(full: true, onDone: () => done++), reduceMotion: true));
    expect(find.bySemanticsLabel('Glyph'), findsOneWidget);
    expect(find.text(skipHint.toUpperCase()), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(done, 1);
  });

  test('first run is brief and later launches are under a second', () {
    expect(IntroSplash.lengthOf(IntroSplash.firstRun), lessThan(const Duration(milliseconds: 2500)));
    expect(IntroSplash.lengthOf(IntroSplash.later), lessThan(const Duration(seconds: 1)));
  });

  testWidgets('first run says it can be skipped and finishes on its own', (tester) async {
    var done = 0;
    await tester.pumpWidget(host(IntroSplash(full: true, onDone: () => done++)));
    expect(find.text('TAP TO SKIP'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(done, 1);
  });

  testWidgets('later launches are minimal, with no hint', (tester) async {
    var done = 0;
    await tester.pumpWidget(host(IntroSplash(full: false, onDone: () => done++)));
    expect(find.text('TAP TO SKIP'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(done, 1);
  });

  testWidgets('a tap anywhere skips it, once', (tester) async {
    var done = 0;
    await tester.pumpWidget(host(IntroSplash(full: true, onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(10, 10));
    expect(done, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(done, 1);
  });

  testWidgets('the hint has no debug underline under MaterialApp', (tester) async {
    // The app shows the splash above any Material, where Flutter's fallback
    // text style draws a yellow double underline.
    await tester.pumpWidget(MaterialApp(home: IntroSplash(full: true, onDone: () {})));
    final hint = tester.widget<RichText>(
        find.descendant(of: find.text('TAP TO SKIP'), matching: find.byType(RichText)));
    expect(hint.text.style?.decoration, isNot(TextDecoration.underline));
    await tester.pump(const Duration(seconds: 3));
  });
}
