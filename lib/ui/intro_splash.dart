import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../engine/frame.dart';
import '../engine/generator.dart';
import '../engine/generators/intro.dart';
import '../engine/palette.dart';
import 'design/tokens.dart';
import 'widgets/led_matrix_view.dart';

/// The Glyph intro as the app's launch screen: the full animation on first
/// run, a quick "pop and assemble" on later launches. Tap to skip.
class IntroSplash extends StatefulWidget {
  const IntroSplash({super.key, required this.full, required this.onDone});

  final bool full;
  final VoidCallback onDone;

  @override
  State<IntroSplash> createState() => _IntroSplashState();
}

class _IntroSplashState extends State<IntroSplash> with SingleTickerProviderStateMixin {
  // The quick version starts just before the pile pops.
  static const _quickFrom = 2.25;

  final _frame = Frame(16, 16);
  final _tick = ValueNotifier(0);
  late final EffectInstance _intro = GlyphIntro().create(16, 16, 1);
  late final Ticker _ticker;
  late final double _from = widget.full ? 0 : _quickFrom;
  late final double _to = GlyphIntro.duration + (widget.full ? 0.6 : 0.2);
  double _simTo = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Fast-forward the physics to the starting point without showing it.
    _advance(_from);
    _ticker = createTicker((elapsed) {
      final t = _from + elapsed.inMicroseconds / 1e6;
      if (t >= _to) return _finish();
      _advance(t);
      _tick.value++;
    })..start();
  }

  void _advance(double t) {
    final p = Params({});
    while (_simTo < t) {
      _simTo = (_simTo + 1 / 60).clamp(0, t);
      _intro.render(_frame, _simTo, 1 / 60, p, palettes.first);
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _ticker.stop();
    widget.onDone();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: ColoredBox(
        color: Lb.ink,
        child: Center(
          child: SizedBox(
            width: 220,
            child: LedMatrixView(frame: _frame, repaint: _tick, glow: true),
          ),
        ),
      ),
    );
  }
}
