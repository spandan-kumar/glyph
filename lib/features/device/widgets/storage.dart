import 'package:flutter/material.dart';

import '../../../app/devices.dart';
import '../../../ui/design/parts.dart';
import '../../../ui/design/route.dart';
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
      return const EmptyNote(text: 'Your device doesn\'t say how much room it has.');
    }
    final f = used / total;
    final unused = _unusedGifBytes(manager);
    return LbPanel(
      onTap: () => Navigator.of(
        context,
      ).push(lbRoute<void>((_) => StoragePage(manager: manager, store: store))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('$used KB of $total KB used', style: LbType.bodyStrong)),
              const Icon(Icons.chevron_right_sharp, color: Lb.text3),
            ],
          ),
          const SizedBox(height: 12),
          DotBar(fraction: f, color: f > 0.85 ? Lb.phosphor : Lb.text),
          const SizedBox(height: 10),
          Text(
            f > 0.85
                ? 'Your device is full. Make room in Device → Storage.'
                : unused > 0
                ? '${formatBytes(unused)} is used by old files that nothing plays anymore. Tap to free it up.'
                : 'Room for ${total - used} KB more.',
            style: LbType.small,
          ),
        ],
      ),
    );
  }
}

/// Animation files that nothing saved on the device plays anymore.
List<MapEntry<String, int>> _unusedGifs(DeviceManager m) => [
  for (final e in m.files.entries)
    if (e.key.toLowerCase().endsWith('.gif') && m.presetsUsingFile(e.key).isEmpty && !m.isSystemFile(e.key)) e,
];

int _unusedGifBytes(DeviceManager m) => _unusedGifs(m).fold<int>(0, (s, e) => s + e.value);

/// What a file on the device is, in plain words.
String describeFile(String path) {
  final p = path.toLowerCase();
  final name = p.startsWith('/') ? p.substring(1) : p;
  if (name.endsWith('.gif')) return 'An animation';
  if (name == 'cfg.json') return 'Your device\'s settings';
  if (name == 'bkp.cfg.json') return 'A backup copy of its settings';
  if (name == 'presets.json') return 'The list of everything saved on it';
  if (name == 'wsec.json') return 'Its Wi-Fi password and security settings';
  if (name == 'version-info.json') return 'Which WLED version it runs';
  if (RegExp(r'^ledmap\d*\.json$').hasMatch(name)) return 'How its lights are wired';
  if (RegExp(r'^palette\d+\.json$').hasMatch(name)) return 'A custom colour palette';
  if (RegExp(r'\.html?(\.gz)?$').hasMatch(name)) return 'An extra tool for its web page';
  if (name.endsWith('.json')) return 'Settings for one of its extra tools';
  if (RegExp(r'\.(png|jpe?g|bmp)$').hasMatch(name)) return 'A picture';
  return 'A file stored on it';
}

/// What's taking space on the device: animation files (with what plays
/// them) and everything else, each explained in plain words.
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
        // The Glyph intro is part of the device's start-up: counted in the
        // bar, not listed (and never offered for deletion).
        final entries = [
          for (final e in manager.files.entries)
            if (!manager.isSystemFile(e.key)) e,
        ]..sort((a, b) => b.value.compareTo(a.value));
        final gifs = [for (final e in entries) if (e.key.toLowerCase().endsWith('.gif')) e];
        final others = [for (final e in entries) if (!e.key.toLowerCase().endsWith('.gif')) e];
        final used = info?.fsUsedKb, total = info?.fsTotalKb;
        final unused = _unusedGifs(manager);
        final unusedBytes = unused.fold<int>(0, (s, e) => s + e.value);
        return LedRefresh(
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
                const SizedBox(height: 14),
              ],
              Text(
                'This is your device\'s own memory. Animations you send to it take up most of '
                'the room. Deleting one that nothing plays anymore makes space for new ones.',
                style: LbType.small,
              ),
              if (unused.isNotEmpty) ...[
                const SizedBox(height: 16),
                _FreeUp(bytes: unusedBytes, count: unused.length, onTap: () => _freeUp(context, unused)),
              ],
              const SizedBox(height: 24),
              MonoLabel('Animations · ${gifs.length}'),
              const SizedBox(height: 10),
              if (gifs.isEmpty)
                const EmptyNote(text: 'No animation files on your device.')
              else
                RowGroup(children: [for (final e in gifs) _row(context, e.key, e.value, gif: true)]),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 24),
                const MonoLabel('Other files'),
                const SizedBox(height: 6),
                Text(
                  'Files WLED uses to run. The ones with a lock can\'t be deleted.',
                  style: LbType.small,
                ),
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
    final title = _friendlyTitle(
      path,
      users.map((p) => p.name).toList(),
      gif: gif,
    );
    final what = gif
        ? users.isEmpty
              ? 'Nothing plays it anymore'
              : 'An animation'
        : null;
    return Row1(
      key: ValueKey(path),
      leading: gif
          ? SizedBox.square(
              dimension: 40,
              child: LedBezel(
                child: GifThumb(manager: manager, name: path),
              ),
            )
          : Icon(
              locked ? Icons.lock_outline_sharp : Icons.insert_drive_file_sharp,
              color: Lb.text3,
            ),
      title: title,
      subtitle: [
        ?what,
        if (locked) 'Your device needs this',
        formatBytes(size),
      ].join(' · '),
      detail: path.substring(1),
      trailing: locked
          ? null
          : IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_sharp, color: Lb.text2),
              onPressed: () => _delete(
                context,
                path,
                title,
                size,
                users.map((p) => p.name).toList(),
              ),
            ),
    );
  }

  /// What to call a file: the animation it belongs to, else what it is.
  static String _friendlyTitle(
    String path,
    List<String> users, {
    required bool gif,
  }) {
    if (!gif) return describeFile(path);
    return users.isEmpty ? 'Old animation' : users.join(', ');
  }

  Future<void> _delete(
    BuildContext context,
    String path,
    String name,
    int size,
    List<String> users,
  ) async {
    final ok = await confirm(
      context,
      title: 'Delete $name?',
      message: users.isEmpty
          ? 'Frees ${formatBytes(size)} on your device.'
          : users.length == 1
          ? '“${users.single}” uses this file — it will stop working.'
          : '${users.map((u) => '“$u”').join(', ')} use this file — they will stop working.',
    );
    if (!ok || !context.mounted) return;
    await guarded(context, () => manager.deleteFile(path), done: 'Deleted $name');
  }

  Future<void> _freeUp(BuildContext context, List<MapEntry<String, int>> files) async {
    final bytes = files.fold<int>(0, (s, e) => s + e.value);
    final ok = await confirm(
      context,
      title: 'Free up ${formatBytes(bytes)}?',
      message: 'Deletes ${files.length} old animation file${files.length == 1 ? '' : 's'} that nothing '
          'plays anymore. Everything you\'ve saved keeps playing.',
      action: 'Free up',
    );
    if (!ok || !context.mounted) return;
    await guarded(context, () async {
      for (final f in files) {
        await manager.deleteFile(f.key);
      }
    }, done: 'Freed up ${formatBytes(bytes)}');
  }
}

/// "31 KB of old animations nothing plays anymore" with a button to clear them.
class _FreeUp extends StatelessWidget {
  const _FreeUp({required this.bytes, required this.count, required this.onTap});

  final int bytes, count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LbPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${formatBytes(bytes)} is used by $count old file${count == 1 ? '' : 's'} that nothing plays anymore.',
          style: LbType.bodyStrong,
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onTap, child: Text('Free up ${formatBytes(bytes)}')),
      ],
    ),
  );
}
