import 'package:flutter/material.dart';

import '../../../app/devices.dart';
import '../../../ui/design/parts.dart';
import '../../../ui/design/tokens.dart';
import '../../../ui/design/type.dart';
import '../../../wled/presets.dart';
import '../device_manager.dart';
import 'common.dart';

/// What's saved on the device: a grid of LED tiles. Tap plays it on the
/// device; long-press to rename, delete or play it at power-on.
class KeptSection extends StatelessWidget {
  const KeptSection({super.key, required this.manager, required this.store, required this.onPlay});

  final DeviceManager manager;
  final DeviceStore store;

  /// Plays a saved item (stops live streaming first).
  final Future<void> Function(int id) onPlay;

  @override
  Widget build(BuildContext context) {
    final items = keptItems(manager);
    if (!manager.isLoaded && manager.isLoading) {
      return const EmptyNote(text: 'Looking at what\'s saved on your device…');
    }
    if (manager.error != null && items.isEmpty) {
      return EmptyNote(
        text: 'Couldn\'t read what\'s saved on your device.',
        action: OutlinedButton(onPressed: manager.load, child: const Text('Try again')),
      );
    }
    if (items.isEmpty) {
      return const EmptyNote(
        text: 'Nothing saved yet. Find something you love and tap Send to device — '
            'it plays here even without your phone.',
      );
    }
    final accent = accentOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 520 ? 4 : 3;
        const gap = 10.0;
        final tile = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final p in items)
              SizedBox(
                // Tiles follow their item when the grid shifts after a delete.
                key: ValueKey(p.id),
                width: tile,
                child: KeptTile(
                  manager: manager,
                  preset: p,
                  accent: accent,
                  missing: manager.isFileMissing(p),
                  active: store.presetId == p.id && store.isOn == true && !store.playlistRunning,
                  onTap: manager.isFileMissing(p)
                      ? () => _menu(context, p)
                      : () => guarded(context, () => onPlay(p.id)),
                  onLongPress: () => _menu(context, p),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _menu(BuildContext context, WledPreset p) async {
    if (manager.isFileMissing(p)) {
      final v = await showActions(
        context,
        title: p.name,
        subtitle: 'Its animation file is gone from your device, so it can\'t play. '
            'Send it again from Display, or delete it.',
        actions: const [ActionItem('Delete', Icons.delete_outline_sharp, 'delete', danger: true)],
      );
      if (v == 'delete' && context.mounted) await deleteKept(context, manager, p);
      return;
    }
    final boot = manager.schedule != null && manager.powerOnLook == p.id;
    final v = await showActions(
      context,
      title: p.name,
      subtitle: boot ? 'Plays when your device powers on.' : 'Saved on your device.',
      actions: [
        const ActionItem('Play now', Icons.play_arrow_sharp, 'play'),
        const ActionItem('Rename', Icons.edit_sharp, 'rename'),
        if (!boot && manager.schedule != null)
          const ActionItem('Play when it powers on', Icons.power_sharp, 'boot'),
        const ActionItem('Delete', Icons.delete_outline_sharp, 'delete', danger: true),
      ],
    );
    if (!context.mounted) return;
    switch (v) {
      case 'play':
        await guarded(context, () => onPlay(p.id));
      case 'rename':
        await _rename(context, p);
      case 'boot':
        await guarded(
          context,
          () => manager.setBootPreset(p.id),
          done: '“${p.name}” will play when your device powers on',
        );
      case 'delete':
        await deleteKept(context, manager, p);
    }
  }

  Future<void> _rename(BuildContext context, WledPreset p) async {
    final name = await promptText(context, title: 'Rename', initial: p.name);
    if (name == null || name.isEmpty || name == p.name || !context.mounted) return;
    await guarded(context, () => manager.rename(p.id, name), done: 'Renamed to “$name”');
  }
}

/// Asks, then removes [p] from the device (and its GIF when nothing else
/// uses it and the user agrees).
Future<void> deleteKept(BuildContext context, DeviceManager manager, WledPreset p) async {
  final gif = p.gifName;
  final sharedGif = gif != null && manager.presetsUsingFile(gif).any((x) => x.id != p.id);
  final gifSize = gif == null ? null : manager.files['/$gif'];
  final usedBy = [
    ...manager.playlistsUsing(p.id).map((x) => 'the show “${x.name}”'),
    if (manager.timersUsing(p.id).isNotEmpty) 'a routine',
    if (manager.schedule != null && manager.powerOnLook == p.id) 'power-on',
  ];
  var withFile = gif != null && gifSize != null && !sharedGif;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Delete “${p.name}”?', style: LbType.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('It will be removed from your device.', style: LbType.body.copyWith(color: Lb.text2)),
            if (usedBy.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'It\'s part of ${usedBy.join(', ')}.',
                  style: LbType.small.copyWith(color: Lb.phosphor),
                ),
              ),
            if (gif != null && gifSize != null && !sharedGif)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: withFile,
                onChanged: (v) => setState(() => withFile = v ?? false),
                title: Text('Also free up ${formatBytes(gifSize)}', style: LbType.body),
                subtitle: Text('Deletes its animation file too', style: LbType.small),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Lb.danger, foregroundColor: Lb.ink),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  await guarded(
    context,
    () => manager.deletePreset(p.id, withFile: withFile),
    done: 'Deleted “${p.name}”',
  );
}

/// One saved item: an LED tile with its picture and name.
class KeptTile extends StatelessWidget {
  const KeptTile({
    super.key,
    required this.manager,
    required this.preset,
    this.active = false,
    this.missing = false,
    this.accent = Lb.phosphor,
    this.onTap,
    this.onLongPress,
  });

  final DeviceManager manager;
  final WledPreset preset;
  final bool active;

  /// Its animation file was deleted: a dark panel labelled "File missing".
  final bool missing;
  final Color accent;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: preset.name,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: LedBezel(
              active: active && !missing,
              accent: accent,
              child: missing
                  ? const Stack(
                      fit: StackFit.expand,
                      children: [
                        DotGlyph(color: Lb.text3, dim: true),
                        Center(child: MonoLabel('File missing', color: Lb.text2)),
                      ],
                    )
                  : PresetThumb(manager: manager, preset: preset),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (active) ...[StatusDot(on: true, color: accent), const SizedBox(width: 6)],
              Expanded(
                child: Text(
                  preset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LbType.small.copyWith(color: missing ? Lb.text3 : (active ? Lb.text : Lb.text2)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
