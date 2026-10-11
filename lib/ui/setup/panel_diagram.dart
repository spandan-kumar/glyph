import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../wled/panel_setup.dart';
import '../design/tokens.dart';

/// A display drawn as a grid of dim LED dots in a bezel. One widget for the
/// whole wizard: size tiles, the wiring questions (tap a corner, an arrow or
/// a dot) and the wiring result (the path the LEDs take).
///
/// Positions are logical, with the origin at the top left as you face the
/// display.
class PanelDiagram extends StatelessWidget {
  const PanelDiagram({
    super.key,
    required this.width,
    required this.height,
    this.maxHeight = 300,
    this.lit = const {},
    this.wiring,
    this.showPath = false,
    this.corner,
    this.alongWidth,
    this.onCorner,
    this.showRunArrows = false,
    this.dotColor = Lb.ledOff,
    this.onJump,
    this.label,
  });

  final int width, height;

  /// The most the panel itself may be tall.
  final double maxHeight;

  /// Logical cells drawn lit.
  final Set<(int, int)> lit;

  /// With [showPath], a line through every LED in the order they are wired.
  final PanelWiring? wiring;
  final bool showPath;

  /// The corner LED 0 is in, drawn lit.
  final StartCorner? corner;

  /// Which way the first run goes (needed for [onJump]).
  final bool? alongWidth;

  /// Two faint, non-interactive arrows from [corner] along the width and the
  /// height (the answer lives in option rows under the diagram).
  final bool showRunArrows;

  /// The colour of the unlit dots (or of the fine grid for tiny cells).
  final Color dotColor;

  /// Tap targets: the four corners and the two places the second run can
  /// start.
  final ValueChanged<StartCorner>? onCorner;
  final ValueChanged<bool>? onJump;
  final String? label;

  bool get _interactive => onCorner != null || onJump != null;

  /// Room around the panel so 48px targets on its corners stay inside.
  static const margin = 24.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final m = _interactive ? margin : 0.0;
      final availW = (box.maxWidth.isFinite ? box.maxWidth : 300.0) - 2 * m;
      final cell = math.max(1.0, math.min(availW / width, maxHeight / height));
      final g = _Geo(width, height, cell, m);
      final size = Size(availW + 2 * m, g.panelH + 2 * m);
      final desc = label ?? 'Display diagram, $width by $height lights';
      return SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            Semantics(
              label: desc,
              image: true,
              child: CustomPaint(
                size: size,
                painter: _DiagramPainter(
                  geo: g,
                  availW: availW,
                  lit: lit,
                  wiring: showPath ? wiring : null,
                  corner: corner,
                  alongWidth: alongWidth,
                  jump: onJump != null,
                  arrows: showRunArrows,
                  dotColor: dotColor,
                ),
              ),
            ),
            if (onCorner != null)
              for (final c in StartCorner.values)
                _target(
                  g.center(_cornerCell(c), availW),
                  '${_cap(c.label)} corner',
                  () => onCorner!(c),
                  child: _CornerRing(diameter: (g.cell * 0.38 * 4.4).clamp(20.0, 44.0)),
                ),
            if (onJump != null && corner != null && alongWidth != null) ..._candidates(g, availW),
          ],
        ),
      );
    },
  );

  (int, int) _cornerCell(StartCorner c) => (c.isRight ? width - 1 : 0, c.isBottom ? height - 1 : 0);

  Widget _target(Offset center, String label, VoidCallback onTap, {Widget? child}) => Positioned(
    left: center.dx - Lb.touch / 2,
    top: center.dy - Lb.touch / 2,
    width: Lb.touch,
    height: Lb.touch,
    child: Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: child == null
          ? InkWell(onTap: onTap, borderRadius: BorderRadius.circular(Lb.rControl))
          : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
    ),
  );

  /// The two cells the second run can start in.
  List<(int, int)> candidateCells() {
    final c = corner!;
    if (alongWidth!) {
      final y = c.isBottom ? height - 2 : 1;
      final near = c.isRight ? width - 1 : 0;
      return [(near, y), (width - 1 - near, y)];
    }
    final x = c.isRight ? width - 2 : 1;
    final near = c.isBottom ? height - 1 : 0;
    return [(x, near), (x, height - 1 - near)];
  }

  List<Widget> _candidates(_Geo g, double availW) {
    final cells = candidateCells();
    return [
      for (var i = 0; i < 2; i++)
        _target(
          g.center(cells[i], availW),
          i == 0 ? 'Same end as the first light' : 'The far end',
          () => onJump!(i == 1),
        ),
    ];
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// A corner target: a 1.5px ring that fills when pressed.
class _CornerRing extends StatefulWidget {
  const _CornerRing({required this.diameter});

  final double diameter;

  @override
  State<_CornerRing> createState() => _CornerRingState();
}

class _CornerRingState extends State<_CornerRing> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => _down = true),
    onPointerUp: (_) => setState(() => _down = false),
    onPointerCancel: (_) => setState(() => _down = false),
    child: Center(
      child: Container(
        width: widget.diameter,
        height: widget.diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _down ? Lb.raised : null,
          border: Border.all(color: Lb.text3, width: 1.5),
        ),
      ),
    ),
  );
}

class _Geo {
  const _Geo(this.w, this.h, this.cell, this.margin);

  final int w, h;
  final double cell, margin;
  double get panelW => cell * w;
  double get panelH => cell * h;

  /// Centre of logical cell [c] in a diagram [availW] wide (plus margins).
  Offset center((int, int) c, double availW) => Offset(
    margin + (availW - panelW) / 2 + (c.$1 + 0.5) * cell,
    margin + (c.$2 + 0.5) * cell,
  );
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter({
    required this.geo,
    required this.availW,
    required this.lit,
    required this.wiring,
    required this.corner,
    required this.alongWidth,
    required this.jump,
    required this.arrows,
    required this.dotColor,
  });

  final _Geo geo;
  final double availW;
  final Set<(int, int)> lit;
  final PanelWiring? wiring;
  final StartCorner? corner;
  final bool? alongWidth;
  final bool jump, arrows;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geo;
    final r = math.max(1.0, g.cell * 0.38);
    final left = g.margin + (availW - g.panelW) / 2;
    final bezel = Rect.fromLTWH(left, g.margin, g.panelW, g.panelH).inflate(math.min(6, g.cell * 0.5 + 2));
    final rrect = RRect.fromRectAndRadius(bezel, const Radius.circular(Lb.rControl));
    canvas.drawRRect(rrect, Paint()..color = Lb.bezel);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Lb.line
        ..style = PaintingStyle.stroke,
    );

    if (r * 2 < 2) {
      // Dots this small turn to mush: a fine grid reads as "many LEDs".
      final grid = Paint()
        ..color = Lb.text3.withValues(alpha: 0.7)
        ..strokeWidth = 0.6;
      // Lines about 3px apart stay readable as separate LEDs.
      final step = math.max(1, (3 / g.cell).ceil());
      for (var x = 0; x <= g.w; x += step) {
        final dx = left + x * g.cell;
        canvas.drawLine(Offset(dx, g.margin), Offset(dx, g.margin + g.panelH), grid);
      }
      for (var y = 0; y <= g.h; y += step) {
        final dy = g.margin + y * g.cell;
        canvas.drawLine(Offset(left, dy), Offset(left + g.panelW, dy), grid);
      }
    } else {
      canvas.drawPoints(
        ui.PointMode.points,
        [
          for (var y = 0; y < g.h; y++)
            for (var x = 0; x < g.w; x++) g.center((x, y), availW),
        ],
        Paint()
          ..color = dotColor
          ..strokeWidth = r * 2
          ..strokeCap = StrokeCap.round,
      );
    }

    final w = wiring;
    if (w != null) {
      final path = Path();
      final n = g.w * g.h;
      for (var i = 0; i < n; i++) {
        final (x, y) = w.positionOf(i, g.w, g.h);
        final o = g.center((x, y), availW);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Lb.text2
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, g.cell * 0.14)
          ..strokeJoin = StrokeJoin.round,
      );
      final (fx, fy) = w.positionOf(0, g.w, g.h);
      canvas.drawCircle(g.center((fx, fy), availW), r * 1.5, Paint()..color = Lb.phosphor);
      final (lx, ly) = w.positionOf(n - 1, g.w, g.h);
      canvas.drawCircle(
        g.center((lx, ly), availW),
        r * 1.3,
        Paint()
          ..color = Lb.text
          ..style = PaintingStyle.stroke,
      );
    }

    final litPaint = Paint()..color = Lb.phosphor;
    for (final c in lit) {
      canvas.drawCircle(g.center(c, availW), r * 1.2, litPaint);
    }
    final c = corner;
    if (c != null) {
      canvas.drawCircle(
        g.center((c.isRight ? g.w - 1 : 0, c.isBottom ? g.h - 1 : 0), availW),
        jump ? r : r * 1.5,
        litPaint,
      );
    }
    if (arrows && c != null) {
      final start = g.center((c.isRight ? g.w - 1 : 0, c.isBottom ? g.h - 1 : 0), availW);
      final dx = c.isRight ? -1.0 : 1.0, dy = c.isBottom ? -1.0 : 1.0;
      final p = Paint()
        ..color = Lb.text2.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.square;
      void arrow(Offset dir, double len) {
        final from = start + dir * (r * 1.5 + 6);
        final to = start + dir * math.max(len, r * 1.5 + 16);
        canvas.drawLine(from, to, p);
        final side = Offset(-dir.dy, dir.dx);
        canvas.drawLine(to, to - dir * 7 + side * 5, p);
        canvas.drawLine(to, to - dir * 7 - side * 5, p);
      }

      arrow(Offset(dx, 0), g.panelW * 0.4);
      arrow(Offset(0, dy), g.panelH * 0.4);
    }
    if (jump && c != null && alongWidth != null) {
      final cells = PanelDiagram(
        width: g.w,
        height: g.h,
        corner: c,
        alongWidth: alongWidth,
      ).candidateCells();
      final ring = Paint()
        ..color = Lb.phosphor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final cell in cells) {
        canvas.drawCircle(g.center(cell, availW), math.max(g.cell * 0.4, 4), ring);
      }
    }
  }

  @override
  bool shouldRepaint(_DiagramPainter old) =>
      old.geo.cell != geo.cell ||
      old.geo.w != geo.w ||
      old.geo.h != geo.h ||
      old.availW != availW ||
      old.lit != lit ||
      old.wiring != wiring ||
      old.corner != corner ||
      old.alongWidth != alongWidth ||
      old.arrows != arrows ||
      old.dotColor != dotColor ||
      old.jump != jump;
}
