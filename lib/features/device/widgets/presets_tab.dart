import 'package:flutter/material.dart';

import '../../../app/devices.dart';
import '../../../ui/theme.dart';
import '../../../wled/presets.dart';
import '../device_manager.dart';
import 'common.dart';

/// Saved presets with thumbnails: tap to play, menu to rename or delete.
class PresetsTab extends StatelessWidget {
  const PresetsTab({super.key, required this.manager, required this.store, required this.onApply});

  final DeviceManager manager;
  final DeviceStore store;

  /// Applies a preset (stops live streaming first).
  final Future<void> Function(int id) onApply;

  @override
  Widget build(BuildContext context) {
    final presets = manager.playable;
    return RefreshIndicator(
      onRefresh: manager.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (manager.error != null)
            InfoBanner(text: manager.error!, icon: Icons.error_outline, color: GlyphColors.danger),
          if (!manager.isLoaded && manager.isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (presets.isEmpty)
            const EmptyNote(
              icon: Icons.bookmarks_outlined,
              text: 'No presets yet. Open an animation and tap "Save to matrix".',
            )
          else ...[
            const InfoBanner(
              icon: Icons.offline_bolt_outlined,
              text: 'Presets live on the matrix and play without your phone.',
            ),
            for (final p in presets)
              Tile(
                highlight: store.presetId == p.id && store.isOn == true,
                leading: PresetThumb(manager: manager, preset: p),
                title: p.name,
                subtitle:
                    '#${p.id} · ${manager.describe(p)}'
                    '${manager.schedule?.bootPreset == p.id ? ' · plays at power-on' : ''}',
                onTap: () => guarded(context, () => onApply(p.id)),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => switch (v) {
                    'rename' => _rename(context, p),
                    'delete' => _delete(context, p),
                    _ => null,
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WledPreset p) async {
    final name = await promptText(context, title: 'Rename preset', initial: p.name);
    if (name == null || name.isEmpty || name == p.name || !context.mounted) return;
    await guarded(context, () => manager.rename(p.id, name), done: 'Renamed to "$name"');
  }

  Future<void> _delete(BuildContext context, WledPreset p) async {
    final gif = p.gifName;
    final sharedGif = gif != null && manager.presetsUsingFile(gif).any((x) => x.id != p.id);
    final gifSize = gif == null ? null : manager.files['/$gif'];
    final usedBy = [
      ...manager.playlistsUsing(p.id).map((x) => 'playlist "${x.name}"'),
      if (manager.timersUsing(p.id).isNotEmpty) 'a schedule',
      if (manager.schedule?.bootPreset == p.id) 'the boot preset',
    ];
    var withFile = gif != null && gifSize != null && !sharedGif;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Delete "${p.name}"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('It will be removed from the matrix.'),
              if (usedBy.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'It is used by ${usedBy.join(', ')}.',
                    style: const TextStyle(color: GlyphColors.warning),
                  ),
                ),
              if (gif != null && gifSize != null && !sharedGif)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: withFile,
                  onChanged: (v) => setState(() => withFile = v ?? false),
                  title: Text('Also delete $gif'),
                  subtitle: Text('Frees ${formatBytes(gifSize)}'),
                ),
              if (sharedGif)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$gif is kept: another preset uses it.',
                    style: const TextStyle(color: GlyphColors.textMuted, fontSize: 13),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: GlyphColors.danger),
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
      done: 'Deleted "${p.name}"',
    );
  }
}
