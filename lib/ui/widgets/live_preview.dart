import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../../engine/registry.dart';
import '../../library/catalog.dart';
import 'led_matrix_view.dart';

/// Caps how many previews render per vsync so a screen full of thumbnails
/// never blows the frame budget. Previews that miss a slot try again next
/// frame; anything starved for too long goes through regardless.
abstract final class PreviewBudget {
  static int maxPerFrame = 10;
  static Duration _stamp = Duration.zero;
  static int _used = 0;

  static bool take({required bool starving}) {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    if (now != _stamp) {
      _stamp = now;
      _used = 0;
    }
    if (_used >= maxPerFrame && !starving) return false;
    _used++;
    return true;
  }
}

/// A self-running thumbnail of a library item. Grids and shelves build
/// lazily, so only on-screen previews exist; they also pause while a fast
/// fling is in progress and whenever an ancestor [TickerMode] is off.
class LivePreview extends StatefulWidget {
  const LivePreview({super.key, required this.item, this.size = 16, this.borderRadius = 12});

  final LibraryItem item;
  final int size;
  final double borderRadius;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> with SingleTickerProviderStateMixin {
  static const _interval = Duration(milliseconds: 40); // ~25 fps
  static const _starving = Duration(milliseconds: 200);

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
    // One frame up front so the card never flashes black.
    _instance.render(_frame, 0, 0, _params, _palette);
  }

  @override
  void didUpdateWidget(LivePreview old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id || old.size != widget.size) _setup();
  }

  void _onTick(Duration elapsed) {
    final since = elapsed - _last;
    if (since < _interval) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) return;
    if (!PreviewBudget.take(starving: since > _starving)) return;
    final dt = (since.inMicroseconds / 1e6).clamp(0.0, 0.1) * (widget.item.speed ?? 1);
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
  Widget build(BuildContext context) => RepaintBoundary(
        child: LedMatrixView(frame: _frame, repaint: _tick, borderRadius: widget.borderRadius),
      );
}
