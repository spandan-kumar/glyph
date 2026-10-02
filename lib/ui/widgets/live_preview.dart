import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../../engine/registry.dart';
import '../../library/catalog.dart';
import 'led_matrix_view.dart';

/// A self-running thumbnail of a library item. Grid cells are built lazily, so
/// only on-screen previews tick.
class LivePreview extends StatefulWidget {
  const LivePreview({super.key, required this.item, this.size = 16});

  final LibraryItem item;
  final int size;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview>
    with SingleTickerProviderStateMixin {
  late Frame _frame;
  late EffectInstance _instance;
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
    final g = generatorById(widget.item.generatorId);
    _frame = Frame(widget.size, widget.size);
    _instance = g.create(widget.size, widget.size, widget.item.id.hashCode);
    _params = Params.defaultsFor(g, widget.item.params);
    _palette = paletteById(widget.item.paletteId);
    _t = 0;
  }

  @override
  void didUpdateWidget(LivePreview old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) _setup();
  }

  void _onTick(Duration elapsed) {
    // Thumbnails run at ~25 fps to keep a scrolling grid cheap.
    if ((elapsed - _last).inMilliseconds < 40) return;
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1) *
        (widget.item.speed ?? 1);
    _last = elapsed;
    _t += dt;
    _instance.render(_frame, _t, dt, _params, _palette);
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
      LedMatrixView(frame: _frame, repaint: _tick, borderRadius: 12);
}
