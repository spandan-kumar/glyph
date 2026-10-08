import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../design/stage.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import 'tiles.dart';
import 'tune_controller.dart';

/// Scroll-driven geometry for the Stage collapsing into the mini-stage.
///
/// [home] is where the Stage sits with the page at the top (in the screen
/// stack's coordinates), [mini] the thumbnail slot in the pinned bar. As the
/// page scrolls, [t] runs 0 → 1 over the distance it takes the Stage's home
/// to slide up under the bar, and the floating Stage's [rect] is the eased
/// interpolation between the two. Scrolling back up runs it in reverse.
class StageMorph extends ChangeNotifier {
  /// Eases the travel so the Stage shrinks a little ahead of the content
  /// scrolling under it (it never overlaps the caption below it).
  static const curve = Lb.ease;

  Rect? _home;
  Rect _mini = Rect.zero;
  double _t = 0;
  double _travel = 1;

  /// Scroll distance over which the Stage collapses.
  double get travel => _travel;

  /// Part-way between full Stage and thumbnail: not a place to rest.
  bool get between => _t > 0.01 && _t < 0.99;

  /// False until the Stage's home has been laid out and measured.
  bool get ready => _home != null;
  Rect? get home => _home;
  Rect get mini => _mini;

  /// Linear collapse progress, 0 (full Stage) to 1 (mini thumbnail).
  double get t => _t;

  /// Whether the Stage has become the mini thumbnail.
  bool get collapsed => _t >= 0.98;

  /// Where the floating Stage is drawn right now.
  Rect get rect => Rect.lerp(_home ?? _mini, _mini, curve.transform(_t))!;

  /// 0 → 1 as [t] runs from [from] to [to]; for fading things in.
  double fade(double from, double to) => ((_t - from) / (to - from)).clamp(0.0, 1.0);

  Map<Twin, (Rect, Rect)> _twins = const {};

  /// Whether [id] flies between the deck and the bar (both ends measured).
  bool flies(Twin id) => _twins.containsKey(id);

  /// 0 → 1 as the twin travels; each lands just before the bar takes over
  /// ([collapsed]), the ones nearer the Stage leaving first.
  double twinProgress(Twin id) => Lb.easeInOut.transform(fade(id.leaves, 0.98));

  /// Where the flying copy of [id] is drawn: riding the page with its home,
  /// pulled into its slot in the bar.
  Rect? twinRect(Twin id) {
    final (home, slot) = _twins[id] ?? (null, null);
    if (home == null || slot == null) return null;
    final page = home.translate(0, -_t * _travel);
    if (!id.ridesStage) return Rect.lerp(page, slot, twinProgress(id));
    // A straight line would cross the Stage shrinking into the same corner,
    // so the title tucks in under it, rides along, then steps right and up
    // into its slot once the Stage is small (sideways first, then up).
    final stage = rect;
    final ride = Offset.lerp(
        page.topLeft, Offset(stage.left, stage.bottom + 6), Lb.easeInOut.transform(fade(id.leaves, 0.5)))!;
    final at = Offset(lerpDouble(ride.dx, slot.left, Lb.ease.transform(fade(0.72, 0.9)))!,
        lerpDouble(ride.dy, slot.top, Lb.ease.transform(fade(0.86, 0.98)))!);
    return at & Size.lerp(home.size, slot.size, twinProgress(id))!;
  }

  /// Both ends of [id], page at the top and slot in the bar.
  (Rect, Rect)? twinEnds(Twin id) => _twins[id];

  /// [barBottom] is where the pinned bar ends; the morph completes when the
  /// whole deck under the Stage ([deckBottom], else the Stage's home) has
  /// scrolled up to it, so nothing of it is left behind. [twins] pairs each deck
  /// element's home (page at the top) with its slot in the bar.
  void update({
    required Rect home,
    required Rect mini,
    required double barBottom,
    required double offset,
    double? deckBottom,
    Map<Twin, (Rect, Rect)> twins = const {},
  }) {
    final travel = max(1.0, (deckBottom ?? home.bottom) - barBottom);
    _travel = travel;
    final t = (offset / travel).clamp(0.0, 1.0);
    if (home == _home && mini == _mini && t == _t && mapEquals(twins, _twins)) return;
    _home = home;
    _mini = mini;
    _t = t;
    _twins = twins;
    notifyListeners();
  }
}

/// Deck elements with a twin in the mini bar. As the Stage collapses, a copy
/// flies from one to the other so there's never two of them on screen.
///
/// The small channel line doesn't fly: its path would cross the shrinking
/// Stage, so it fades out with the page and in with the bar.
enum Twin {
  title(0.2, ridesStage: true),
  send(0.28);

  const Twin(this.leaves, {this.ridesStage = false});

  /// Collapse progress at which it starts pulling away from the page.
  final double leaves;

  /// Travels tucked under the Stage rather than in a straight line.
  final bool ridesStage;
}

/// Lets the screen find a deck or bar element to measure it. The newest
/// attached one wins, so a caption mid-crossfade measures the incoming copy.
class TwinAnchors {
  final _boxes = <Twin, RenderBox>{};

  RenderBox? operator [](Twin id) {
    final b = _boxes[id];
    return b != null && b.attached && b.hasSize ? b : null;
  }
}

class TwinAnchor extends SingleChildRenderObjectWidget {
  const TwinAnchor({super.key, required this.anchors, required this.id, super.child});

  final TwinAnchors? anchors;
  final Twin id;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderTwinAnchor(anchors, id);

  @override
  void updateRenderObject(BuildContext context, RenderTwinAnchor renderObject) => renderObject
    ..release()
    ..anchors = anchors
    ..id = id
    ..claim();
}

class RenderTwinAnchor extends RenderProxyBox {
  RenderTwinAnchor(this.anchors, this.id);

  TwinAnchors? anchors;
  Twin id;

  void claim() {
    if (attached) anchors?._boxes[id] = this;
  }

  void release() {
    if (identical(anchors?._boxes[id], this)) anchors?._boxes.remove(id);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    claim();
  }

  @override
  void detach() {
    release();
    super.detach();
  }
}

/// Hides a deck or bar element while its flying twin stands in for it.
class TwinSlot extends StatelessWidget {
  const TwinSlot({super.key, required this.morph, required this.id, required this.inBar, required this.child});

  final StageMorph? morph;
  final Twin id;

  /// The bar's copy shows once collapsed; the deck's only at the top.
  final bool inBar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = morph;
    if (m == null) return child;
    return ListenableBuilder(
      listenable: m,
      child: child,
      builder: (context, child) {
        final hidden = m.flies(id) && (inBar ? !m.collapsed : m.t > 0);
        return Opacity(opacity: hidden ? 0 : 1, child: IgnorePointer(ignoring: hidden, child: child));
      },
    );
  }
}

/// Calls [onLayout] (after the frame) whenever its child's size changes, so
/// the screen can re-measure the Stage's home without polling.
class LayoutReporter extends SingleChildRenderObjectWidget {
  const LayoutReporter({super.key, required this.onLayout, super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderLayoutReporter(onLayout);

  @override
  void updateRenderObject(BuildContext context, RenderLayoutReporter renderObject) => renderObject.onLayout = onLayout;
}

class RenderLayoutReporter extends RenderProxyBox {
  RenderLayoutReporter(this.onLayout);

  VoidCallback onLayout;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onLayout();
    });
  }
}

/// The one live Stage on Display. It floats above the page in the screen's
/// stack and is placed by [StageMorph]: full size under the header at the
/// top, the mini-stage thumbnail once the page has scrolled. Vertical drags
/// on it scroll the page underneath, so it never gets in the way.
class MorphingStage extends StatefulWidget {
  const MorphingStage({
    super.key,
    required this.morph,
    required this.scroll,
    required this.onTap,
    required this.onSwiped,
  });

  final StageMorph morph;
  final ScrollController scroll;

  /// Tweak at full size, back to the top as the mini thumbnail.
  final VoidCallback onTap;

  /// After a swipe surfs (hides the swipe hint).
  final VoidCallback onSwiped;

  @override
  State<MorphingStage> createState() => _MorphingStageState();
}

class _MorphingStageState extends State<MorphingStage> {
  bool _heart = false;
  Drag? _drag;

  @override
  void dispose() {
    _drag?.cancel();
    super.dispose();
  }

  void _doubleTap() {
    final tune = TuneScope.read(context);
    if (tune.playback.item == null) return;
    final on = tune.toggleFavourite();
    if (!on) return;
    HapticFeedback.lightImpact();
    setState(() => _heart = true);
    Future.delayed(heartHold, () {
      if (mounted) setState(() => _heart = false);
    });
  }

  void _longPress() {
    final p = AppScope.of(context).playback;
    HapticFeedback.lightImpact();
    p.isPlaying ? p.pause() : p.resume();
  }

  // Vertical drags belong to the page underneath.
  void _dragStart(DragStartDetails d) {
    if (!widget.scroll.hasClients) return;
    _drag = widget.scroll.position.drag(d, () => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback, devices = scope.devices;
    final tune = TuneScope.of(context);
    return GestureDetector(
      onVerticalDragStart: _dragStart,
      onVerticalDragUpdate: (d) => _drag?.update(d),
      onVerticalDragEnd: (d) => _drag?.end(d),
      onVerticalDragCancel: () => _drag?.cancel(),
      child: ListenableBuilder(
        listenable: Listenable.merge([playback, devices]),
        builder: (context, _) {
          // Switched off from the power key: the Stage dims like the room.
          final off = devices.isConnected && devices.isOn == false;
          return AnimatedOpacity(
            opacity: off ? 0.28 : 1,
            duration: Lb.medium,
            curve: Lb.ease,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Stage(
                  frame: playback.frame,
                  repaint: playback.frameTick,
                  // Sized by the morph, not by the Stage.
                  maxWidth: double.infinity,
                  onSwipe: (dir) {
                    widget.onSwiped();
                    tune.surf(context, dir);
                  },
                  onTap: widget.onTap,
                  onDoubleTap: _doubleTap,
                  onLongPress: _longPress,
                ),
                if (tune.shuffling) const Positioned.fill(child: IgnorePointer(child: _Reel())),
                IgnorePointer(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AnimatedScale(
                        scale: _heart ? 1 : 0.3,
                        duration: Lb.medium,
                        curve: heartPopCurve,
                        child: AnimatedOpacity(
                          opacity: _heart ? 1 : 0,
                          duration: Lb.fast,
                          child: const LedHeart(dot: 12),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!playback.isPlaying && playback.generator != null)
                  IgnorePointer(
                    child: ListenableBuilder(
                      listenable: widget.morph,
                      builder: (context, child) {
                        final o = 1 - widget.morph.fade(0, 0.3);
                        return o <= 0 ? const SizedBox.shrink() : Opacity(opacity: o, child: child);
                      },
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Lb.ink.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(Lb.rControl),
                              border: Border.all(color: Lb.line),
                            ),
                            child: Text('HELD · LONG-PRESS TO PLAY', style: LbType.label.copyWith(color: Lb.text2)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A slot-machine reel sweeping over the Stage while Surprise spins.
class _Reel extends StatefulWidget {
  const _Reel();

  @override
  State<_Reel> createState() => _ReelState();
}

class _ReelState extends State<_Reel> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Lb.rControl + 1),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(painter: _ReelPainter(_c.value)),
      ),
    );
  }
}

class _ReelPainter extends CustomPainter {
  _ReelPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Two bands rolling downward, like a reel blurring past. Stepped in
    // hard strips rather than a gradient, like rows of a matrix.
    const steps = [0.15, 0.35, 0.55, 0.35, 0.15];
    final strip = size.height * 0.24 / steps.length;
    final paint = Paint();
    for (final o in [0.0, 0.5]) {
      final top = ((t + o) % 1.0) * size.height * 1.4 - size.height * 0.32;
      for (var i = 0; i < steps.length; i++) {
        canvas.drawRect(Rect.fromLTWH(0, top + i * strip, size.width, strip + 0.5),
            paint..color = Lb.ink.withValues(alpha: steps[i]));
      }
    }
  }

  @override
  bool shouldRepaint(_ReelPainter old) => old.t != t;
}
