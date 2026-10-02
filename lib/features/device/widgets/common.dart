import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../ui/theme.dart';
import '../../../wled/presets.dart';
import '../device_manager.dart';

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: GlyphColors.textMuted,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyNote extends StatelessWidget {
  const EmptyNote({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, size: 40, color: GlyphColors.textMuted),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: GlyphColors.textMuted),
        ),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}

/// A note in a tinted box, e.g. "runs without your phone".
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.color = GlyphColors.accent,
  });

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.highlight = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: highlight ? GlyphColors.primary.withValues(alpha: 0.14) : GlyphColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: highlight ? GlyphColors.primary.withValues(alpha: 0.6) : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        leading: leading,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: GlyphColors.textMuted, fontSize: 13),
              ),
        trailing: trailing,
        onTap: onTap,
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
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: GlyphColors.danger) : null,
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
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: widget.maxLength,
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
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

/// Runs [task], showing its error as a snackbar. Returns whether it worked.
Future<bool> guarded(BuildContext context, Future<void> Function() task, {String? done}) async {
  try {
    await task();
    if (done != null && context.mounted) toast(context, done);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '$e'.replaceFirst('WledException: ', ''));
    return false;
  }
}

/// Square thumbnail of a GIF stored on the matrix, fetched once and animated
/// with crisp pixels.
class GifThumb extends StatelessWidget {
  const GifThumb({super.key, required this.manager, required this.name, this.size = 44});

  final DeviceManager manager;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => _Frame(
    size: size,
    child: FutureBuilder<Uint8List>(
      future: manager.gif(name),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return Icon(
            snap.hasError ? Icons.broken_image_outlined : Icons.gif_box_outlined,
            size: size * 0.5,
            color: GlyphColors.textMuted,
          );
        }
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) =>
              Icon(Icons.broken_image_outlined, size: size * 0.5, color: GlyphColors.textMuted),
        );
      },
    ),
  );
}

/// Thumbnail for any preset: the GIF it plays, or an icon tinted with its
/// colour.
class PresetThumb extends StatelessWidget {
  const PresetThumb({super.key, required this.manager, required this.preset, this.size = 44});

  final DeviceManager manager;
  final WledPreset preset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gif = preset.gifName;
    if (gif != null && manager.files.keys.any((f) => f.toLowerCase() == '/${gif.toLowerCase()}')) {
      return GifThumb(manager: manager, name: gif, size: size);
    }
    final c = preset.primaryColor;
    final tint = c != null && c != 0 ? Color(0xFF000000 | c) : GlyphColors.primary;
    final icon = switch (preset.kind) {
      PresetKind.playlist => Icons.queue_music_rounded,
      PresetKind.api => Icons.code_rounded,
      PresetKind.state when preset.turnsOff => Icons.power_settings_new_rounded,
      PresetKind.state when gif != null => Icons.gif_box_outlined,
      PresetKind.state => Icons.auto_awesome_rounded,
    };
    return _Frame(
      size: size,
      color: tint.withValues(alpha: 0.16),
      child: Icon(icon, size: size * 0.5, color: tint),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.size, required this.child, this.color = GlyphColors.surfaceHigh});

  final double size;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: size,
      height: size,
      color: color,
      alignment: Alignment.center,
      child: child,
    ),
  );
}
