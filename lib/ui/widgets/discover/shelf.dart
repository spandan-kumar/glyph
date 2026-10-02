import 'package:flutter/material.dart';

import '../../../library/catalog.dart';
import '../../../library/user_library.dart';
import '../../theme.dart';
import 'animation_card.dart';

/// A titled, horizontally scrolling row of cards. Built lazily, so only the
/// visible cards (and their previews) exist.
class Shelf extends StatelessWidget {
  const Shelf({
    super.key,
    required this.title,
    required this.items,
    required this.library,
    this.icon,
    this.onSeeAll,
  });

  static const cardWidth = 128.0;
  static const height = 176.0;

  final String title;
  final IconData? icon;
  final List<LibraryItem> items;
  final UserLibrary library;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: GlyphColors.accent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              if (onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(
              width: cardWidth,
              child: AnimationCard(item: items[i], library: library, showCategory: false),
            ),
          ),
        ),
      ],
    );
  }
}
