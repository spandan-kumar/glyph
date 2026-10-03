import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import '../widgets/led_matrix_view.dart';
import 'stage_deck.dart';
import 'tune_controller.dart';

/// The Stage collapsed into a slim pinned bar: a live panel, the channel
/// line and title, and ‹ › to keep surfing. Replaces the old bottom
/// now-playing bar.
class MiniStage extends StatelessWidget {
  const MiniStage({super.key, this.onTap, this.panelKey});

  final VoidCallback? onTap;

  /// Lets the screen fly tiles into the mini panel.
  final GlobalKey? panelKey;

  @override
  Widget build(BuildContext context) {
    final playback = AppScope.of(context).playback;
    final tune = TuneScope.of(context);
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: Lb.panel.withValues(alpha: 0.96),
          border: const Border(bottom: Lb.hairline),
        ),
        child: SizedBox(
          height: 60,
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
                          dimension: 44,
                          child: Center(
                            child: LedMatrixView(
                              frame: playback.frame,
                              repaint: playback.frameTick,
                              bezel: true,
                              borderRadius: 3,
                            ),
                          ),
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
              IconButton(
                tooltip: 'Previous',
                onPressed: () => tune.surf(context, -1),
                icon: const Icon(Icons.chevron_left_rounded, color: Lb.text2),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed: () => tune.surf(context, 1),
                icon: const Icon(Icons.chevron_right_rounded, color: Lb.text),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
