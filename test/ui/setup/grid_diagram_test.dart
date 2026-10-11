import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/setup/grid_diagram.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/panel_setup.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget diagram, {double width = 320}) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: diagram),
        ),
      ),
    ),
  );

  testWidgets('tappable panels are labelled buttons of at least 48px and report their cell', (tester) async {
    final handle = tester.ensureSemantics();
    (int, int)? got;
    await pump(
      tester,
      GridDiagram(
        cols: 8,
        rows: 2,
        panelW: 8,
        panelH: 8,
        targets: const {(0, 0), (7, 1)},
        onPanel: (c) => got = c,
        cellLabel: (x, y) => 'Cell $x $y',
      ),
    );
    for (final cell in [(0, 0), (7, 1)]) {
      final f = find.bySemanticsLabel('Cell ${cell.$1} ${cell.$2}');
      expect(f, findsOneWidget);
      expect(tester.getSemantics(f).getSemanticsData().flagsCollection.isButton, isTrue);
      final size = tester.getSize(f);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      await tester.tap(f);
      expect(got, cell);
    }
    expect(find.bySemanticsLabel('Cell 3 0'), findsNothing, reason: 'panels that are not targets are not buttons');
    handle.dispose();
  });

  testWidgets('a lone target is still its own node, apart from the diagram label', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      GridDiagram(cols: 2, rows: 1, panelW: 8, panelH: 8, targets: const {(1, 0)}, onPanel: (_) {}, label: 'Grid'),
    );
    expect(find.bySemanticsLabel('Grid'), findsOneWidget);
    expect(find.bySemanticsLabel('Panel 2, 1'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a plain diagram is an image with a plain description', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const GridDiagram(cols: 4, rows: 2, panelW: 16, panelH: 16));
    expect(find.bySemanticsLabel('Display diagram, 4 by 2 panels of 16 by 16 lights'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('order numbers, the path and first lights draw for every chain without errors', (tester) async {
    for (final chain in PanelWiring.all) {
      await pump(
        tester,
        GridDiagram(
          cols: 3,
          rows: 2,
          panelW: 16,
          panelH: 16,
          chain: chain,
          numbers: true,
          showPath: true,
          selected: const {(1, 1)},
          firstLights: const {(0, 0): StartCorner.topLeft, (1, 1): StartCorner.bottomRight},
        ),
      );
      expect(tester.takeException(), isNull, reason: '$chain');
    }
  });

  testWidgets('a 8 by 8 grid of big panels still lays out in a narrow column', (tester) async {
    await pump(tester, const GridDiagram(cols: 8, rows: 8, panelW: 32, panelH: 32), width: 280);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(GridDiagram)).width, 280);
  });
}
