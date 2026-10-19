import 'package:flutter/material.dart';

import '../features/device/widgets/common.dart';
import 'community/glyph_menu.dart';
import 'design/tokens.dart';
import 'design/type.dart';
import 'screens/home_shell.dart';

const cantSeeItLabel = 'Can\'t see it?';

/// The toast action that opens [showCantSeeIt]. Built from the app's root,
/// so it still works after the screen that showed the toast has gone (the
/// first vibe ends onboarding straight away).
SnackBarAction cantSeeItAction(BuildContext context) {
  final root = Navigator.maybeOf(context, rootNavigator: true)?.overlay?.context ?? context;
  return SnackBarAction(label: cantSeeItLabel, onPressed: () {
    if (root.mounted) showCantSeeIt(root);
  });
}

/// What to check when a look didn't reach the device, and where to go next.
Future<void> showCantSeeIt(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(cantSeeItLabel, style: LbType.title),
              const SizedBox(height: 14),
              const Note(text: 'Check your device is plugged in and switched on.'),
              const Note(text: 'Your phone and device need to be on the same Wi-Fi.'),
              const Note(text: 'It\'s still playing here on your phone, so nothing is lost.'),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Lb.cta)),
                onPressed: () {
                  Navigator.pop(ctx);
                  HomeShell.goFromAnywhere(2);
                },
                child: const Text('Check my device'),
              ),
              const SizedBox(height: 4),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(Lb.touch),
                  foregroundColor: Lb.text2,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  if (context.mounted) sendFeedback(context);
                },
                child: const Text('Send a report'),
              ),
            ],
          ),
        ),
      ),
    );
