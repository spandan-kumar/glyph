import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../engine/frame.dart';
import '../engine/generator.dart';
import '../engine/generators/intro.dart';
import '../engine/palette.dart';
import 'design/tokens.dart';
import 'design/type.dart';
import 'widgets/led_matrix_view.dart';

/// The first-run splash's hint.
const skipHint = 'Tap to skip';

/// The Glyph intro as the app's launch screen. First run plays a brief cut
/// (the pile, the pop, the shine; about 2.3 s) with a "Tap to skip" hint;
/// later launches only pop and assemble (under a second). Tap anywhere to
/// skip. The device's own boot intro keeps the full timeline.
class IntroSplash extends StatefulWidget {
  const IntroSplash({super.key, required this.full, required this.onDone});

  final bool full;
  final VoidCallback onDone;

  /// Splash timings, exposed for tests: where each cut starts and ends on
  /// the intro's timeline, and how fast it plays.
  @visibleForTesting
  static const firstRun = (from: 1.2, to: GlyphIntro.shineEndAt, speed: 1.3);
  @visibleForTesting
  static const later = (from: GlyphIntro.popAt - 0.1, to: GlyphIntro.settledAt + 0.15, speed: 1.5);

  /// Wall-clock length of a cut.
  static Duration lengthOf(({double from, double to, double speed}) cut) =>
      Duration(microseconds: ((cut.to - cut.from) / cut.speed * 1e6).round());

  @override
  State<IntroSplash> createState() => _IntroSplashState();
}

class _IntroSplashState extends State<IntroSplash>
    with SingleTickerProviderStateMixin {
  late final _cut = widget.full ? IntroSplash.firstRun : IntroSplash.later;
  final _frame = Frame(16, 16);
  final _tick = ValueNotifier(0);
  late final EffectInstance _intro = GlyphIntro().create(16, 16, 1);
  late final Ticker _ticker;
  double _simTo = 0;
  bool _done = false;
  bool _checked = false;
  bool _reduced = false;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    // Fast-forward the physics to the starting point without showing it.
    _advance(_cut.from);
    _ticker = createTicker((elapsed) {
      final t = _cut.from + elapsed.inMicroseconds / 1e6 * _cut.speed;
      if (t >= _cut.to) return _finish();
      _advance(t);
      _tick.value++;
    })..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    if (!Lb.reduceMotion(context)) return;
    // Reduced motion: the finished logo, held briefly, then on.
    _reduced = true;
    _ticker.stop();
    _advance(GlyphIntro.duration);
    _tick.value++;
    _hold = Timer(Duration(milliseconds: widget.full ? 800 : 400), _finish);
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
    _hold?.cancel();
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Glyph',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: ColoredBox(
          color: Lb.ink,
          child: Stack(
            children: [
              Center(
                child: SizedBox(
                  width: 220,
                  child: LedMatrixView(frame: _frame, repaint: _tick, glow: true),
                ),
              ),
              // Only the first run lasts long enough to need saying.
              if (widget.full && !_reduced)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 48 + MediaQuery.paddingOf(context).bottom,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Lb.slow,
                    curve: Lb.ease,
                    builder: (context, k, child) => Opacity(opacity: k, child: child),
                    child: Text(skipHint.toUpperCase(), textAlign: TextAlign.center, style: LbType.label),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
