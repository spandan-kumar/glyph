import 'dart:math';

import 'package:flutter/material.dart';

import '../../engine/frame.dart';
import '../design/tokens.dart';

/// The little matrix in the header: 5×5 dots. While streaming it's a tiny
/// live mirror of the Stage; [charge] fills it as a Keep beams in, and
/// [flash] lights it fully when the look has landed on the matrix.
class MatrixGlyph extends StatelessWidget {
  const MatrixGlyph({
    super.key,
    required this.frame,
    required this.repaint,
    required this.live,
    required this.accent,
    this.charge = 0,
    this.flash = 0,
    this.error = false,
    this.dot = 3.4,
  });

  static const n = 5;

  final Frame frame;
  final Listenable repaint;
  final bool live;
  final Color accent;
  final double charge, flash, dot;
  final bool error;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size.square(n * dot),
          painter: _GlyphPainter(this),
        ),
      );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.g) : super(repaint: g.live ? g.repaint : null);

  final MatrixGlyph g;

  @override
  void paint(Canvas canvas, Size size) {
    const n = MatrixGlyph.n;
    final d = g.dot;
    final off = Paint()..color = Lb.ledOff;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = Lb.line;
    canvas.drawRRect(
        RRect.fromRectAndRadius((Offset.zero & size).inflate(2), const Radius.circular(Lb.rTile)), line);
    final f = g.frame;
    final lit = Paint();
    final glow = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, d * 0.9);
    final charged = (g.charge * n * n).floor();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final c = Offset((x + 0.5) * d, (y + 0.5) * d);
        final r = d * 0.36;
        Color? color;
        if (g.error && g.flash > 0) {
          color = Color.lerp(Lb.ledOff, Lb.danger, g.flash);
        } else if (g.flash > 0) {
          color = Color.lerp(Lb.ledOff, g.accent, g.flash);
        } else if ((n - 1 - y) * n + x < charged) {
          // Fills from the bottom row up, like a glass of light.
          color = g.accent;
        }
        if (color == null && g.live && f.width > 0) {
          final sx = ((x + 0.5) / n * f.width).floor().clamp(0, f.width - 1);
          final sy = ((y + 0.5) / n * f.height).floor().clamp(0, f.height - 1);
          final i = (sy * f.width + sx) * 3;
          final px = f.rgb;
          if (i + 2 < px.length && max(px[i], max(px[i + 1], px[i + 2])) > 24) {
            color = Color.fromARGB(255, px[i], px[i + 1], px[i + 2]);
          }
        }
        if (color == null) {
          canvas.drawCircle(c, r, off);
          continue;
        }
        if (g.flash > 0.2) canvas.drawCircle(c, r * 1.6, glow..color = color.withValues(alpha: 0.6 * g.flash));
        canvas.drawCircle(c, r, lit..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.g.charge != g.charge ||
      old.g.flash != g.flash ||
      old.g.live != g.live ||
      old.g.error != g.error ||
      old.g.accent != g.accent ||
      old.g.frame != g.frame;
}

/// AHA #5: dots of light streaming from the Stage up into the matrix glyph.
/// [progress] loops 0→1 while the look is being kept.
class BeamPainter extends CustomPainter {
  BeamPainter({required this.progress, required this.from, required this.to, required this.color})
      : super(repaint: progress);

  final Animation<double> progress;

  /// Where the dots leave from (the Stage) and land (the glyph), in the
  /// painter's coordinates.
  final Rect from;
  final Offset to;
  final Color color;

  static const _count = 18;
  static final _seeds = List.generate(_count, (i) => Random(i * 7919 + 13).nextDouble());

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    final dot = Paint();
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (var i = 0; i < _count; i++) {
      // Staggered and looping, so there's always a stream in flight.
      final t = (p + i / _count) % 1.0;
      final s = _seeds[i];
      final start = Offset(from.left + from.width * (0.15 + 0.7 * s), from.top + from.height * (0.15 + 0.5 * _seeds[(i + 5) % _count]));
      final control = Offset(
        (start.dx + to.dx) / 2 + (s - 0.5) * from.width * 0.9,
        min(start.dy, to.dy) + (start.dy - to.dy).abs() * 0.15,
      );
      final e = Lb.easeLeave.transform(t);
      final pos = _quad(start, control, to, e);
      // Fade in leaving the Stage, shrink as they're absorbed.
      final a = (t < 0.15 ? t / 0.15 : 1.0) * (1 - pow(t, 6).toDouble());
      final r = 2.6 * (1 - 0.55 * e);
      canvas.drawCircle(pos, r * 2.4, glow..color = color.withValues(alpha: 0.5 * a));
      canvas.drawCircle(pos, r, dot..color = Color.lerp(color, Colors.white, 0.35)!.withValues(alpha: a));
    }
  }

  static Offset _quad(Offset a, Offset b, Offset c, double t) {
    final u = 1 - t;
    return a * (u * u) + b * (2 * u * t) + c * (t * t);
  }

  @override
  bool shouldRepaint(BeamPainter old) => old.from != from || old.to != to || old.color != color;
}
