import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/community.dart';
import '../../features/device/widgets/common.dart';
import '../design/tokens.dart';
import 'glyph_menu.dart';

/// The release notes for [version], ending with two quiet community links.
Future<void> showWhatsNewSheet(BuildContext context, String version, List<String> lines) {
  HapticFeedback.selectionClick(); // opening a sheet is a pick
  return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        void go(Future<Uri> Function() link) async {
          Navigator.pop(ctx);
          final uri = await link();
          if (context.mounted) await openCommunityLink(context, uri);
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetTitle('What’s new', subtitle: 'Glyph $version'),
                for (final l in lines) Note(text: l, lit: true, color: Lb.text2),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => go(() async => Community.showAndTell),
                      child: const Text('Share your setup'),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => go(() async => Community.idea(Diagnostics(env: await Community.env()))),
                      child: const Text('Send an idea'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
}
