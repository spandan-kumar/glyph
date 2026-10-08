import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/tune/stage_deck.dart';

void main() {
  for (final compact in [false, true]) {
    testWidgets('room colour does not animate the ${compact ? "compact" : "wide"} Send border', (tester) async {
      final accent = ValueNotifier(Colors.red);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
        child: ValueListenableBuilder<Color>(
          valueListenable: accent,
          builder: (context, color, _) => SendButton(
            state: KeepState.idle, accent: color, compact: compact, onTap: () {},
          ),
        ),
      ))));
      await tester.pump(const Duration(milliseconds: 300));
      for (final color in [Colors.blue, Colors.green, Colors.amber]) {
        accent.value = color;
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, false);
      }
      await tester.pumpWidget(const SizedBox());
      accent.dispose();
    });
  }
}
