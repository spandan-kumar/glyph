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
    this.zoom = false,
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

  /// On a wide or tall display, show a zoomed crop at the [corner] (just the
  /// first runs and a little context, faded at the cut) instead of the whole
  /// panel, so the dots stay big enough to tell apart.
  final bool zoom;

  bool get _interactive => onCorner != null || onJump != null;

  /// Room around the panel so 48px targets on its corners stay inside.
  static const margin = 24.0;

  /// A zoomed crop is used when whole-panel dots would be under [zoomBelow]px
  /// pitch, and is sized for [zoomCell]px pitch.
  static const zoomBelow = 14.0;
  static const zoomCell = 16.0;
  static const zoomMaxCell = 28.0;
  static const _contextRuns = 3;

  /// The visible window of logical cells: (x0, y0, columns, rows).
  (int, int, int, int) _window(double availW) {
    final full = math.min(availW / width, maxHeight / height);
    final c = corner;
    if (!zoom || c == null || full >= zoomBelow) return (0, 0, width, height);
    final fitW = math.max(1, (availW / zoomCell).floor());
    final fitH = math.max(1, (maxHeight / zoomCell).floor());
    final along = alongWidth;
    // Two runs plus one more for context; the long way as far as it fits.
    final vw = along == false ? math.min(width, _contextRuns) : math.min(width, fitW);
    final vh = along == true ? math.min(height, _contextRuns) : math.min(height, fitH);
    return (c.isRight ? width - vw : 0, c.isBottom ? height - vh : 0, vw, vh);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final m = _interactive || zoom ? margin : 0.0;
      final availW = (box.maxWidth.isFinite ? box.maxWidth : 300.0) - 2 * m;
      final (vx, vy, vw, vh) = _window(availW);
      final cropped = vw < width || vh < height;
      var cell = math.min(availW / vw, maxHeight / vh);
      if (cropped) cell = math.min(cell, zoomMaxCell);
      final g = _Geo(width, height, math.max(1.0, cell), m, vx, vy, vw, vh);
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
          g.center(g.clamp(cells[i]), availW),
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
  const _Geo(this.w, this.h, this.cell, this.margin, this.x0, this.y0, this.vw, this.vh);

  /// The whole display, and the window of it that is drawn.
  final int w, h, x0, y0, vw, vh;
  final double cell, margin;
  double get panelW => cell * vw;
  double get panelH => cell * vh;
  bool get cropped => vw < w || vh < h;

  /// Centre of logical cell [c] in a diagram [availW] wide (plus margins).
  Offset center((int, int) c, double availW) =>
      Offset(margin + (availW - panelW) / 2 + (c.$1 - x0 + 0.5) * cell, margin + (c.$2 - y0 + 0.5) * cell);

  /// [c] pulled inside the window (cells past the cut sit on its fade).
  (int, int) clamp((int, int) c) => (c.$1.clamp(x0, x0 + vw - 1).toInt(), c.$2.clamp(y0, y0 + vh - 1).toInt());
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
    final r = math.max(1.0, g.cell * (g.cropped ? 0.3 : 0.38));
    final left = g.margin + (availW - g.panelW) / 2;
    final panel = Rect.fromLTWH(left, g.margin, g.panelW, g.panelH);
    final bezel = panel.inflate(math.min(6, g.cell * 0.5 + 2));
    final rrect = RRect.fromRectAndRadius(bezel, const Radius.circular(Lb.rControl));
    canvas.drawRRect(rrect, Paint()..color = Lb.bezel);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Lb.line
        ..style = PaintingStyle.stroke,
    );

    // Tiny cells: draw every k-th LED in both axes so dots stay readable and
    // the panel keeps its exact aspect ratio.
    final k = g.cell >= 3.2 ? 1 : (4 / g.cell).ceil();
    final dia = math.max(2.5, k == 1 ? r * 2 : g.cell * k * 0.62);
    final centers = <Offset>[];
    for (var y = g.y0; y < g.y0 + g.vh; y += k) {
      for (var x = g.x0; x < g.x0 + g.vw; x += k) {
        // Centre of the k×k block (shorter at the far edge).
        final bx = math.min(k, g.x0 + g.vw - x), by = math.min(k, g.y0 + g.vh - y);
        final o = g.center((x, y), availW);
        centers.add(o + Offset((bx - 1) * g.cell / 2, (by - 1) * g.cell / 2));
      }
    }
    canvas.drawPoints(
      ui.PointMode.points,
      centers,
      Paint()
        ..color = dotColor
        ..strokeWidth = dia
        ..strokeCap = StrokeCap.round,
    );

    if (g.cropped) _paintCut(canvas, g, panel, bezel);

    final w = wiring;
    if (w != null) _paintPath(canvas, g, w, r);

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
      final cells = PanelDiagram(width: g.w, height: g.h, corner: c, alongWidth: alongWidth).candidateCells();
      final ring = Paint()
        ..color = Lb.phosphor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final double ringR = g.cropped ? g.cell * 0.62 : math.max(g.cell * 0.4, 4.0);
      for (final cell in cells) {
        canvas.drawCircle(g.center(g.clamp(cell), availW), ringR, ring);
      }
    }
  }

  /// Fades the cut edges into the bezel and adds a small "…" beyond them, so
  /// a crop reads as part of a bigger panel.
  void _paintCut(Canvas canvas, _Geo g, Rect panel, Rect bezel) {
    final fade = Paint();
    // Overlapping bands stack up: the nearer the cut, the more bezel shows.
    const depth = 3;
    void band(Rect r, double a) => canvas.drawRect(r, fade..color = Lb.bezel.withValues(alpha: a));
    final edge = bezel.inflate(0.5);
    final dots = Paint()..color = Lb.text3;
    void ellipsis(Offset first, Offset step) {
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(first + step * i.toDouble(), 1.4, dots);
      }
    }

    final mid = panel.center;
    final b = bezel.right - panel.right;
    if (g.x0 + g.vw < g.w) {
      for (var i = 0; i < depth; i++) {
        band(Rect.fromLTRB(panel.right - g.cell * (i + 1), bezel.top + 1, edge.right, bezel.bottom - 1), 0.5);
      }
      ellipsis(Offset(panel.right + b + 5, mid.dy), const Offset(4, 0));
    }
    if (g.x0 > 0) {
      for (var i = 0; i < depth; i++) {
        band(Rect.fromLTRB(edge.left, bezel.top + 1, panel.left + g.cell * (i + 1), bezel.bottom - 1), 0.5);
      }
      ellipsis(Offset(panel.left - b - 5, mid.dy), const Offset(-4, 0));
    }
    if (g.y0 + g.vh < g.h) {
      for (var i = 0; i < depth; i++) {
        band(Rect.fromLTRB(bezel.left + 1, panel.bottom - g.cell * (i + 1), bezel.right - 1, edge.bottom), 0.5);
      }
      ellipsis(Offset(mid.dx, panel.bottom + b + 5), const Offset(0, 4));
    }
    if (g.y0 > 0) {
      for (var i = 0; i < depth; i++) {
        band(Rect.fromLTRB(bezel.left + 1, edge.top, bezel.right - 1, panel.top + g.cell * (i + 1)), 0.5);
      }
      ellipsis(Offset(mid.dx, panel.top - b - 5), const Offset(0, -4));
    }
  }

  /// The LED path: runs solid, the long returns between them thin, dashed
  /// and faint, and an arrowhead on the first run for the direction.
  void _paintPath(Canvas canvas, _Geo g, PanelWiring w, double r) {
    final n = g.w * g.h;
    final runs = Path();
    final returns = <(Offset, Offset)>[];
    // The first run ends at its first turn or jump.
    var firstRunEnd = n - 1;
    var settled = false;
    var prev = w.positionOf(0, g.w, g.h);
    var prevO = g.center(prev, availW);
    runs.moveTo(prevO.dx, prevO.dy);
    for (var i = 1; i < n; i++) {
      final p = w.positionOf(i, g.w, g.h);
      final o = g.center(p, availW);
      final step = (p.$1 - prev.$1).abs() + (p.$2 - prev.$2).abs() == 1;
      if (step) {
        runs.lineTo(o.dx, o.dy);
      } else {
        returns.add((prevO, o));
        runs.moveTo(o.dx, o.dy);
      }
      if (!settled) {
        final first = w.positionOf(0, g.w, g.h), second = w.positionOf(1, g.w, g.h);
        final along = (second.$1 - first.$1, second.$2 - first.$2);
        if (!step || (p.$1 - prev.$1, p.$2 - prev.$2) != along) {
          firstRunEnd = i - 1;
          settled = true;
        }
      }
      prev = p;
      prevO = o;
    }
    final width = math.max(1.0, g.cell * 0.14);
    final dashed = Paint()
      ..color = Lb.text2.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, width * 0.7);
    for (final (a, b) in returns) {
      _dash(canvas, a, b, dashed);
    }
    canvas.drawPath(
      runs,
      Paint()
        ..color = Lb.text2
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round,
    );
    if (firstRunEnd >= 1) {
      final a = g.center(w.positionOf(0, g.w, g.h), availW);
      final b = g.center(w.positionOf(firstRunEnd, g.w, g.h), availW);
      final len = (b - a).distance;
      if (len >= 12) {
        final dir = (b - a) / len;
        final side = Offset(-dir.dy, dir.dx);
        final tip = (a + b) / 2 + dir * 4;
        final head = Paint()
          ..color = Lb.text
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.square;
        canvas.drawLine(tip, tip - dir * 6 + side * 4, head);
        canvas.drawLine(tip, tip - dir * 6 - side * 4, head);
      }
    }
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

  static void _dash(Canvas canvas, Offset a, Offset b, Paint p) {
    const on = 3.0, off = 4.0;
    final len = (b - a).distance;
    if (len == 0) return;
    final dir = (b - a) / len;
    for (var t = 0.0; t < len; t += on + off) {
      canvas.drawLine(a + dir * t, a + dir * math.min(t + on, len), p);
    }
  }

  @override
  bool shouldRepaint(_DiagramPainter old) =>
      old.geo.cell != geo.cell ||
      old.geo.w != geo.w ||
      old.geo.h != geo.h ||
      old.geo.x0 != geo.x0 ||
      old.geo.y0 != geo.y0 ||
      old.geo.vw != geo.vw ||
      old.geo.vh != geo.vh ||
      old.availW != availW ||
      old.lit != lit ||
      old.wiring != wiring ||
      old.corner != corner ||
      old.alongWidth != alongWidth ||
      old.arrows != arrows ||
      old.dotColor != dotColor ||
      old.jump != jump;
}
