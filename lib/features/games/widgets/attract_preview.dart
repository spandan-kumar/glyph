import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../engine/frame.dart';
import '../../../ui/design/tokens.dart';
import '../../../ui/widgets/led_matrix_view.dart';
import '../core/game.dart';

/// A game playing itself, for the picker grid.
class AttractPreview extends StatefulWidget {
  const AttractPreview({super.key, required this.def, this.width = 16, this.height = 16});

  final GameDef def;
  final int width, height;

  @override
  State<AttractPreview> createState() => _AttractPreviewState();
}

class _AttractPreviewState extends State<AttractPreview> with SingleTickerProviderStateMixin {
  late GameView _view;
  late Frame _frame;
  late final Ticker _ticker;
  final _tick = ValueNotifier(0);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _setup();
    _ticker = createTicker(_onTick)..start();
  }

  void _setup() {
    _view = GameView(widget.def, widget.width, widget.height,
        seed: widget.def.id.hashCode & 0xffff, demo: true);
    _frame = Frame(widget.width, widget.height);
    _view.render(_frame);
  }

  @override
  void didUpdateWidget(AttractPreview old) {
    super.didUpdateWidget(old);
    if (old.def.id != widget.def.id || old.width != widget.width || old.height != widget.height) {
      _setup();
    }
  }

  void _onTick(Duration elapsed) {
    // ~30 fps keeps a grid of previews cheap.
    if ((elapsed - _last).inMilliseconds < 33) return;
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _view
      ..tick(dt)
      ..render(_frame);
    _tick.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LedMatrixView(frame: _frame, repaint: _tick, borderRadius: Lb.rTile);
}
