import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../wled/panel_setup.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'setup_parts.dart' show SetupChip;

/// A display of several panels drawn as one grid of dim LED dots with the
/// panel outlines over it. Used by the grid layout screen, the panel-order
/// questions (tap a panel), the order result (numbers and the chain path) and
/// the upside-down step (where each panel's first light sits).
///
/// Cells are (column, row) with the origin at the top left as you face the
/// display.
class GridDiagram extends StatelessWidget {
  const GridDiagram({
    super.key,
    required this.cols,
    required this.rows,
    required this.panelW,
    required this.panelH,
    this.maxHeight = 260,
    this.chain,
    this.numbers = false,
    this.showPath = false,
    this.targets = const {},
    this.onPanel,
    this.selected = const {},
    this.firstLights = const {},
    this.dotColor = Lb.ledOff,
    this.label,
    this.cellLabel,
  });

  final int cols, rows, panelW, panelH;
  final double maxHeight;

  /// With [numbers] or [showPath]: the order the panels are chained in.
  final PanelWiring? chain;
  final bool numbers, showPath;

  /// Panels that can be tapped (drawn with a brighter outline); the rest
  /// are dimmed. Empty with no [onPanel] means nothing is interactive.
  final Set<(int, int)> targets;
  final ValueChanged<(int, int)>? onPanel;

  /// Panels drawn marked (a [Lb.text] frame).
  final Set<(int, int)> selected;

  /// Where the first light of a panel sits, drawn as an amber dot.
  final Map<(int, int), StartCorner> firstLights;
  final Color dotColor;
  final String? label;

  /// Semantics label of a tappable panel.
  final String Function(int cx, int cy)? cellLabel;

  bool get _interactive => onPanel != null;
  static const margin = 24.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final m = _interactive ? margin : 8.0;
      final availW = (box.maxWidth.isFinite ? box.maxWidth : 300.0) - 2 * m;
      final totalW = cols * panelW, totalH = rows * panelH;
      final pitch = math.max(1.0, math.min(availW / totalW, maxHeight / totalH));
      final geo = _GridGeo(cols, rows, panelW, panelH, pitch, Offset(m + (availW - totalW * pitch) / 2, m));
      final size = Size(availW + 2 * m, totalH * pitch + 2 * m);
      // Panels narrower than a touch target get a row of chips as well.
      final dense = _interactive && targets.isNotEmpty && panelW * pitch < Lb.touch;
      final desc = label ?? 'Display diagram, $cols by $rows panels of $panelW by $panelH lights';
      final diagram = SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            Semantics(
              container: true,
              label: desc,
              image: true,
              child: CustomPaint(
                size: size,
                painter: _GridPainter(
                  geo: geo,
                  chain: chain,
                  numbers: numbers,
                  showPath: showPath,
                  targets: _interactive ? targets : const {},
                  selected: selected,
                  firstLights: firstLights,
                  dotColor: dotColor,
                ),
              ),
            ),
            if (_interactive)
              for (final cell in targets)
                _target(
                  geo,
                  cell,
                  () => onPanel!(cell),
                  cellLabel?.call(cell.$1, cell.$2) ?? 'Panel ${cell.$1 + 1}, ${cell.$2 + 1}',
                ),
          ],
        ),
      );
      if (!dense) return diagram;
      final cells = targets.toList()..sort((a, b) => (a.$2 * cols + a.$1).compareTo(b.$2 * cols + b.$1));
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          diagram,
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cell in cells)
                SetupChip(
                  label: 'Panel ${cell.$2 * cols + cell.$1 + 1}',
                  selected: selected.contains(cell),
                  onTap: () => onPanel!(cell),
                ),
            ],
          ),
        ],
      );
    },
  );

  Widget _target(_GridGeo g, (int, int) cell, VoidCallback onTap, String label) {
    final r = g.rect(cell);
    // Taller than drawn when short, never wider than the panel, so a target
    // can't reach into a neighbour's visual; dense grids add chips instead.
    final w = r.width, h = math.max(Lb.touch, r.height);
    return Positioned(
      left: r.center.dx - w / 2,
      top: r.center.dy - h / 2,
      width: w,
      height: h,
      child: Semantics(
        container: true,
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap),
      ),
    );
  }
}

class _GridGeo {
  const _GridGeo(this.cols, this.rows, this.pw, this.ph, this.pitch, this.origin);

  final int cols, rows, pw, ph;
  final double pitch;
  final Offset origin;

  double get width => cols * pw * pitch;
  double get height => rows * ph * pitch;

  Rect rect((int, int) c) =>
      Rect.fromLTWH(origin.dx + c.$1 * pw * pitch, origin.dy + c.$2 * ph * pitch, pw * pitch, ph * pitch);
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.geo,
    required this.chain,
    required this.numbers,
    required this.showPath,
    required this.targets,
    required this.selected,
    required this.firstLights,
    required this.dotColor,
  });

  final _GridGeo geo;
  final PanelWiring? chain;
  final bool numbers, showPath;
  final Set<(int, int)> targets, selected;
  final Map<(int, int), StartCorner> firstLights;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geo;
    final whole = Rect.fromLTWH(g.origin.dx, g.origin.dy, g.width, g.height);
    final bezel = whole.inflate(math.min(6, g.pitch * 0.5 + 2));
    final rrect = RRect.fromRectAndRadius(bezel, const Radius.circular(Lb.rControl));
    canvas.drawRRect(rrect, Paint()..color = Lb.bezel);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Lb.line
        ..style = PaintingStyle.stroke,
    );

    final interactive = targets.isNotEmpty;
    // Tiny pitch: draw every k-th LED in both directions.
    final k = g.pitch >= 3.2 ? 1 : (4 / g.pitch).ceil();
    final dia = math.max(2.0, k == 1 ? g.pitch * 0.76 : g.pitch * k * 0.62);
    for (var cy = 0; cy < g.rows; cy++) {
      for (var cx = 0; cx < g.cols; cx++) {
        final cell = (cx, cy);
        final r = g.rect(cell);
        final dim = interactive && !targets.contains(cell);
        final pts = <Offset>[];
        for (var y = 0; y < g.ph; y += k) {
          for (var x = 0; x < g.pw; x += k) {
            final bx = math.min(k, g.pw - x), by = math.min(k, g.ph - y);
            pts.add(Offset(r.left + (x + bx / 2) * g.pitch, r.top + (y + by / 2) * g.pitch));
          }
        }
        canvas.drawPoints(
          ui.PointMode.points,
          pts,
          Paint()
            ..color = dim ? dotColor : (interactive ? Lb.text3 : dotColor)
            ..strokeWidth = dia
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Panel outlines over the dots.
    for (var cy = 0; cy < g.rows; cy++) {
      for (var cx = 0; cx < g.cols; cx++) {
        final cell = (cx, cy);
        final r = g.rect(cell).deflate(0.5);
        final mark = selected.contains(cell);
        final target = targets.contains(cell);
        canvas.drawRect(
          r,
          Paint()
            ..color = mark ? Lb.text : (target ? Lb.text2 : Lb.text3.withValues(alpha: interactive ? 0.5 : 0.9))
            ..style = PaintingStyle.stroke
            ..strokeWidth = mark || target ? 1.5 : 1,
        );
      }
    }

    // A ring on each panel that can be tapped, like the corner rings.
    for (final cell in targets) {
      final r = g.rect(cell);
      final d = math.min(40.0, math.min(r.width, r.height) * 0.5);
      canvas.drawCircle(
        r.center,
        d / 2,
        Paint()
          ..color = Lb.text2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    final c = chain;
    if (c != null && (numbers || showPath)) _paintChain(canvas, g, c);

    for (final e in firstLights.entries) {
      final r = g.rect(e.key);
      final rad = (g.pitch * 1.1).clamp(3.0, 7.0);
      final inset = math.min(rad + 3, math.min(r.width, r.height) / 3);
      final p = Offset(
        e.value.isRight ? r.right - inset : r.left + inset,
        e.value.isBottom ? r.bottom - inset : r.top + inset,
      );
      canvas.drawCircle(p, rad, Paint()..color = Lb.phosphor);
    }
  }

  void _paintChain(Canvas canvas, _GridGeo g, PanelWiring c) {
    final n = g.cols * g.rows;
    final centers = [for (var k = 0; k < n; k++) g.rect(c.positionOf(k, g.cols, g.rows)).center];
    if (showPath) {
      final solid = Path()..moveTo(centers.first.dx, centers.first.dy);
      final dashed = Paint()
        ..color = Lb.text2.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (var k = 1; k < n; k++) {
        final a = c.positionOf(k - 1, g.cols, g.rows), b = c.positionOf(k, g.cols, g.rows);
        final step = (a.$1 - b.$1).abs() + (a.$2 - b.$2).abs() == 1;
        if (step) {
          solid.lineTo(centers[k].dx, centers[k].dy);
        } else {
          _dash(canvas, centers[k - 1], centers[k], dashed);
          solid.moveTo(centers[k].dx, centers[k].dy);
        }
      }
      canvas.drawPath(
        solid,
        Paint()
          ..color = Lb.text2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
      if (n > 1) {
        final a = centers[0], b = centers[1];
        final len = (b - a).distance;
        if (len > 16) {
          final dir = (b - a) / len, side = Offset(-dir.dy, dir.dx);
          final tip = a + dir * (len * 0.55);
          final head = Paint()
            ..color = Lb.text
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.square;
          canvas.drawLine(tip, tip - dir * 7 + side * 5, head);
          canvas.drawLine(tip, tip - dir * 7 - side * 5, head);
        }
      }
    }
    if (numbers) {
      for (var k = 0; k < n; k++) {
        final r = g.rect(c.positionOf(k, g.cols, g.rows));
        final size = (math.min(r.width, r.height) * 0.42).clamp(10.0, 20.0);
        final first = k == 0;
        final tp = TextPainter(
          text: TextSpan(
            text: '${k + 1}',
            style: LbType.mono.copyWith(fontSize: size, color: first ? Lb.ink : Lb.text, fontWeight: FontWeight.w500),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final pad = const EdgeInsets.symmetric(horizontal: 4, vertical: 1);
        final box = Rect.fromCenter(
          center: r.center,
          width: tp.width + pad.horizontal,
          height: tp.height + pad.vertical,
        );
        canvas.drawRect(box, Paint()..color = first ? Lb.phosphor : Lb.bezel.withValues(alpha: 0.88));
        if (!first) {
          canvas.drawRect(
            box,
            Paint()
              ..color = Lb.line
              ..style = PaintingStyle.stroke,
          );
        }
        tp.paint(canvas, box.topLeft + Offset(pad.left, pad.top));
      }
    }
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
  bool shouldRepaint(_GridPainter old) =>
      old.geo.cols != geo.cols ||
      old.geo.rows != geo.rows ||
      old.geo.pw != geo.pw ||
      old.geo.ph != geo.ph ||
      old.geo.pitch != geo.pitch ||
      old.geo.origin != geo.origin ||
      old.chain != chain ||
      old.numbers != numbers ||
      old.showPath != showPath ||
      old.dotColor != dotColor ||
      old.targets.length != targets.length ||
      !old.targets.containsAll(targets) ||
      old.selected.length != selected.length ||
      !old.selected.containsAll(selected) ||
      old.firstLights.length != firstLights.length ||
      old.firstLights.entries.any((e) => firstLights[e.key] != e.value);
}
