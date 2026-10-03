import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

/// Instrument-panel label: DM Mono, uppercase, tracked.
class MonoLabel extends StatelessWidget {
  const MonoLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: color == null ? LbType.label : LbType.label.copyWith(color: color));
}

/// A section of a panel: mono label, optional trailing action, content.
class PanelSection extends StatelessWidget {
  const PanelSection({super.key, required this.label, required this.child, this.trailing, this.padding});

  final String label;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(Lb.gutter, 20, Lb.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: MonoLabel(label)),
            ?trailing,
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// A flat panel with a hairline border — the default container.
class LbPanel extends StatelessWidget {
  const LbPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Lb.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel)),
        side: Lb.hairline,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// A status dot (lit when [on]).
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.on, this.color = Lb.ok, this.size = 6});

  final bool on;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? color : Lb.text3,
          boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: size)] : null,
        ),
      );
}
