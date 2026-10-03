import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/clip.dart';
import '../design/ambient.dart';
import '../design/stage.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import 'tiles.dart';
import 'tune_controller.dart';

enum KeepState { idle, beaming, kept, failed }

/// Stage width that leaves room for the caption and a peek of the rails.
double stageWidthFor(Size screen, double aspect) {
  final byWidth = screen.width - 2 * Lb.gutter;
  final byHeight = max(160.0, screen.height * 0.40) * aspect;
  return min(360, min(byWidth, byHeight));
}

/// The top of Tune: the Stage, the channel caption and the transport.
class StageDeck extends StatefulWidget {
  const StageDeck({
    super.key,
    required this.stageKey,
    required this.onTweak,
    required this.onKeep,
    required this.keepState,
    required this.showHint,
    required this.onSwiped,
  });

  final GlobalKey stageKey;
  final VoidCallback onTweak;
  final VoidCallback onKeep;
  final KeepState keepState;
  final bool showHint;
  final VoidCallback onSwiped;

  @override
  State<StageDeck> createState() => _StageDeckState();
}

class _StageDeckState extends State<StageDeck> {
  bool _heart = false;

  void _doubleTap() {
    final tune = TuneScope.read(context);
    if (tune.playback.item == null) return;
    final on = tune.toggleFavourite();
    HapticFeedback.mediumImpact();
    if (!on) return;
    setState(() => _heart = true);
    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted) setState(() => _heart = false);
    });
  }

  void _longPress() {
    final p = AppScope.of(context).playback;
    HapticFeedback.lightImpact();
    p.isPlaying ? p.pause() : p.resume();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback, devices = scope.devices;
    final tune = TuneScope.of(context);
    final screen = MediaQuery.sizeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([playback, devices]),
      builder: (context, _) {
        final frame = playback.frame;
        final width = stageWidthFor(screen, frame.width / frame.height);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Stage(
                  key: widget.stageKey,
                  frame: frame,
                  repaint: playback.frameTick,
                  deviceName: devices.isConnected
                      ? '${devices.info!.name} · ${playback.isStreaming ? 'live' : devices.keptTitle != null && devices.keptTitle == (playback.item?.title ?? playback.generator?.name) ? 'kept' : 'ready'}'
                      : null,
                  connected: playback.isStreaming,
                  maxWidth: width,
                  onSwipe: (dir) {
                    widget.onSwiped();
                    tune.surf(context, dir);
                  },
                  onTap: widget.onTweak,
                  onDoubleTap: _doubleTap,
                  onLongPress: _longPress,
                ),
                if (tune.shuffling)
                  Positioned.fill(child: IgnorePointer(child: Center(child: _Reel(width: width)))),
                IgnorePointer(
                  child: AnimatedScale(
                    scale: _heart ? 1 : 0.3,
                    duration: Lb.medium,
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: _heart ? 1 : 0,
                      duration: Lb.fast,
                      child: const LedHeart(dot: 12),
                    ),
                  ),
                ),
                if (!playback.isPlaying && playback.generator != null)
                  IgnorePointer(
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
              ],
            ),
            SizedBox(
              height: 22,
              child: AnimatedOpacity(
                opacity: widget.showHint ? 1 : 0,
                duration: Lb.slow,
                child: widget.showHint ? const _SwipeHint() : const SizedBox.shrink(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Lb.gutter),
              child: _Caption(onTweak: widget.onTweak),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Lb.gutter),
              child: _Transport(onTweak: widget.onTweak, onKeep: widget.onKeep, keepState: widget.keepState),
            ),
          ],
        );
      },
    );
  }
}

/// "‹ swipe ›", nudging sideways; shown the first two times only.
class _SwipeHint extends StatefulWidget {
  const _SwipeHint();

  @override
  State<_SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<_SwipeHint> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final n = sin(_c.value * 2 * pi) * 4;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.translate(offset: Offset(-n.abs(), 0), child: Text('‹', style: LbType.mono)),
            const SizedBox(width: 8),
            Text('SWIPE THE MATRIX', style: LbType.label.copyWith(color: Lb.text2)),
            const SizedBox(width: 8),
            Transform.translate(offset: Offset(n.abs(), 0), child: Text('›', style: LbType.mono)),
          ],
        );
      },
    );
  }
}

/// The channel caption: a mono "CH 03 · RIGHT NOW" over the title, sliding
/// in from the side you surfed toward, like a TV changing channel.
class _Caption extends StatelessWidget {
  const _Caption({required this.onTweak});

  final VoidCallback onTweak;

  @override
  Widget build(BuildContext context) {
    final tune = TuneScope.of(context);
    final playback = tune.playback;
    final g = playback.generator;
    final item = playback.item;
    final at = tune.position;
    final label = tune.shuffling
        ? 'Shuffling…'
        : at >= 0
            ? 'CH ${(at + 1).toString().padLeft(2, '0')} · ${tune.channel.name}'
            : g == null
                ? 'Tuning…'
                : 'Now playing';
    final title = item?.title ?? g?.name ?? ' ';
    final sub = item != null
        ? '${item.category} · ${playback.palette.name}'
        : g is ClipGenerator
            ? 'Made by you'
            : g != null
                ? playback.palette.name
                : '';
    final key = tune.shuffling ? 'shuffle' : '${tune.channel.id}|${item?.id ?? g?.name}';
    final dir = tune.direction.toDouble();

    return Semantics(
      button: true,
      hint: 'Tweak',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTweak,
        child: AnimatedSize(
          duration: Lb.fast,
          curve: Lb.ease,
          alignment: Alignment.topLeft,
          child: AnimatedSwitcher(
            duration: tune.shuffling ? Duration.zero : Lb.medium,
            switchInCurve: Lb.ease,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, anim) {
              final incoming = child.key == ValueKey(key);
              final from = Offset((incoming ? 0.22 : -0.22) * dir, 0);
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: from, end: Offset.zero).animate(anim),
                  child: child,
                ),
              );
            },
            child: Column(
              key: ValueKey(key),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: LbType.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Flexible(
                    child: Text(title, style: LbType.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: Lb.text3),
                ]),
                const SizedBox(height: 2),
                Text(sub, style: LbType.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (item?.notice case final notice?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(notice,
                        style: LbType.small.copyWith(fontSize: 11, color: Lb.text3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.onTweak, required this.onKeep, required this.keepState});

  final VoidCallback onTweak, onKeep;
  final KeepState keepState;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final tune = TuneScope.of(context);
    final accent = AmbientScope.of(context).accent;
    final item = scope.playback.item;
    final devices = scope.devices;
    final canKeep = devices.isConnected && (devices.caps?.canPlayGifs ?? false) && scope.playback.generator != null;
    return ListenableBuilder(
      listenable: tune.library,
      builder: (context, _) {
        final fav = item != null && tune.library.isFavourite(item.id);
        return Row(
          children: [
            _RoundButton(
              icon: fav ? Icons.favorite : Icons.favorite_border,
              color: fav ? Lb.danger : Lb.text,
              label: fav ? 'Unheart' : 'Heart',
              onTap: item == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      tune.toggleFavourite();
                    },
            ),
            const SizedBox(width: 10),
            _RoundButton(
              icon: Icons.casino_outlined,
              label: 'Surprise me',
              onTap: tune.shuffling ? null : () => tune.surprise(context, scope.catalog),
            ),
            const SizedBox(width: 10),
            _RoundButton(icon: Icons.tune, label: 'Tweak', onTap: onTweak),
            const Spacer(),
            _PillButton(
              icon: keepState == KeepState.kept ? Icons.check : Icons.north_rounded,
              label: switch (keepState) {
                KeepState.beaming => 'Keeping',
                KeepState.kept => 'Kept',
                _ => 'Keep',
              },
              accent: canKeep ? accent : null,
              dim: !canKeep,
              busy: keepState == KeepState.beaming,
              onTap: keepState == KeepState.beaming ? null : onKeep,
            ),
          ],
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, this.onTap, this.color = Lb.text});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(side: Lb.hairline),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 20, color: onTap == null ? Lb.text3 : color),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.accent,
    this.dim = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? accent;
  final bool dim, busy;

  @override
  Widget build(BuildContext context) {
    final fg = dim ? Lb.text3 : Lb.text;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: accent ?? Lb.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: accent ?? Lb.text),
                    )
                  else
                    Icon(icon, size: 16, color: accent ?? fg),
                  const SizedBox(width: 8),
                  Text(label.toUpperCase(), style: LbType.label.copyWith(color: fg, fontSize: 11.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A slot-machine reel sweeping over the Stage while Surprise spins.
class _Reel extends StatefulWidget {
  const _Reel({required this.width});

  final double width;

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
    return SizedBox(
      width: widget.width,
      child: AspectRatio(
        aspectRatio: AppScope.of(context).playback.frame.width / AppScope.of(context).playback.frame.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Lb.rControl + 4),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(painter: _ReelPainter(_c.value)),
          ),
        ),
      ),
    );
  }
}

class _ReelPainter extends CustomPainter {
  _ReelPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Two soft bands rolling downward, like a reel blurring past.
    for (final o in [0.0, 0.5]) {
      final y = ((t + o) % 1.0) * size.height * 1.4 - size.height * 0.2;
      final rect = Rect.fromLTWH(0, y - size.height * 0.12, size.width, size.height * 0.24);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Lb.ink.withValues(alpha: 0), Lb.ink.withValues(alpha: 0.55), Lb.ink.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_ReelPainter old) => old.t != t;
}

/// The title the caption and mini-stage show.
String captionTitle(TuneController tune) =>
    tune.playback.item?.title ?? tune.playback.generator?.name ?? '';

/// The mono channel line used by the mini-stage.
String captionLabel(TuneController tune) {
  final at = tune.position;
  return at >= 0 ? 'CH ${(at + 1).toString().padLeft(2, '0')} · ${tune.channel.name}' : 'Now playing';
}
