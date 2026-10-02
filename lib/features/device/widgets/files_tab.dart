import 'package:flutter/material.dart';

import '../../../app/devices.dart';
import '../../../ui/theme.dart';
import '../device_manager.dart';
import 'common.dart';

/// Files WLED needs to work; never offered for deletion.
const protectedFiles = {
  '/cfg.json',
  '/bkp.cfg.json',
  '/presets.json',
  '/wsec.json',
  '/version-info.json',
  '/ledmap.json',
};

bool isProtectedFile(String path) {
  final p = path.toLowerCase();
  return protectedFiles.contains(p) ||
      RegExp(r'^/ledmap\d*\.json$').hasMatch(p) ||
      RegExp(r'^/palette\d+\.json$').hasMatch(p);
}

/// Storage on the matrix: GIFs (with what uses them) and other files.
class FilesTab extends StatelessWidget {
  const FilesTab({super.key, required this.manager, required this.store});

  final DeviceManager manager;
  final DeviceStore store;

  @override
  Widget build(BuildContext context) {
    final info = store.info;
    final entries = manager.files.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final gifs = [
      for (final e in entries)
        if (e.key.toLowerCase().endsWith('.gif')) e,
    ];
    final others = [
      for (final e in entries)
        if (!e.key.toLowerCase().endsWith('.gif')) e,
    ];
    final used = info?.fsUsedKb, total = info?.fsTotalKb;
    final unusedBytes = gifs
        .where((e) => manager.presetsUsingFile(e.key).isEmpty)
        .fold<int>(0, (s, e) => s + e.value);

    return RefreshIndicator(
      onRefresh: () async {
        await store.refresh();
        await manager.load();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (used != null && total != null && total > 0)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: GlyphColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sd_storage_outlined, size: 18, color: GlyphColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(child: Text('$used of $total KB used')),
                      Text(
                        '${total - used} KB free',
                        style: const TextStyle(color: GlyphColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (used / total).clamp(0.0, 1.0),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    color: used / total > 0.85 ? GlyphColors.warning : GlyphColors.primary,
                  ),
                  if (unusedBytes > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${formatBytes(unusedBytes)} in GIFs no preset uses',
                        style: const TextStyle(fontSize: 12, color: GlyphColors.textMuted),
                      ),
                    ),
                ],
              ),
            ),
          SectionLabel('GIFs (${gifs.length})'),
          if (gifs.isEmpty)
            const EmptyNote(icon: Icons.gif_box_outlined, text: 'No GIFs on this matrix.'),
          for (final e in gifs) _fileTile(context, e.key, e.value, gif: true),
          if (others.isNotEmpty) ...[
            const SectionLabel('Other files'),
            for (final e in others) _fileTile(context, e.key, e.value),
          ],
        ],
      ),
    );
  }

  Widget _fileTile(BuildContext context, String path, int size, {bool gif = false}) {
    final users = manager.presetsUsingFile(path);
    final locked = isProtectedFile(path);
    final usage = gif
        ? users.isEmpty
              ? 'Unused'
              : 'Used by ${users.map((p) => p.name).join(', ')}'
        : locked
        ? 'Needed by WLED'
        : null;
    return Tile(
      leading: gif
          ? GifThumb(manager: manager, name: path, size: 40)
          : Icon(
              locked ? Icons.lock_outline : Icons.insert_drive_file_outlined,
              color: GlyphColors.textMuted,
            ),
      title: path.substring(1),
      subtitle: [formatBytes(size), ?usage].join(' · '),
      trailing: locked
          ? null
          : IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, path, size, users.map((p) => p.name).toList()),
            ),
    );
  }

  Future<void> _delete(BuildContext context, String path, int size, List<String> users) async {
    final name = path.substring(1);
    final ok = await confirm(
      context,
      title: 'Delete $name?',
      message: users.isEmpty
          ? 'Frees ${formatBytes(size)} on the matrix.'
          : 'Used by ${users.join(', ')}. Those presets will show nothing until you save the '
                'GIF again.',
    );
    if (!ok || !context.mounted) return;
    await guarded(context, () => manager.deleteFile(path), done: 'Deleted $name');
  }
}
