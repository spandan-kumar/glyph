import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/design/knob.dart';

import 'turn_knob.dart';

void main() {
  testWidgets('a knob turns with a circling finger and never scrolls its page', (tester) async {
    var value = 0.5;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => ListView(
          controller: scroll,
          children: [
            const SizedBox(height: 200),
            Center(child: Knob(value: value, label: 'Speed', onChanged: (v) => setState(() => value = v))),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    ));

    await turnKnob(tester, knobs);
    expect(value, closeTo(0.5 + 1 / 3, 0.03), reason: 'a quarter turn of a 270° knob');
    expect(scroll.offset, 0);

    await turnKnob(tester, knobs, up: false);
    expect(value, closeTo(0.5, 0.03));

    // A straight drag through the middle does nothing and still doesn't scroll.
    await tester.drag(knobs, const Offset(0, -80));
    await tester.pump();
    expect(scroll.offset, 0);

    // Past the stop it stays at the stop.
    for (var i = 0; i < 4; i++) {
      await turnKnob(tester, knobs);
    }
    expect(value, 1);
  });
}
