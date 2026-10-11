import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/setup/panel_diagram.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/panel_setup.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget diagram, {double width = 320}) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Center(child: SizedBox(width: width, child: diagram))),
    ),
  );

  testWidgets('corner targets are labelled buttons of at least 48px and report their corner', (tester) async {
    final handle = tester.ensureSemantics();
    StartCorner? got;
    await pump(tester, PanelDiagram(width: 32, height: 8, onCorner: (c) => got = c));
    final labels = {
      'Top left corner': StartCorner.topLeft,
      'Top right corner': StartCorner.topRight,
      'Bottom left corner': StartCorner.bottomLeft,
      'Bottom right corner': StartCorner.bottomRight,
    };
    for (final e in labels.entries) {
      final f = find.bySemanticsLabel(e.key);
      expect(f, findsOneWidget, reason: e.key);
      final data = tester.getSemantics(f).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      final size = tester.getSize(f);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      await tester.tap(f);
      expect(got, e.value, reason: e.key);
    }
    expect(find.bySemanticsLabel('Display diagram, 32 by 8 lights'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('jump dots are labelled and answer', (tester) async {
    final handle = tester.ensureSemantics();
    bool? far;
    await pump(
      tester,
      PanelDiagram(width: 8, height: 8, corner: StartCorner.topLeft, alongWidth: true, onJump: (f) => far = f),
    );
    await tester.tap(find.bySemanticsLabel('Same end as the first light'));
    expect(far, isFalse);
    await tester.tap(find.bySemanticsLabel('The far end'));
    expect(far, isTrue);
    handle.dispose();
  });

  test('the second run starts next to the first, at either end', () {
    final rows = PanelDiagram(width: 8, height: 4, corner: StartCorner.topLeft, alongWidth: true);
    expect(rows.candidateCells(), [(0, 1), (7, 1)]);
    final cols = PanelDiagram(width: 8, height: 4, corner: StartCorner.bottomRight, alongWidth: false);
    expect(cols.candidateCells(), [(6, 3), (6, 0)]);
  });

  for (final (w, h) in [(1, 1), (8, 8), (32, 8), (8, 32), (128, 128)]) {
    testWidgets('draws ${w}x$h with its path without errors and within its width', (tester) async {
      await pump(
        tester,
        PanelDiagram(width: w, height: h, wiring: const PanelWiring(corner: StartCorner.bottomRight, vertical: true, zigzag: true), showPath: true),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(PanelDiagram)).width, lessThanOrEqualTo(320));
      expect(tester.getSize(find.byType(CustomPaint).last).height, lessThanOrEqualTo(300 + 12));
    });
  }
}
