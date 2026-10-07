import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/clip.dart';
import '../design/ambient.dart';
import '../design/led_text.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import 'stage_morph.dart';
import 'tune_controller.dart';

enum KeepState { idle, checking, beaming, kept, failed }

/// Stage width that leaves room for the caption and a peek of the rails.
double stageWidthFor(Size screen, double aspect) {
  final byWidth = screen.width - 2 * Lb.gutter;
  final byHeight = max(160.0, screen.height * 0.40) * aspect;
  return min(360, min(byWidth, byHeight));
}

/// The top of Display: the Stage's home (the live panel itself floats above
/// the page as a [MorphingStage] and sits here when the page is at the top),
/// the device line, the channel caption and the transport.
class StageDeck extends StatelessWidget {
  const StageDeck({
    super.key,
    required this.stageKey,
    required this.onTweak,
    required this.onKeep,
    required this.keepState,
    required this.showHint,
    this.onLayout,
  });

  /// On the Stage's home slot, so the screen can measure it.
  final GlobalKey stageKey;
  final VoidCallback onTweak;
  final VoidCallback onKeep;
  final KeepState keepState;
  final bool showHint;

  /// Called after the home slot changes size (e.g. a wider matrix).
  final VoidCallback? onLayout;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback, devices = scope.devices;
    final screen = MediaQuery.sizeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([playback, devices]),
      builder: (context, _) {
        final frame = playback.frame;
        final aspect = frame.width / frame.height;
        final width = stageWidthFor(screen, aspect);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: LayoutReporter(
                onLayout: onLayout ?? () {},
                child: SizedBox(key: stageKey, width: width, height: width / aspect),
              ),
            ),
            if (devices.isConnected) ...[
              const SizedBox(height: 10),
              _DeviceLine(
                text: '${devices.info!.name} · ${devices.isOn == false ? 'off' : playback.isStreaming ? 'live' : devices.isPlayingKept(playback.item?.title ?? playback.generator?.name ?? '') ? 'saved' : 'ready'}',
                lit: playback.isStreaming && devices.isOn != false,
              ),
            ],
            SizedBox(
              height: 22,
              child: AnimatedOpacity(
                opacity: showHint ? 1 : 0,
                duration: Lb.slow,
                child: showHint ? const _SwipeHint() : const SizedBox.shrink(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Lb.gutter),
              child: _Caption(onTweak: onTweak),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Lb.gutter),
              child: _Transport(onTweak: onTweak, onKeep: onKeep, keepState: keepState),
            ),
          ],
        );
      },
    );
  }
}

/// The device's name under the Stage with its status LED.
class _DeviceLine extends StatelessWidget {
  const _DeviceLine({required this.text, required this.lit});

  final String text;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StatusDot(on: lit),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text.toUpperCase(), style: LbType.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
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
            Text('SWIPE THE DISPLAY', style: LbType.label.copyWith(color: Lb.text2)),
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
                  const Icon(Icons.keyboard_arrow_up_sharp, size: 20, color: Lb.text3),
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
    final canSend = devices.isConnected && (devices.caps?.canPlayGifs ?? false) && !(scope.playback.generator?.liveOnly ?? true);
    return ListenableBuilder(
      listenable: tune.library,
      builder: (context, _) {
        final fav = item != null && tune.library.isFavourite(item.id);
        return Row(
          children: [
            SquareKey(
              icon: fav ? Icons.favorite_sharp : Icons.favorite_border_sharp,
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
            SquareKey(
              icon: Icons.casino_sharp,
              label: 'Surprise me',
              onTap: tune.shuffling ? null : () => tune.surprise(context, scope.catalog),
            ),
            const SizedBox(width: 10),
            SquareKey(icon: Icons.tune_sharp, label: 'Tweak', onTap: onTweak),
            const Spacer(),
            SendButton(
              state: keepState,
              accent: canSend ? accent : null,
              dim: !canSend,
              onTap: keepState == KeepState.beaming || keepState == KeepState.checking ? null : onKeep,
            ),
          ],
        );
      },
    );
  }
}

/// A square hardware key: 44 px, hairline, 2 px corners.
class SquareKey extends StatelessWidget {
  const SquareKey({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color = Lb.text,
    this.outlined = true,
    this.size = 44,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  /// Draw the hairline frame (off for keys sitting in a bar).
  final bool outlined;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(Lb.rControl)),
            side: outlined ? Lb.hairline : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, size: 20, color: onTap == null ? Lb.text3 : color),
            ),
          ),
        ),
      ),
    );
  }
}

/// SEND → SENDING → ✓ SENT: a rectangular key lit in the room colour when
/// the device can take it.
class SendButton extends StatelessWidget {
  const SendButton({super.key, required this.state, this.onTap, this.accent, this.dim = false, this.compact = false});

  final KeepState state;
  final VoidCallback? onTap;
  final Color? accent;
  final bool dim;

  /// A square key with just the sign (for the collapsed mini bar).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = dim ? Lb.text3 : Lb.text;
    final label = switch (state) {
      KeepState.checking => 'Checking',
      KeepState.beaming => 'Sending',
      KeepState.kept => 'Sent',
      KeepState.failed => 'Retry',
      _ => 'Send',
    };
    if (compact) {
      final busy = state == KeepState.beaming || state == KeepState.checking;
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(Lb.rControl)),
            side: BorderSide(color: accent ?? Lb.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: 40,
              child: Center(
                child: busy
                    ? _Chaser(color: accent ?? Lb.text)
                    : Icon(
                        switch (state) {
                          KeepState.kept => Icons.check_sharp,
                          KeepState.failed => Icons.refresh_sharp,
                          _ => Icons.north_sharp,
                        },
                        size: 18,
                        color: state == KeepState.failed ? Lb.danger : (accent ?? fg),
                      ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(Lb.rControl)),
          side: BorderSide(color: accent ?? Lb.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 34,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state == KeepState.beaming || state == KeepState.checking) ...[
                    _Chaser(color: accent ?? Lb.text),
                    const SizedBox(width: 8),
                  ] else if (state != KeepState.kept) ...[
                    Icon(Icons.north_sharp, size: 14, color: accent ?? fg),
                    const SizedBox(width: 8),
                  ],
                  // The pixel font, like the dock and the section headers.
                  LedText(label.toUpperCase(), dot: 2, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three LEDs chasing upward while a look is being sent.
class _Chaser extends StatefulWidget {
  const _Chaser({required this.color});

  final Color color;

  @override
  State<_Chaser> createState() => _ChaserState();
}

class _ChaserState extends State<_Chaser> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 6,
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final lit = (_c.value * 3).floor();
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 2; i >= 0; i--)
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == lit ? widget.color : Lb.ledOff,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The title the caption and mini-stage show.
String captionTitle(TuneController tune) =>
    tune.playback.item?.title ?? tune.playback.generator?.name ?? '';

/// The mono channel line used by the mini-stage.
String captionLabel(TuneController tune) {
  final at = tune.position;
  return at >= 0 ? 'CH ${(at + 1).toString().padLeft(2, '0')} · ${tune.channel.name}' : 'Now playing';
}
