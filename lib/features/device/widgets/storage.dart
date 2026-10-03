import 'package:flutter/material.dart';

import '../../../app/devices.dart';
import '../../../ui/design/parts.dart';
import '../../../ui/design/tokens.dart';
import '../../../ui/design/type.dart';
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

/// "38 KB of 983 KB used" with an LED dot bar, and a way into the files.
class StorageSection extends StatelessWidget {
  const StorageSection({super.key, required this.manager, required this.store});

  final DeviceManager manager;
  final DeviceStore store;

  @override
  Widget build(BuildContext context) {
    final info = store.info;
    final used = info?.fsUsedKb, total = info?.fsTotalKb;
    if (used == null || total == null || total <= 0) {
      return const EmptyNote(text: 'Your matrix doesn\'t say how much room it has.');
    }
    final f = used / total;
    final unused = _unusedGifBytes(manager);
    return LbPanel(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => StoragePage(manager: manager, store: store)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('$used KB of $total KB used', style: LbType.bodyStrong)),
              const Icon(Icons.chevron_right_rounded, color: Lb.text3),
            ],
          ),
          const SizedBox(height: 12),
          DotBar(fraction: f, color: f > 0.85 ? Lb.phosphor : Lb.text),
          const SizedBox(height: 10),
          Text(
            f > 0.85
                ? 'Almost full — remove something to keep more.'
                : unused > 0
                ? '${formatBytes(unused)} is taken by animations nothing uses.'
                : 'Room for ${total - used} KB more.',
            style: LbType.small,
          ),
        ],
      ),
    );
  }
}

int _unusedGifBytes(DeviceManager m) => m.files.entries
    .where((e) => e.key.toLowerCase().endsWith('.gif') && m.presetsUsingFile(e.key).isEmpty)
    .fold<int>(0, (s, e) => s + e.value);

/// What's taking space on the matrix: animation files (with what uses them)
/// and everything else.
class StoragePage extends StatelessWidget {
  const StoragePage({super.key, required this.manager, required this.store});

  final DeviceManager manager;
  final DeviceStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Storage')),
    body: ListenableBuilder(
      listenable: Listenable.merge([manager, store]),
      builder: (context, _) {
        final info = store.info;
        final entries = manager.files.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final gifs = [for (final e in entries) if (e.key.toLowerCase().endsWith('.gif')) e];
        final others = [for (final e in entries) if (!e.key.toLowerCase().endsWith('.gif')) e];
        final used = info?.fsUsedKb, total = info?.fsTotalKb;
        return RefreshIndicator(
          onRefresh: () async {
            await store.refresh();
            await manager.load();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Lb.gutter, 8, Lb.gutter, 32),
            children: [
              if (used != null && total != null && total > 0) ...[
                Text('$used KB of $total KB used', style: LbType.title),
                const SizedBox(height: 12),
                DotBar(fraction: used / total, color: used / total > 0.85 ? Lb.phosphor : Lb.text),
                const SizedBox(height: 24),
              ],
              MonoLabel('Animations · ${gifs.length}'),
              const SizedBox(height: 10),
              if (gifs.isEmpty)
                const EmptyNote(text: 'No animation files on your matrix.')
              else
                RowGroup(children: [for (final e in gifs) _row(context, e.key, e.value, gif: true)]),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 24),
                const MonoLabel('Other files'),
                const SizedBox(height: 10),
                RowGroup(children: [for (final e in others) _row(context, e.key, e.value)]),
              ],
            ],
          ),
        );
      },
    ),
  );

  Widget _row(BuildContext context, String path, int size, {bool gif = false}) {
    final users = manager.presetsUsingFile(path);
    final locked = isProtectedFile(path);
    final usage = gif
        ? users.isEmpty
              ? 'Nothing uses it'
              : 'Used by ${users.map((p) => p.name).join(', ')}'
        : locked
        ? 'Your matrix needs this'
        : null;
    return Row1(
      leading: gif
          ? SizedBox.square(dimension: 40, child: LedBezel(child: GifThumb(manager: manager, name: path)))
          : Icon(locked ? Icons.lock_outline_rounded : Icons.insert_drive_file_outlined, color: Lb.text3),
      title: path.substring(1),
      subtitle: [formatBytes(size), ?usage].join(' · '),
      trailing: locked
          ? null
          : IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded, color: Lb.text2),
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
          ? 'Frees ${formatBytes(size)} on your matrix.'
          : 'Used by ${users.join(', ')}. They\'ll show nothing until you keep it again.',
    );
    if (!ok || !context.mounted) return;
    await guarded(context, () => manager.deleteFile(path), done: 'Deleted $name');
  }
}
