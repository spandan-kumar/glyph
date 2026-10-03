import 'package:flutter/material.dart';

import '../design/ambient.dart';
import '../design/knob.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../screens/home_shell.dart';

// Shared chrome for the Make studio and the feature screens it opens
// (editor, text, import, music, games). Lives here rather than in
// lib/ui/design so the studio owns it; promote if other places need it.

/// The room's accent colour without subscribing to its changes (falls back
/// to phosphor when there's no ambient scope, e.g. in isolated tests).
Color readAccent(BuildContext context) {
  final scope = context.getInheritedWidgetOfExactType<AmbientScope>();
  return scope?.notifier?.accent ?? Lb.phosphor;
}

/// Crisp rectangle for buttons, chips and menus in the studio (UX: matrix
/// geometry). LED dots and rotary knobs are the only round things.
const studioShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(Lb.rControl)),
);

/// [studioShape] with a hairline, for outlined controls.
const studioOutlinedShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(Lb.rControl)),
  side: Lb.hairline,
);

/// Square icon buttons (M3 defaults to circles).
final ButtonStyle studioIconStyle = IconButton.styleFrom(shape: studioShape);

/// Square segmented buttons (M3 defaults to a stadium).
final ButtonStyle studioSegmentStyle = SegmentedButton.styleFrom(shape: studioShape);

/// Square-cornered popup menus (matches the app theme's menus).
const studioMenuShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel)),
  side: Lb.hairline,
);

/// A feature screen pushed on top of the shell: the room glow continues
/// behind a transparent app bar with a quiet heading title.
class StudioScaffold extends StatelessWidget {
  const StudioScaffold({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    required this.body,
    this.bottomBar,
    this.titleSpacing,
  }) : assert(title != null || titleWidget != null);

  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget body;
  final Widget? bottomBar;
  final double? titleSpacing;

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleSpacing: titleSpacing,
        title: titleWidget ?? Text(title!, style: LbType.heading),
        actions: actions,
      ),
      body: body,
      bottomNavigationBar: bottomBar,
    );
    final ambient = context.getInheritedWidgetOfExactType<AmbientScope>() != null;
    return ambient
        ? AmbientBackdrop(child: scaffold)
        : ColoredBox(color: Lb.ink, child: scaffold);
  }
}

/// A group of controls: a mono label over a hairline panel.
class StudioGroup extends StatelessWidget {
  const StudioGroup({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  });

  final String label;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Row(children: [Expanded(child: MonoLabel(label)), ?trailing]),
            ),
            LbPanel(padding: padding, child: child),
          ],
        ),
      );
}

/// A [Knob] tinted by the room, with an optional value readout.
class StudioKnob extends StatelessWidget {
  const StudioKnob({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.valueText,
    this.size = 60,
  });

  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String? valueText;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Knob(
            label: label,
            value: value.clamp(min, max),
            min: min,
            max: max,
            size: size,
            accent: readAccent(context),
            onChanged: onChanged,
          ),
          if (valueText != null) ...[
            const SizedBox(height: 2),
            Text(valueText!, style: LbType.mono.copyWith(fontSize: 11)),
          ],
        ],
      );
}

/// Knobs sharing a row evenly; each shrinks to fit rather than overflow.
class StudioKnobRow extends StatelessWidget {
  const StudioKnobRow({super.key, required this.knobs});

  final List<Widget> knobs;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (final k in knobs)
          Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: k)),
      ]);
}

/// "On your device": a small lit dot breathing next to a mono label.
class LivePulse extends StatefulWidget {
  const LivePulse({super.key, this.label = 'On your device', this.color});

  final String label;
  final Color? color;

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? readAccent(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox.square(
        dimension: 16,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(painter: _PulsePainter(_c.value, accent)),
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(widget.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LbType.label.copyWith(color: accent)),
      ),
    ]);
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
        c,
        3 + 5 * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.7 * (1 - t)));
    canvas.drawCircle(c, 5, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(c, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.color != color;
}

/// One row of an action sheet.
class StudioAction {
  const StudioAction(this.icon, this.label, this.onTap, {this.subtitle, this.danger = false});

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;
}

/// A quiet action sheet: optional header, then icon + verb rows. The sheet
/// closes before the chosen action runs.
Future<void> showStudioActions(
  BuildContext context, {
  Widget? header,
  required List<StudioAction> actions,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null)
                Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), child: header),
              if (header != null) const Divider(),
              for (final a in actions)
                _ActionRow(
                  action: a,
                  onTap: () {
                    Navigator.pop(ctx);
                    a.onTap();
                  },
                ),
            ],
          ),
        ),
      ),
    );

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.onTap});

  final StudioAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = action.danger ? Lb.danger : Lb.text;
    return InkWell(
      borderRadius: BorderRadius.circular(Lb.rControl),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(children: [
          Icon(action.icon, size: 20, color: action.danger ? Lb.danger : Lb.text2),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(action.label, style: LbType.body.copyWith(color: color)),
              if (action.subtitle != null) Text(action.subtitle!, style: LbType.small),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Shows a short floating message.
void studioToast(BuildContext context, String msg, {SnackBarAction? action}) =>
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));

/// Takes the person to the Device tab to connect. Works from a tab (the
/// shell is an ancestor) and from a screen pushed over the shell (the shell
/// is a sibling route underneath: switch its tab, then pop back to it).
void goToMatrix(BuildContext context) {
  if (context.findAncestorWidgetOfExactType<HomeShell>() != null) {
    HomeShell.go(context, 2);
    return;
  }
  final nav = Navigator.maybeOf(context);
  Element? inside;
  void visit(Element e) {
    if (inside != null) return;
    if (e.widget is HomeShell) {
      e.visitChildren((c) => inside ??= c);
      return;
    }
    e.visitChildren(visit);
  }

  if (nav != null) (nav.context as Element).visitChildren(visit);
  final target = inside;
  if (nav == null || target == null) {
    studioToast(context, 'Connect a device in the Device tab.');
    return;
  }
  HomeShell.go(target, 2);
  nav.popUntil((r) => r.isFirst);
}
