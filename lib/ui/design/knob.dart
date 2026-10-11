import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'type.dart';

/// A rotary control like a synth knob: circle a finger around it to turn
/// it (clockwise turns up), with a tick every detent and a firmer bump at
/// either end. It takes the touch the moment it lands, so a page it sits in
/// never scrolls instead. Changes are continuous; there is no "apply".
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
  double? _angle; // the finger's angle around the centre, while turning
  double _turn = 0; // where the turn has got to, unclamped within the stops

  double get _t => ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  Offset get _centre => Offset(widget.size / 2, widget.size / 2);

  /// Near the centre the angle swings wildly, so it doesn't count there.
  double? _angleAt(Offset p) {
    final v = p - _centre;
    return v.distance < widget.size * 0.14 ? null : atan2(v.dy, v.dx);
  }

  void _down(PointerDownEvent e) {
    _angle = _angleAt(e.localPosition);
    _turn = _t;
    _lastDetent = (_t * widget.detents).round();
    HapticFeedback.selectionClick();
  }

  void _move(PointerMoveEvent e) {
    final a = _angleAt(e.localPosition);
    if (a == null) return;
    final from = _angle;
    _angle = a;
    if (from == null) return;
    // Shortest way round, so crossing ±π doesn't jump.
    var d = a - from;
    if (d > pi) d -= 2 * pi;
    if (d < -pi) d += 2 * pi;
    _turn = (_turn + d / _KnobPainter._sweep).clamp(0.0, 1.0);
    _setT(_turn);
  }

  void _setT(double t) {
    final was = _t;
    t = t.clamp(0.0, 1.0);
    final d = (t * widget.detents).round();
    if ((t == 0 || t == 1) && t != was) {
      HapticFeedback.lightImpact(); // the end stop
      _lastDetent = d;
    } else if (d != _lastDetent) {
      _lastDetent = d;
      HapticFeedback.selectionClick();
    }
    widget.onChanged(widget.min + t * (widget.max - widget.min));
  }

  void _step(int dir) => _setT(_t + dir / widget.detents);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wins the gesture arena on touch-down, so a scrolling parent
        // never gets the drag; the turn itself is read from raw pointers.
        RawGestureDetector(
          gestures: {
            EagerGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(EagerGestureRecognizer.new, (_) {}),
          },
          child: Listener(
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: (_) => _angle = null,
            onPointerCancel: (_) => _angle = null,
            child: Semantics(
              slider: true,
              label: widget.label,
              value: '${(_t * 100).round()}%',
              increasedValue: '${((_t + 1 / widget.detents).clamp(0.0, 1.0) * 100).round()}%',
              decreasedValue: '${((_t - 1 / widget.detents).clamp(0.0, 1.0) * 100).round()}%',
              onIncrease: () => _step(1),
              onDecrease: () => _step(-1),
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _KnobPainter(_t, widget.accent),
              ),
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
