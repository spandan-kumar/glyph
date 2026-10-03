import 'dart:math';

import 'package:flutter/material.dart';

import '../../features/text/fonts.dart';
import '../design/tokens.dart';
import '../design/type.dart';

/// Step 1: black room, the wordmark lights up dot by dot.
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key, required this.onFind, required this.onBrowse});

  final VoidCallback onFind;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 3),
        const Center(child: LedWordmark()),
        const SizedBox(height: 28),
        Text('Your matrix, alive.', textAlign: TextAlign.center, style: LbType.title),
        const Spacer(flex: 4),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: onFind,
          child: const Text('Find my matrix'),
        ),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: Lb.text2,
          ),
          onPressed: onBrowse,
          child: const Text('Just looking around'),
        ),
      ],
    ),
  );
}

/// "GLYPH" assembling itself out of LED dots in a left-to-right sweep.
class LedWordmark extends StatefulWidget {
  const LedWordmark({super.key, this.text = 'GLYPH', this.maxDot = 10});

  final String text;
  final double maxDot;

  @override
  State<LedWordmark> createState() => _LedWordmarkState();
}

class _LedWordmarkState extends State<LedWordmark> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final font = boldFont;
      final cols = font.measure(widget.text);
      final dot = min(widget.maxDot, max(4.0, (box.maxWidth - 8) / cols)).floorToDouble();
      return Semantics(
        label: widget.text,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(cols * dot, font.capHeight * dot),
            painter: _WordmarkPainter(widget.text, font, dot, _c),
          ),
        ),
      );
    },
  );
}

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter(this.text, this.font, this.dot, this.t) : super(repaint: t);

  final String text;
  final BitmapFont font;
  final double dot;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = font.measure(text);
    final lit = <(int, int)>[];
    var x0 = 0;
    for (final rune in text.runes) {
      final g = font.glyph(rune);
      for (var y = 0; y < font.capHeight && y < g.rows.length; y++) {
        for (var x = 0; x < g.width; x++) {
          if (g.on(x, y)) lit.add((x0 + x, y));
        }
      }
      x0 += g.width + font.spacing;
    }
    final off = Paint()..color = Lb.ledOff;
    final r = dot * 0.38;
    // The unlit panel fades in first, then the letters light in a sweep.
    final panel = (t.value / 0.2).clamp(0.0, 1.0);
    if (panel > 0) {
      off.color = Lb.ledOff.withValues(alpha: panel);
      for (var y = 0; y < font.capHeight; y++) {
        for (var x = 0; x < cols; x++) {
          canvas.drawCircle(Offset((x + 0.5) * dot, (y + 0.5) * dot), r, off);
        }
      }
    }
    final bloom = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, dot * 0.6);
    final core = Paint();
    for (final (x, y) in lit) {
      // Each dot's turn comes with its column, jittered so it sparkles in.
      final jitter = ((x * 7 + y * 13) % 5) / 5 * 0.08;
      final start = 0.15 + (x / cols) * 0.6 + jitter;
      final k = ((t.value - start) / 0.12).clamp(0.0, 1.0);
      if (k <= 0) continue;
      final c = Offset((x + 0.5) * dot, (y + 0.5) * dot);
      // A brief flash as each dot lands, settling to warm white.
      final flash = (1 - ((t.value - start - 0.12) / 0.2).clamp(0.0, 1.0)) * k;
      final color = Color.lerp(Lb.text, Lb.phosphor, flash * 0.8)!;
      bloom.color = color.withValues(alpha: 0.35 * k);
      canvas.drawCircle(c, r * 1.6, bloom);
      core.color = color.withValues(alpha: k);
      canvas.drawCircle(c, r, core);
    }
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) => old.text != text || old.dot != dot;
}
