import 'package:flutter/material.dart';

import '../../engine/frame.dart';

/// Draws a [Frame] as round LEDs on a dark panel. Pass [repaint] (e.g. the
/// playback frame tick) to repaint without rebuilding.
class LedMatrixView extends StatelessWidget {
  const LedMatrixView({
    super.key,
    required this.frame,
    this.repaint,
    this.glow = false,
    this.borderRadius = 16,
  });

  final Frame frame;
  final Listenable? repaint;
  final bool glow;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: frame.width / frame.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CustomPaint(
          painter: _LedPainter(frame, glow, repaint),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _LedPainter extends CustomPainter {
  _LedPainter(this.frame, this.glow, Listenable? repaint)
      : super(repaint: repaint);

  final Frame frame;
  final bool glow;

  static final _bg = Paint()..color = const Color(0xFF050507);
  static final _off = Paint()..color = const Color(0xFF15151D);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _bg);
    final cell = size.width / frame.width;
    final r = cell * 0.36;
    final led = Paint();
    final halo = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.5);
    final px = frame.rgb;

    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final i = (y * frame.width + x) * 3;
        final cr = px[i], cg = px[i + 1], cb = px[i + 2];
        final c = Offset((x + 0.5) * cell, (y + 0.5) * cell);
        final peak = cr > cg ? (cr > cb ? cr : cb) : (cg > cb ? cg : cb);
        if (peak < 6) {
          canvas.drawCircle(c, r, _off);
          continue;
        }
        final color = Color.fromARGB(255, cr, cg, cb);
        if (glow && peak > 60) {
          halo.color = color.withValues(alpha: 0.35 * peak / 255);
          canvas.drawCircle(c, cell * 0.62, halo);
        }
        led.color = color;
        canvas.drawCircle(c, r, led);
      }
    }
  }

  @override
  bool shouldRepaint(_LedPainter old) => old.frame != frame || old.glow != glow;
}
