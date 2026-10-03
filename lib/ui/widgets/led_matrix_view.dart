import 'dart:ui';

import 'package:flutter/material.dart';

import '../../engine/frame.dart';
import '../design/tokens.dart';

/// Draws a [Frame] as a real LED panel: warm unlit dots, lit dots with a hot
/// core, and (with [glow]) a single blurred bloom pass under them. Pass
/// [repaint] (e.g. the playback frame tick) to repaint without rebuilding.
class LedMatrixView extends StatelessWidget {
  const LedMatrixView({
    super.key,
    required this.frame,
    this.repaint,
    this.glow = false,
    this.borderRadius = Lb.rTile,
    this.bezel = false,
  });

  final Frame frame;
  final Listenable? repaint;
  final bool glow;
  final double borderRadius;

  /// Draw a thin hardware bezel around the panel.
  final bool bezel;

  @override
  Widget build(BuildContext context) {
    Widget panel = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CustomPaint(
        painter: _LedPainter(frame, glow, repaint),
        child: const SizedBox.expand(),
      ),
    );
    if (bezel) {
      panel = DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF050403),
          // Crisp hardware edge: the bezel only softens by a pixel more
          // than the panel inside it.
          borderRadius: BorderRadius.circular(borderRadius + 1),
          border: Border.all(color: Lb.line),
        ),
        child: Padding(padding: const EdgeInsets.all(4), child: panel),
      );
    }
    return AspectRatio(aspectRatio: frame.width / frame.height, child: panel);
  }
}

class _LedPainter extends CustomPainter {
  _LedPainter(this.frame, this.glow, Listenable? repaint) : super(repaint: repaint);

  final Frame frame;
  final bool glow;

  static final _bg = Paint()..color = const Color(0xFF050403);
  static final _off = Paint()..color = Lb.ledOff;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _bg);
    final cell = size.width / frame.width;
    final r = cell * 0.38;
    final px = frame.rgb;

    if (glow) {
      // One blur for the whole panel instead of one per LED.
      canvas.saveLayer(Offset.zero & size, Paint()..imageFilter = ImageFilter.blur(sigmaX: cell * 0.7, sigmaY: cell * 0.7));
      final bloom = Paint();
      for (var y = 0; y < frame.height; y++) {
        for (var x = 0; x < frame.width; x++) {
          final i = (y * frame.width + x) * 3;
          final peak = _peak(px[i], px[i + 1], px[i + 2]);
          if (peak < 50) continue;
          bloom.color = Color.fromARGB((peak * 0.55).round(), px[i], px[i + 1], px[i + 2]);
          canvas.drawCircle(Offset((x + 0.5) * cell, (y + 0.5) * cell), cell * 0.62, bloom);
        }
      }
      canvas.restore();
    }

    final led = Paint();
    final core = Paint();
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final i = (y * frame.width + x) * 3;
        final cr = px[i], cg = px[i + 1], cb = px[i + 2];
        final c = Offset((x + 0.5) * cell, (y + 0.5) * cell);
        final peak = _peak(cr, cg, cb);
        if (peak < 6) {
          canvas.drawCircle(c, r, _off);
          continue;
        }
        led.color = Color.fromARGB(255, cr, cg, cb);
        canvas.drawCircle(c, r, led);
        if (cell >= 6 && peak > 140) {
          // A whiter hot spot reads as emitted light rather than paint.
          core.color = Color.lerp(led.color, const Color(0xFFFFFFFF), 0.45)!.withValues(alpha: 0.7);
          canvas.drawCircle(c, r * 0.42, core);
        }
      }
    }
  }

  static int _peak(int r, int g, int b) => r > g ? (r > b ? r : b) : (g > b ? g : b);

  @override
  bool shouldRepaint(_LedPainter old) => old.frame != frame || old.glow != glow;
}
