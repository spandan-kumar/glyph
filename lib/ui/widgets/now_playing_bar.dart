import 'package:flutter/material.dart';

import '../../features/games/core/game_generator.dart';
import '../../features/games/game_page.dart';
import '../actions.dart';
import '../scope.dart';
import '../theme.dart';
import 'led_matrix_view.dart';
import 'now_playing_sheet.dart';

/// Mini player pinned above the navigation bar, like a music app.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback;
    return ListenableBuilder(
      listenable: Listenable.merge([playback, scope.devices]),
      builder: (context, _) {
        if (playback.generator == null) return const SizedBox.shrink();
        final title = playback.item?.title ?? playback.generator!.name;
        final canStream = scope.devices.isConnected;

        return GestureDetector(
          onTap: () {
            final g = playback.generator;
            // A running game reopens its controller instead of the generic sheet.
            if (g is GameGenerator) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => GamePage(def: g.def)));
            } else {
              showNowPlayingSheet(context);
            }
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: GlyphColors.surfaceHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: GlyphColors.outline),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: LedMatrixView(
                    frame: playback.frame,
                    repaint: playback.frameTick,
                    borderRadius: 8,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        playback.isStreaming
                            ? 'Live on ${scope.devices.info?.name ?? 'matrix'}'
                            : canStream
                                ? 'Preview only'
                                : 'Preview only · no matrix connected',
                        style: TextStyle(
                          fontSize: 12,
                          color: playback.isStreaming
                              ? GlyphColors.accent
                              : GlyphColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canStream)
                  IconButton(
                    tooltip: playback.isStreaming ? 'Stop streaming' : 'Stream to matrix',
                    onPressed: () => playback.isStreaming
                        ? GlyphActions.stopStreaming(context)
                        : GlyphActions.ensureStreaming(context),
                    icon: Icon(
                      playback.isStreaming ? Icons.cast_connected : Icons.cast,
                      color: playback.isStreaming ? GlyphColors.accent : null,
                    ),
                  ),
                IconButton(
                  tooltip: playback.isPlaying ? 'Pause' : 'Play',
                  onPressed: playback.isPlaying ? playback.pause : playback.resume,
                  icon: Icon(playback.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
