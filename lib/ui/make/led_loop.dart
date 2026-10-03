import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../design/tokens.dart';
import '../widgets/led_matrix_view.dart';
import '../widgets/live_preview.dart';

/// Runs any [Generator] locally as a small self-playing LED panel — studio
/// tiles, creation tiles. Pauses with an ancestor [TickerMode] and during
/// fast flings, and shares the per-frame [PreviewBudget] with other previews.
class LedLoop extends StatefulWidget {
  const LedLoop({
    super.key,
    required this.generator,
    this.width = 16,
    this.height = 16,
    this.palette,
    this.glow = false,
    this.bezel = false,
    this.borderRadius = Lb.rTile,
    this.resetKey,
    this.seed = 7,
  });

  final Generator generator;
  final int width, height;
  final Palette? palette;
  final bool glow, bezel;
  final double borderRadius;

  /// Restart from scratch when this changes (e.g. a creation's clip).
  final Object? resetKey;
  final int seed;

  @override
  State<LedLoop> createState() => _LedLoopState();
}

class _LedLoopState extends State<LedLoop> with SingleTickerProviderStateMixin {
  static const _interval = Duration(milliseconds: 40);
  static const _starving = Duration(milliseconds: 200);

  late Frame _frame;
  late EffectInstance _fx;
  late Params _params;
  late Palette _palette;
  late final Ticker _ticker;
  final _tick = ValueNotifier(0);
  Duration _last = Duration.zero;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _setup();
    _ticker = createTicker(_onTick)..start();
  }

  void _setup() {
    final w = widget.width.clamp(1, 128), h = widget.height.clamp(1, 128);
    final g = widget.generator;
    _frame = Frame(w, h);
    _fx = g.create(w, h, widget.seed);
    _params = Params.defaultsFor(g);
    _palette = widget.palette ?? paletteById(g.defaultPalette);
    _t = 0;
    _fx.render(_frame, 0, 0, _params, _palette);
  }

  @override
  void didUpdateWidget(LedLoop old) {
    super.didUpdateWidget(old);
    if (old.generator.id != widget.generator.id ||
        old.width != widget.width ||
        old.height != widget.height ||
        old.resetKey != widget.resetKey) {
      _setup();
    } else if (old.palette != widget.palette) {
      _palette = widget.palette ?? paletteById(widget.generator.defaultPalette);
    }
  }

  void _onTick(Duration elapsed) {
    final since = elapsed - _last;
    if (since < _interval) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) return;
    if (!PreviewBudget.take(starving: since > _starving)) return;
    final dt = (since.inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _t += dt;
    _fx.render(_frame, _t, dt, _params, _palette);
    _tick.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: LedMatrixView(
          frame: _frame,
          repaint: _tick,
          glow: widget.glow,
          bezel: widget.bezel,
          borderRadius: widget.borderRadius,
        ),
      );
}
