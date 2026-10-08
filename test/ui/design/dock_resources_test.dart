import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/design/dock.dart';

void main() {
  const items = [
    DockItem('Display', DockGlyph.display),
    DockItem('Make', DockGlyph.make),
    DockItem('Device', DockGlyph.device),
  ];

  testWidgets('room colour updates do not restart navigation animations', (
    tester,
  ) async {
    final accent = ValueNotifier(Colors.red);
    final index = ValueNotifier(0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ListenableBuilder(
            listenable: Listenable.merge([accent, index]),
            builder: (context, _) => Dock(
              items: items,
              index: index.value,
              onSelect: (tab) => index.value = tab,
              accent: accent.value,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    for (final color in [Colors.blue, Colors.green, Colors.amber]) {
      accent.value = color;
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, false);
    }
    await tester.tap(find.bySemanticsLabel('Make'));
    await tester.pump();
    expect(index.value, 1);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.transientCallbackCount, 0);
    final indicator = tester.widget<AnimatedPositioned>(
      find.byKey(const ValueKey('dock-indicator')),
    );
    expect(indicator.left, indicator.width);
    await tester.pumpWidget(const SizedBox());
    accent.dispose();
    index.dispose();
  });
}
