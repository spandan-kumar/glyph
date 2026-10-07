import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/design/knob.dart';

/// Turns the knob found by [knob] a quarter turn by circling the dial, from
/// the left round to the top (clockwise, turning up) or back (down).
Future<void> turnKnob(WidgetTester tester, Finder knob, {bool up = true}) async {
  final dial = tester.getRect(find.descendant(of: knob, matching: find.byType(CustomPaint)).first);
  final r = dial.width * 0.4;
  Offset at(double a) => dial.center + Offset(cos(a), sin(a)) * r;
  final from = up ? pi : 1.5 * pi, to = up ? 1.5 * pi : pi;
  final g = await tester.startGesture(at(from));
  for (var i = 1; i <= 12; i++) {
    await g.moveTo(at(from + (to - from) * i / 12));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pump();
}

/// The [Knob] widgets on screen.
Finder get knobs => find.byType(Knob);
