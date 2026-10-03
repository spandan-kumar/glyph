
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/design/ambient.dart';
import '../../../ui/design/parts.dart';
import '../../../ui/design/tokens.dart';
import '../../../ui/design/type.dart';
import '../../../wled/presets.dart';
import '../device_manager.dart';

/// Friendly name for something saved on the matrix ("Turn off" for the
/// switch-off entry, a gentle note when it has gone).
String keptName(DeviceManager m, int id) {
  final p = m.preset(id);
  if (p == null) return 'something removed';
  if (p.turnsOff) return 'Turn off';
  return p.name;
}

/// Things worth showing as "Kept": animations, GIFs and saved looks. Shows,
/// raw web commands and the plain "off" entry are left out.
List<WledPreset> keptItems(DeviceManager m) => [
  for (final p in m.presets)
    if (p.kind == PresetKind.state && !p.turnsOff) p,
];

/// A quiet centred note for empty sections.
class EmptyNote extends StatelessWidget {
  const EmptyNote({super.key, required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Lb.rPanel),
      border: Border.all(color: Lb.line),
    ),
    child: Column(
      children: [
        Text(text, textAlign: TextAlign.center, style: LbType.small),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}

/// A one-line hint with a small LED dot, e.g. "runs without your phone".
class Note extends StatelessWidget {
  const Note({super.key, required this.text, this.color = Lb.text3, this.lit = false});

  final String text;
  final Color color;
  final bool lit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 10),
          child: StatusDot(on: lit, color: color),
        ),
        Expanded(
          child: Text(text, style: LbType.small.copyWith(color: lit ? Lb.text2 : Lb.text3)),
        ),
      ],
    ),
  );
}

/// A hairline row: optional leading, title, subtitle, trailing.
class Row1 extends StatelessWidget {
  const Row1({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LbType.bodyStrong.copyWith(color: danger ? Lb.danger : null),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LbType.small,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    ),
  );
}

/// Rows stacked in one hairline panel, separated by hairlines.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LbPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, c) in children.indexed) ...[if (i > 0) const Divider(height: 1), c],
      ],
    ),
  );
}

/// Title block at the top of a sheet.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: LbType.title),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: LbType.small),
        ],
      ],
    ),
  );
}

/// A sheet of actions (long-press menus).
class ActionItem {
  const ActionItem(this.label, this.icon, this.value, {this.danger = false});
  final String label;
  final IconData icon;
  final String value;
  final bool danger;
}

Future<String?> showActions(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<ActionItem> actions,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle(title, subtitle: subtitle),
            for (final a in actions)
              InkWell(
                borderRadius: BorderRadius.circular(Lb.rControl),
                onTap: () => Navigator.pop(ctx, a.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(a.icon, size: 20, color: a.danger ? Lb.danger : Lb.text2),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          a.label,
                          style: LbType.body.copyWith(color: a.danger ? Lb.danger : Lb.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
  bool danger = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: LbType.title),
      content: Text(message, style: LbType.body.copyWith(color: Lb.text2)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: Lb.danger, foregroundColor: Lb.ink)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  int maxLength = 32,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PromptDialog(title: title, initial: initial, hint: hint, maxLength: maxLength),
);

/// Owns its controller so it outlives the dialog's exit animation.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.maxLength,
  });

  final String title, initial, hint;
  final int maxLength;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title, style: LbType.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: widget.maxLength,
      style: LbType.body,
      decoration: InputDecoration(hintText: widget.hint),
      onSubmitted: (v) => Navigator.pop(context, v.trim()),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Runs [task], showing its error as a snackbar. Returns whether it worked.
Future<bool> guarded(BuildContext context, Future<void> Function() task, {String? done}) async {
  try {
    await task();
    if (done != null && context.mounted) toast(context, done);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
    return false;
  }
}

/// Error text without library prefixes or device jargon.
String friendlyError(Object e) {
  final s = '$e'.replaceFirst('WledException: ', '').replaceFirst('ClientException: ', '');
  if (s.contains('preset slots')) return 'Your matrix is full. Remove something first.';
  if (s.contains('SocketException') || s.contains('TimeoutException') || s.contains('offline')) {
    return 'Couldn\'t reach your matrix. Is it on?';
  }
  return s;
}

/// An LED tile frame: a dark bezel with a hairline, lit border when active.
class LedBezel extends StatelessWidget {
  const LedBezel({super.key, required this.child, this.active = false, this.accent = Lb.phosphor});

  final Widget child;
  final bool active;
  final Color accent;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Lb.fast,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFF050403),
      borderRadius: BorderRadius.circular(Lb.rTile + 4),
      border: Border.all(color: active ? accent.withValues(alpha: 0.8) : Lb.line),
      boxShadow: active ? [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 14)] : null,
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(Lb.rTile), child: child),
  );
}

/// A GIF stored on the matrix, fetched once and shown with crisp pixels.
/// Without [size] it fills its parent.
class GifThumb extends StatelessWidget {
  const GifThumb({super.key, required this.manager, required this.name, this.size});

  final DeviceManager manager;
  final String name;
  final double? size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: FutureBuilder<Uint8List>(
      future: manager.gif(name),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return DotGlyph(color: Lb.text3, dim: !snap.hasError);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const DotGlyph(color: Lb.text3),
        );
      },
    ),
  );
}

/// Thumbnail for anything kept on the matrix: its GIF when there is one,
/// otherwise a soft LED glow in its colour. Without [size] it fills.
class PresetThumb extends StatelessWidget {
  const PresetThumb({super.key, required this.manager, required this.preset, this.size});

  final DeviceManager manager;
  final WledPreset preset;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final gif = preset.gifName;
    if (gif != null && manager.files.keys.any((f) => f.toLowerCase() == '/${gif.toLowerCase()}')) {
      return GifThumb(manager: manager, name: gif, size: size);
    }
    final c = preset.primaryColor;
    final tint = c != null && c != 0 ? Color(0xFF000000 | c) : Lb.phosphor;
    return SizedBox(
      width: size,
      height: size,
      child: DotGlyph(color: preset.turnsOff ? Lb.text3 : tint, seed: preset.id),
    );
  }
}

/// An 8×8 field of LED dots glowing from the middle, used where there is no
/// picture to show.
class DotGlyph extends StatelessWidget {
  const DotGlyph({super.key, required this.color, this.seed = 0, this.dim = false});

  final Color color;
  final int seed;
  final bool dim;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DotGlyphPainter(color, seed, dim), child: const SizedBox.expand());
}

class _DotGlyphPainter extends CustomPainter {
  _DotGlyphPainter(this.color, this.seed, this.dim);

  final Color color;
  final int seed;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF050403));
    const n = 8;
    final cell = size.shortestSide / n;
    final p = Paint();
    final ox = (seed * 37 % 5) - 2.0, oy = (seed * 53 % 5) - 2.0;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final dx = x - 3.5 - ox * 0.4, dy = y - 3.5 - oy * 0.4;
        final d = (dx * dx + dy * dy) / 20;
        final k = dim ? 0.0 : (1 - d).clamp(0.0, 1.0);
        p.color = k < 0.08 ? Lb.ledOff : color.withValues(alpha: 0.25 + 0.75 * k);
        canvas.drawCircle(Offset((x + 0.5) * cell, (y + 0.5) * cell), cell * 0.36, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGlyphPainter old) =>
      old.color != color || old.seed != seed || old.dim != dim;
}

/// Storage as a row of LED dots, lit for what's used.
class DotBar extends StatelessWidget {
  const DotBar({super.key, required this.fraction, this.color = Lb.text, this.dots = 32});

  final double fraction;
  final Color color;
  final int dots;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 10,
    child: CustomPaint(painter: _DotBarPainter(fraction.clamp(0, 1), color, dots)),
  );
}

class _DotBarPainter extends CustomPainter {
  _DotBarPainter(this.f, this.color, this.n);

  final double f;
  final Color color;
  final int n;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / n;
    final r = (step * 0.34).clamp(1.0, size.height / 2);
    final lit = (f * n).ceil();
    final on = Paint()..color = color, off = Paint()..color = Lb.ledOff;
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(Offset((i + 0.5) * step, size.height / 2), r, i < lit ? on : off);
    }
  }

  @override
  bool shouldRepaint(_DotBarPainter old) => old.f != f || old.color != color || old.n != n;
}

/// An accent colour from the ambient light when one is available.
/// Falls back to phosphor outside the app shell (tests, standalone pages).
Color accentOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<AmbientScope>()?.notifier?.accent ?? Lb.phosphor;
