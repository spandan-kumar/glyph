import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ambient.dart';
import 'tokens.dart';
import 'type.dart';

/// Glyph's on/off switch: a sharp rectangular track with a square block
/// that slides across, an LED in it lighting up in the room colour when on.
/// Replaces Material's rounded Switch everywhere.
class LbToggle extends StatelessWidget {
  const LbToggle({super.key, required this.value, required this.onChanged, this.accent});

  final bool value;

  /// Null disables the toggle (drawn dimmed).
  final ValueChanged<bool>? onChanged;

  /// Defaults to the room's accent.
  final Color? accent;

  static const width = 42.0, height = 24.0, _pad = 3.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final on = accent ?? context.getInheritedWidgetOfExactType<AmbientScope>()?.notifier?.accent ?? Lb.phosphor;
    const block = height - 2 * _pad;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: Lb.fast,
            curve: Lb.ease,
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: value ? on.withValues(alpha: 0.22) : Lb.ink,
              borderRadius: BorderRadius.circular(Lb.rControl),
              border: Border.all(color: value ? on.withValues(alpha: 0.7) : Lb.line),
            ),
            child: AnimatedAlign(
              duration: Lb.fast,
              curve: Lb.ease,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(_pad - 1),
                child: AnimatedContainer(
                  duration: Lb.fast,
                  width: block,
                  height: block,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value ? on : Lb.raised,
                    borderRadius: BorderRadius.circular(Lb.rTile),
                    border: value ? null : Border.all(color: Lb.line),
                  ),
                  // The LED: dark when off, a lit dot on the lit block when on.
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value ? Lb.ink.withValues(alpha: 0.55) : Lb.ledOff,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row: title (and optional subtitle) with an [LbToggle] at the
/// end. The whole row toggles. Replaces SwitchListTile.
class LbToggleTile extends StatelessWidget {
  const LbToggleTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: Padding(
            padding: padding,
            child: Row(children: [
              if (leading != null) ...[leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: LbType.body.copyWith(color: onChanged == null ? Lb.text3 : Lb.text)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: LbType.small),
                  ],
                ]),
              ),
              const SizedBox(width: 12),
              LbToggle(value: value, onChanged: onChanged),
            ]),
          ),
        ),
      );
}
