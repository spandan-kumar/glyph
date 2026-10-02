import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../library/catalog.dart';
import '../../../library/user_library.dart';
import '../../actions.dart';
import '../../scope.dart';
import '../../theme.dart';
import '../live_preview.dart';

/// A library item with a live preview. Tap plays it; the heart (or a long
/// press) toggles it as a favourite.
class AnimationCard extends StatelessWidget {
  const AnimationCard({super.key, required this.item, required this.library, this.showCategory = true});

  final LibraryItem item;
  final UserLibrary library;
  final bool showCategory;

  void _toggle(BuildContext context) {
    HapticFeedback.selectionClick();
    final adding = !library.isFavourite(item.id);
    library.toggleFavourite(item.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(adding ? 'Added "${item.title}" to favourites' : 'Removed from favourites'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final playback = AppScope.of(context).playback;
    return ListenableBuilder(
      listenable: Listenable.merge([playback, library]),
      builder: (context, _) {
        final playing = playback.item?.id == item.id;
        final fav = library.isFavourite(item.id);
        return GestureDetector(
          onTap: () => GlyphActions.play(context, item),
          onLongPress: () => _toggle(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: GlyphColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: playing ? GlyphColors.primary : GlyphColors.outline,
                width: playing ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The preview takes whatever height the text leaves, so the
                // card never overflows at any text scale or grid width.
                Expanded(
                  child: Stack(
                    children: [
                      Center(child: LivePreview(item: item)),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: _HeartButton(on: fav, onTap: () => _toggle(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (showCategory)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                    child: Text(item.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: GlyphColors.textMuted)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeartButton extends StatelessWidget {
  const _HeartButton({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: on ? 'Remove from favourites' : 'Add to favourites',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: GlyphColors.background.withValues(alpha: 0.65),
              shape: BoxShape.circle,
            ),
            child: Icon(on ? Icons.favorite : Icons.favorite_border,
                size: 16, color: on ? GlyphColors.danger : GlyphColors.textMuted),
          ),
        ),
      );
}
