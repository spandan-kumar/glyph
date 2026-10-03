import 'package:flutter/widgets.dart';

import '../../features/text/fonts.dart';
import 'tokens.dart';

/// Text drawn as lit LED dots with Glyph's own bitmap fonts — used for
/// channel names, the wordmark and big numbers.
class LedText extends StatelessWidget {
  const LedText(
    this.text, {
    super.key,
    this.dot = 3,
    this.color = Lb.text,
    this.font,
    this.unlit = false,
  });

  final String text;

  /// Size of one LED cell in logical pixels.
  final double dot;
  final Color color;
  final BitmapFont? font;

  /// Also draw the unlit dots of the text's bounding box.
  final bool unlit;

  @override
  Widget build(BuildContext context) {
    final f = font ?? tinyFont;
    final w = f.measure(text);
    return CustomPaint(
      size: Size(w * dot, f.capHeight * dot),
      painter: _LedTextPainter(text, f, dot, color, unlit),
    );
  }
}

class _LedTextPainter extends CustomPainter {
  _LedTextPainter(this.text, this.font, this.dot, this.color, this.unlit);

  final String text;
  final BitmapFont font;
  final double dot;
  final Color color;
  final bool unlit;

  @override
  void paint(Canvas canvas, Size size) {
    final on = Paint()..color = color;
    final off = Paint()..color = Lb.ledOff;
    final r = dot * 0.4;
    var x0 = 0;
    for (final rune in text.runes) {
      final g = font.glyph(rune);
      for (var y = 0; y < font.capHeight; y++) {
        for (var x = 0; x < g.width; x++) {
          final lit = y < g.rows.length && g.on(x, y);
          if (!lit && !unlit) continue;
          canvas.drawCircle(Offset((x0 + x + 0.5) * dot, (y + 0.5) * dot), r, lit ? on : off);
        }
      }
      x0 += g.width + font.spacing;
    }
  }

  @override
  bool shouldRepaint(_LedTextPainter old) =>
      old.text != text || old.dot != dot || old.color != color || old.unlit != unlit;
}
