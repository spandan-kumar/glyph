import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Placeholder: the Matrix/onboarding agent replaces this with the first-run
// flow (UX.md J1). Keep the public API: OnboardingFlow(onDone), and the
// static helpers.
class OnboardingFlow extends StatelessWidget {
  const OnboardingFlow({super.key, required this.onDone});

  final VoidCallback onDone;

  static const prefsKey = 'onboarding.done.v1';

  static Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool(prefsKey) ?? false;

  static Future<void> markDone() async =>
      (await SharedPreferences.getInstance()).setBool(prefsKey, true);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              await markDone();
              onDone();
            },
            child: const Text('Start'),
          ),
        ),
      );
}
