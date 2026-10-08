import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../../engine/registry.dart';
import '../../library/catalog.dart';
import '../design/tokens.dart';
import 'led_matrix_view.dart';
import 'preview_visibility.dart';
import 'preview_clock.dart';

/// A strict cap shared by every thumbnail, including audio and games.
abstract final class PreviewBudget {
  static int maxPerFrame = 4;
  static Duration _stamp = Duration.zero;
  static int _used = 0;
  static final _waiting = <BuildContext>{};

  static void forget(BuildContext context) => _waiting.remove(context);

  static bool take(BuildContext context) {
    if (!previewIsVisible(context)) {
      _waiting.remove(context);
      return false;
    }
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    if (now != _stamp) {
      _stamp = now;
      _used = 0;
      _waiting.removeWhere((c) => !c.mounted ||
          !TickerMode.getValuesNotifier(c).value.enabled ||
          !previewIsVisible(c));
    }
    _waiting.add(context);
    if (_used >= maxPerFrame || !identical(_waiting.first, context)) return false;
    _waiting.remove(context);
    _used++;
    return true;
  }
}

/// A self-running LED thumbnail. Pauses off-screen, during fast flings
/// and whenever an ancestor [TickerMode] is off. No bloom: tiles
/// stay cheap, the Stage is the only thing that glows.
class LivePreview extends StatefulWidget {
  /// A catalog look.
  const LivePreview({
    super.key,
    required LibraryItem this.item,
    this.size = 16,
    this.borderRadius = Lb.rTile,
    this.bezel = false,
  })  : generator = null,
        params = const {},
        paletteId = null,
        speed = 1,
        previewKey = null;

  /// Any generator (e.g. a [ClipGenerator] for something the user made).
  /// [previewKey] identifies it across rebuilds.
  const LivePreview.generator({
    super.key,
    required Generator this.generator,
    required String this.previewKey,
    this.params = const {},
    this.paletteId,
    this.speed = 1,
    this.size = 16,
    this.borderRadius = Lb.rTile,
    this.bezel = false,
  }) : item = null;

  final LibraryItem? item;
  final Generator? generator;
  final Map<String, double> params;
  final String? paletteId;
  final double speed;
  final String? previewKey;

  /// Frame size in LEDs (square).
  final int size;
  final double borderRadius;

  /// Draw the thin hardware bezel around the panel.
  final bool bezel;

  String get _id => item?.id ?? previewKey!;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> {
  static const _interval = Duration(milliseconds: 83); // ~12 fps

  late Frame _frame;
  late EffectInstance _instance;
  late Params _params;
  late Palette _palette;
  late double _speed;
  late final PreviewTicker _ticker;
  final _tick = ValueNotifier(0);
  Duration _last = Duration.zero;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _setup();
    _ticker = PreviewTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ticker.bind(context);
  }

  void _setup() {
    final item = widget.item;
    final g = item != null ? generatorById(item.generatorId) : widget.generator!;
    _frame = Frame(widget.size, widget.size);
    _instance = g.create(widget.size, widget.size, widget._id.hashCode);
    _params = Params.defaultsFor(g, item?.params ?? widget.params);
    _palette = paletteById(item?.paletteId ?? widget.paletteId ?? g.defaultPalette);
    _speed = item?.speed ?? widget.speed;
    _t = 0;
    // One frame up front so the tile never flashes black.
    _instance.render(_frame, 0, 0, _params, _palette);
  }

  @override
  void didUpdateWidget(LivePreview old) {
    super.didUpdateWidget(old);
    if (old._id != widget._id || old.size != widget.size) _setup();
  }

  void _onTick(Duration elapsed) {
    final since = elapsed - _last;
    if (since < _interval) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) return;
    if (!PreviewBudget.take(context)) return;
    final dt = (since.inMicroseconds / 1e6).clamp(0.0, 0.1) * _speed;
    _last = elapsed;
    _t += dt;
    _instance.render(_frame, _t, dt, _params, _palette);
    _tick.value++;
  }

  @override
  void dispose() {
    PreviewBudget.forget(context);
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LedMatrixView(
          frame: _frame,
          repaint: _tick,
          borderRadius: widget.borderRadius,
          bezel: widget.bezel,
      );
}
