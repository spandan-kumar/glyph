import 'dart:math';

import 'package:flutter/material.dart';

import '../design/ambient.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import '../widgets/led_matrix_view.dart';
import 'stage_deck.dart';
import 'tune_controller.dart';

/// The Stage collapsed into a slim pinned bar: a live panel, the channel
/// line and title, and ‹ › to keep surfing. Replaces the old bottom
/// now-playing bar.
///
/// On Display the panel itself is the morphing Stage flying into the bar
/// ([livePanel] false leaves its slot empty); on pushed pages the bar draws
/// its own small panel.
class MiniStage extends StatelessWidget {
  const MiniStage({super.key, this.onTap, this.panelKey, this.livePanel = true,
      this.onSend, this.keepState = KeepState.idle});

  /// Height of the bar, below the status-bar inset.
  static const height = 60.0;

  /// The square slot the panel sits in.
  static const panel = 44.0;

  /// Where the panel sits, in the coordinates of whatever the bar's top-left
  /// is laid out at, with the bar pushed down by [top] (the status bar). A
  /// non-square frame is fitted inside the square slot.
  static Rect panelRect({required double top, required double aspect}) {
    final slot = Rect.fromLTWH(Lb.gutter, top + (height - panel) / 2, panel, panel);
    final w = aspect >= 1 ? panel : panel * aspect;
    final h = aspect >= 1 ? panel / aspect : panel;
    return Rect.fromCenter(center: slot.center, width: max(1, w), height: max(1, h));
  }

  final VoidCallback? onTap, onSend;
  final KeepState keepState;

  /// Lets the screen fly tiles into the mini panel.
  final GlobalKey? panelKey;

  /// Draw the small live panel (false when the Stage morphs into the slot).
  final bool livePanel;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback;
    final tune = TuneScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([playback, scope.devices]),
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: Lb.panel.withValues(alpha: 0.96),
          border: const Border(bottom: Lb.hairline),
        ),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Back to the Stage',
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Lb.gutter, 8, 8, 8),
                      child: Row(children: [
                        SizedBox.square(
                          key: panelKey,
                          dimension: panel,
                          child: livePanel
                              ? Center(
                                  child: LedMatrixView(
                                    frame: playback.frame,
                                    repaint: playback.frameTick,
                                    bezel: true,
                                    borderRadius: Lb.rTile,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(captionLabel(tune).toUpperCase(),
                                  style: LbType.label.copyWith(fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(captionTitle(tune),
                                  style: LbType.heading, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
              SquareKey(
                icon: Icons.chevron_left_sharp,
                label: 'Previous',
                color: Lb.text2,
                outlined: false,
                onTap: () => tune.surf(context, -1),
              ),
              SquareKey(
                icon: Icons.chevron_right_sharp,
                label: 'Next',
                outlined: false,
                onTap: () => tune.surf(context, 1),
              ),
              if (onSend != null && scope.devices.isConnected &&
                  (scope.devices.caps?.canPlayGifs ?? false) &&
                  !(playback.generator?.liveOnly ?? true))
                SendButton(
                  compact: true,
                  state: keepState,
                  accent: AmbientScope.of(context).accent,
                  onTap: keepState == KeepState.checking || keepState == KeepState.beaming ? null : onSend,
                ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
