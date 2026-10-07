import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/tune/stage_morph.dart';

void main() {
  // A 360 × 740 phone: Stage centred under the header, caption below it,
  // Send at the right of the transport, the bar's slots at the top.
  const stage = Rect.fromLTWH(26, 130, 308, 308);
  const mini = Rect.fromLTWH(16, 32, 44, 44);
  const title = (Rect.fromLTWH(16, 520, 160, 30), Rect.fromLTWH(72, 52, 130, 20));
  const send = (Rect.fromLTWH(250, 590, 94, 34), Rect.fromLTWH(304, 34, 40, 40));

  StageMorph at(double offset) => StageMorph()
    ..update(
      home: stage,
      mini: mini,
      barBottom: 84,
      offset: offset,
      deckBottom: 640,
      twins: const {Twin.title: title, Twin.send: send},
    );

  test('the twins start at home, end in their slots, and the title never crosses the Stage', () {
    final start = at(0);
    expect(start.twinRect(Twin.title), title.$1);
    expect(start.twinRect(Twin.send), send.$1);

    final travel = start.travel;
    expect(travel, 640 - 84, reason: 'the whole deck leaves before the Stage lands');
    for (var i = 1; i < 100; i++) {
      final m = at(travel * i / 100);
      final t = m.twinRect(Twin.title)!;
      expect(t.overlaps(m.rect), isFalse, reason: 'title over the Stage at t=${m.t}');
    }

    final end = at(travel * 0.98);
    expect(end.collapsed, isTrue);
    expect(end.twinRect(Twin.title)!.topLeft.dx, closeTo(title.$2.left, 0.5));
    expect(end.twinRect(Twin.title)!.topLeft.dy, closeTo(title.$2.top, 0.5));
    expect(end.twinRect(Twin.send)!.center.dx, closeTo(send.$2.center.dx, 0.5));
  });
}
