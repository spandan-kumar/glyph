import 'package:flutter/material.dart';

import '../../../app/devices.dart';
import '../../../ui/theme.dart';
import '../../../wled/presets.dart';
import '../device_manager.dart';
import 'common.dart';

/// Device-side playlists: presets WLED cycles through by itself.
class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({
    super.key,
    required this.manager,
    required this.store,
    required this.onApply,
  });

  final DeviceManager manager;
  final DeviceStore store;
  final Future<void> Function(int id) onApply;

  @override
  Widget build(BuildContext context) {
    final lists = manager.playlists;
    final canCreate = manager.playable.isNotEmpty;
    return RefreshIndicator(
      onRefresh: manager.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const InfoBanner(
            icon: Icons.queue_music_rounded,
            text: 'Playlists run on the matrix: it steps through presets on its own timer.',
          ),
          if (lists.isEmpty)
            EmptyNote(
              icon: Icons.playlist_add_rounded,
              text: canCreate
                  ? 'No playlists yet.'
                  : 'Save a few presets first, then combine them into a playlist.',
            ),
          for (final p in lists)
            Tile(
              highlight: store.playlistId == p.id && store.isOn == true,
              leading: PresetThumb(manager: manager, preset: p),
              title: p.name,
              subtitle: _summary(p.playlist!),
              onTap: () => guarded(context, () => onApply(p.id)),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'edit' => openPlaylistEditor(context, manager, existing: p),
                  'delete' => _delete(context, p),
                  _ => null,
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: canCreate ? () => openPlaylistEditor(context, manager) : null,
              icon: const Icon(Icons.add),
              label: const Text('New playlist'),
            ),
          ),
        ],
      ),
    );
  }

  String _summary(WledPlaylist pl) {
    final n = pl.entries.length;
    final len = pl.passDuration;
    final parts = [
      '$n preset${n == 1 ? '' : 's'}',
      if (len != null) formatTenths(len.inMilliseconds ~/ 100),
      pl.repeat == 0 ? 'loops' : '${pl.repeat}×',
      if (pl.shuffle) 'shuffled',
    ];
    return parts.join(' · ');
  }

  Future<void> _delete(BuildContext context, WledPreset p) async {
    final ok = await confirm(
      context,
      title: 'Delete "${p.name}"?',
      message: 'The presets in it stay on the matrix.',
    );
    if (!ok || !context.mounted) return;
    await guarded(context, () => manager.deletePreset(p.id), done: 'Deleted "${p.name}"');
  }
}

Future<void> openPlaylistEditor(
  BuildContext context,
  DeviceManager manager, {
  WledPreset? existing,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlaylistEditor(manager: manager, existing: existing),
    ),
  );
}

class PlaylistEditor extends StatefulWidget {
  const PlaylistEditor({super.key, required this.manager, this.existing});

  final DeviceManager manager;
  final WledPreset? existing;

  @override
  State<PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<PlaylistEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late WledPlaylist _pl = widget.existing?.playlist ?? const WledPlaylist(entries: []);
  // Stable keys for reordering, parallel to _pl.entries.
  late List<int> _keys = List.generate(_pl.entries.length, (i) => i);
  int _nextKey = 1000;
  bool _saving = false;

  DeviceManager get m => widget.manager;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setEntries(List<PlaylistEntry> e, List<int> keys) => setState(() {
    _pl = _pl.copyWith(entries: e);
    _keys = keys;
  });

  Future<void> _add() async {
    final id = await _pickPreset(context, title: 'Add preset');
    if (id == null) return;
    final last = _pl.entries.isEmpty ? null : _pl.entries.last;
    _setEntries(
      [
        ..._pl.entries,
        PlaylistEntry(
          presetId: id,
          durationDs: last?.durationDs ?? 300,
          transitionDs: last?.transitionDs ?? 7,
        ),
      ],
      [..._keys, _nextKey++],
    );
  }

  Future<int?> _pickPreset(BuildContext context, {required String title}) {
    final choices = [
      for (final p in m.playable)
        if (p.id != widget.existing?.id) p,
    ];
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final p in choices)
              Tile(
                leading: PresetThumb(manager: m, preset: p, size: 36),
                title: p.name,
                subtitle: m.describe(p),
                onTap: () => Navigator.pop(ctx, p.id),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_pl.entries.isEmpty) return;
    setState(() => _saving = true);
    final ok = await guarded(context, () async {
      await m.savePlaylist(id: widget.existing?.id, name: _name.text, playlist: _pl);
    }, done: 'Playlist saved and playing');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _pl.entries;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New playlist' : 'Edit playlist'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: entries.isEmpty || _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        buildDefaultDragHandles: false,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              maxLength: 32,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Evening mix'),
            ),
            _options(),
            SectionLabel(
              'Presets (${entries.length})',
              trailing: TextButton.icon(
                onPressed: entries.length >= WledPlaylist.maxEntries ? null : _add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ),
            if (entries.isEmpty)
              const EmptyNote(icon: Icons.playlist_add, text: 'Add presets to play in order.'),
          ],
        ),
        itemCount: entries.length,
        onReorderItem: (from, to) {
          final e = [...entries], k = [..._keys];
          e.insert(to, e.removeAt(from));
          k.insert(to, k.removeAt(from));
          _setEntries(e, k);
        },
        itemBuilder: (context, i) => _EntryRow(
          key: ValueKey(_keys[i]),
          index: i,
          manager: m,
          entry: entries[i],
          onChanged: (e) => _setEntries([...entries]..[i] = e, _keys),
          onRemove: () => _setEntries([...entries]..removeAt(i), [..._keys]..removeAt(i)),
        ),
      ),
    );
  }

  Widget _options() {
    final endLabel = switch (_pl.endPreset) {
      0 => 'Stay on last preset',
      WledPlaylist.restorePrevious => 'Go back to what was playing',
      final id => m.presetName(id),
    };
    return Material(
      color: GlyphColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: Text('Repeat')),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Forever')),
                    ButtonSegment(value: false, label: Text('Times')),
                  ],
                  selected: {_pl.repeat == 0},
                  onSelectionChanged: (s) =>
                      setState(() => _pl = _pl.copyWith(repeat: s.first ? 0 : 1)),
                ),
              ],
            ),
            if (_pl.repeat > 0)
              Row(
                children: [
                  const Expanded(child: Text('Play through')),
                  IconButton(
                    onPressed: _pl.repeat > 1
                        ? () => setState(() => _pl = _pl.copyWith(repeat: _pl.repeat - 1))
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('${_pl.repeat}×'),
                  IconButton(
                    onPressed: _pl.repeat < 99
                        ? () => setState(() => _pl = _pl.copyWith(repeat: _pl.repeat + 1))
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Shuffle'),
              subtitle: const Text('Reshuffles after each pass'),
              value: _pl.shuffle,
              onChanged: (v) => setState(() => _pl = _pl.copyWith(shuffle: v)),
            ),
            if (_pl.repeat > 0)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('When it ends'),
                subtitle: Text(endLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickEnd,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickEnd() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
        children: [
          ListTile(title: const Text('Stay on last preset'), onTap: () => Navigator.pop(ctx, 0)),
          ListTile(
            title: const Text('Go back to what was playing'),
            onTap: () => Navigator.pop(ctx, WledPlaylist.restorePrevious),
          ),
          ListTile(
            title: const Text('Play a preset…'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(ctx, -1),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final id = choice == -1 ? await _pickPreset(context, title: 'Then play') : choice;
    if (id != null) setState(() => _pl = _pl.copyWith(endPreset: id));
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.index,
    required this.manager,
    required this.entry,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final DeviceManager manager;
  final PlaylistEntry entry;
  final ValueChanged<PlaylistEntry> onChanged;
  final VoidCallback onRemove;

  static const _durations = [50, 100, 150, 300, 600, 1200, 3000, 6000, 18000, 36000, 0];
  static const _transitions = [0, 3, 7, 10, 20, 50];

  @override
  Widget build(BuildContext context) {
    final p = manager.preset(entry.presetId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: GlyphColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_indicator, color: GlyphColors.textMuted),
                ),
              ),
              if (p != null) PresetThumb(manager: manager, preset: p, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p?.name ?? 'Missing preset ${entry.presetId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p == null ? GlyphColors.danger : null),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        _ChipMenu(
                          icon: Icons.timer_outlined,
                          label: formatTenths(entry.durationDs),
                          values: _withCurrent(_durations, entry.durationDs),
                          format: formatTenths,
                          onSelected: (v) => onChanged(entry.copyWith(durationDs: v)),
                        ),
                        _ChipMenu(
                          icon: Icons.blur_on,
                          label: _tr(entry.transitionDs),
                          values: _withCurrent(_transitions, entry.transitionDs),
                          format: _tr,
                          onSelected: (v) => onChanged(entry.copyWith(transitionDs: v)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(onPressed: onRemove, icon: const Icon(Icons.close, size: 20)),
            ],
          ),
        ),
      ),
    );
  }

  static String _tr(int ds) =>
      ds == 0 ? 'cut' : '${(ds / 10).toStringAsFixed(ds % 10 == 0 ? 0 : 1)} s fade';

  static List<int> _withCurrent(List<int> base, int v) => base.contains(v)
      ? base
      : ([...base, v]..sort(
          (a, b) => a == 0
              ? 1
              : b == 0
              ? -1
              : a - b,
        ));
}

class _ChipMenu extends StatelessWidget {
  const _ChipMenu({
    required this.icon,
    required this.label,
    required this.values,
    required this.format,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final List<int> values;
  final String Function(int) format;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    onSelected: onSelected,
    itemBuilder: (_) => [for (final v in values) PopupMenuItem(value: v, child: Text(format(v)))],
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: GlyphColors.accent),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 12, color: GlyphColors.accent)),
        ],
      ),
    ),
  );
}
