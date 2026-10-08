import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/intro_splash.dart';

void main() {
  testWidgets('reduced motion: finished logo held briefly, then done', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: IntroSplash(full: true, onDone: () => done++),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Glyph'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(done, 1);
  });
}
