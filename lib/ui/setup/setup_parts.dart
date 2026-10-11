import 'package:flutter/material.dart';

import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';

/// The shape of every wizard step: a scrolling body (title, one supporting
/// line, a visual) and a sticky action area at the bottom for the one
/// primary action, a secondary one and an optional text link.
class StepLayout extends StatelessWidget {
  const StepLayout({
    super.key,
    required this.title,
    this.line,
    this.children = const [],
    this.primary,
    this.secondary,
    this.link,
    this.gap = 24,
  });

  final String title;
  final String? line;
  final List<Widget> children;
  final Widget? primary, secondary, link;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          children: [
            Semantics(header: true, child: Text(title, style: LbType.title)),
            if (line != null) ...[const SizedBox(height: 8), Text(line!, style: LbType.small)],
            SizedBox(height: gap),
            ...children,
          ],
        ),
      ),
      if (primary != null || secondary != null || link != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?primary,
              if (secondary != null) ...[const SizedBox(height: 8), secondary!],
              if (link != null) ...[const SizedBox(height: 4), link!],
            ],
          ),
        ),
    ],
  );
}

/// The one primary action: 52px, paper fill.
class SetupPrimary extends StatelessWidget {
  const SetupPrimary(this.label, {super.key, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Lb.cta)),
    onPressed: busy ? null : onPressed,
    child: busy
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LedSpinner(color: Lb.text2),
              const SizedBox(width: 10),
              Text(label),
            ],
          )
        : Text(label),
  );
}

class SetupSecondary extends StatelessWidget {
  const SetupSecondary(this.label, {super.key, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Lb.touch)),
    onPressed: onPressed,
    child: Text(label),
  );
}

/// A quiet text action under the buttons.
class SetupLink extends StatelessWidget {
  const SetupLink(this.label, {super.key, required this.onPressed, this.danger = false});

  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      minimumSize: const Size.fromHeight(Lb.touch),
      foregroundColor: danger ? Lb.danger : Lb.text2,
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

/// A busy screen: LED spinner and a line of words.
class BusyBody extends StatelessWidget {
  const BusyBody(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LedSpinner(size: 36),
          const SizedBox(height: 20),
          Text(text, textAlign: TextAlign.center, style: LbType.heading),
        ],
      ),
    ),
  );
}

/// Pick-one chip: inverted when selected, at least 48px.
class SetupChip extends StatelessWidget {
  const SetupChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? Lb.text : Lb.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Lb.rControl),
        side: BorderSide(color: selected ? Lb.text : Lb.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Lb.rControl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: Lb.touch, minHeight: Lb.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: 1,
              child: Text(label, style: LbType.bodyStrong.copyWith(color: selected ? Lb.ink : Lb.text)),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A one-line text field on the Lightbox surface.
InputDecoration fieldDecoration(String label, {Widget? suffix, String? hint}) =>
    InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix);

enum ProgressState { done, current, waiting }

/// One row of a progress list: a check, the spinner or a dim dot, then words.
class StepStatusRow extends StatelessWidget {
  const StepStatusRow({super.key, required this.label, required this.state});

  final String label;
  final ProgressState state;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Semantics(
      label: '$label, ${switch (state) {
        ProgressState.done => 'done',
        ProgressState.current => 'in progress',
        ProgressState.waiting => 'waiting',
      }}',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: switch (state) {
                ProgressState.done => const Icon(Icons.check_sharp, size: 16, color: Lb.ok),
                ProgressState.current => const LedSpinner(size: 16),
                ProgressState.waiting => Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Lb.ledOff),
                ),
              },
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: LbType.body.copyWith(color: state == ProgressState.waiting ? Lb.text2 : Lb.text),
            ),
          ),
        ],
      ),
    ),
  );
}
