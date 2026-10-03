import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'type.dart';

/// A rotary control like a synth knob: drag up/down (or around) to turn,
/// with a haptic tick every detent. Changes are continuous; there is no
/// "apply".
class Knob extends StatefulWidget {
  const Knob({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.label,
    this.size = 64,
    this.accent = Lb.phosphor,
    this.detents = 20,
  });

  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String? label;
  final double size;
  final Color accent;
  final int detents;

  @override
  State<Knob> createState() => _KnobState();
}

class _KnobState extends State<Knob> {
  int _lastDetent = -1;

  double get _t => ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  void _setT(double t) {
    t = t.clamp(0.0, 1.0);
    final d = (t * widget.detents).round();
    if (d != _lastDetent) {
      _lastDetent = d;
      HapticFeedback.selectionClick();
    }
    widget.onChanged(widget.min + t * (widget.max - widget.min));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onVerticalDragUpdate: (d) => _setT(_t - d.delta.dy / 180),
          onHorizontalDragUpdate: (d) => _setT(_t + d.delta.dx / 180),
          child: Semantics(
            slider: true,
            label: widget.label,
            value: '${(_t * 100).round()}%',
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _KnobPainter(_t, widget.accent),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 6),
          Text(widget.label!.toUpperCase(), style: LbType.label),
        ],
      ],
    );
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter(this.t, this.accent);

  final double t;
  final Color accent;

  static const _start = 0.75 * pi, _sweep = 1.5 * pi;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final arc = Rect.fromCircle(center: c, radius: r - 2);
    canvas.drawArc(arc, _start, _sweep, false, track..color = Lb.line);
    canvas.drawArc(arc, _start, _sweep * t, false, track..color = accent);

    // The cap: a raised disc with a hairline and a notch.
    canvas.drawCircle(c, r - 9, Paint()..color = Lb.raised);
    canvas.drawCircle(c, r - 9, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Lb.line);
    final a = _start + _sweep * t;
    final inner = c + Offset(cos(a), sin(a)) * (r - 22);
    final outer = c + Offset(cos(a), sin(a)) * (r - 12);
    canvas.drawLine(inner, outer, Paint()
      ..color = Lb.text
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.t != t || old.accent != accent;
}
