import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

/// Instrument-panel label: DM Mono, uppercase, tracked.
class MonoLabel extends StatelessWidget {
  const MonoLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: color == null ? LbType.label : LbType.label.copyWith(color: color));
}

/// A section of a panel: mono label, optional trailing action, content.
class PanelSection extends StatelessWidget {
  const PanelSection({super.key, required this.label, required this.child, this.trailing, this.padding});

  final String label;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(Lb.gutter, 20, Lb.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: MonoLabel(label)),
            ?trailing,
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// A flat panel with a hairline border — the default container.
class LbPanel extends StatelessWidget {
  const LbPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Lb.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel)),
        side: Lb.hairline,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// A status dot (lit when [on]).
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.on, this.color = Lb.ok, this.size = 6});

  final bool on;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? color : Lb.text3,
          boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: size)] : null,
        ),
      );
}

/// A busy indicator drawn as a 3×3 block of LEDs with one lit dot chasing
/// round the edge — the matrix stand-in for a circular spinner.
class LedSpinner extends StatefulWidget {
  const LedSpinner({super.key, this.size = 20, this.color = Lb.text});

  final double size;
  final Color color;

  @override
  State<LedSpinner> createState() => _LedSpinnerState();
}

class _LedSpinnerState extends State<LedSpinner> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 960))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: CustomPaint(painter: _SpinnerPainter(_c, widget.color)),
  );
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.t, this.color) : super(repaint: t);

  final Animation<double> t;
  final Color color;

  // The eight edge cells, clockwise from top-left.
  static const _ring = [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (0, 1)];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / 3;
    final r = cell * 0.32;
    final head = (t.value * _ring.length).floor();
    for (var i = 0; i < _ring.length; i++) {
      // Head fully lit, two fading cells behind it.
      final age = (head - i) % _ring.length;
      final a = switch (age) {
        0 => 1.0,
        1 => 0.45,
        2 => 0.18,
        _ => 0.0,
      };
      final (x, y) = _ring[i];
      canvas.drawCircle(
        Offset((x + 0.5) * cell, (y + 0.5) * cell),
        r,
        Paint()..color = a == 0 ? Lb.ledOff : color.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.color != color;
}
