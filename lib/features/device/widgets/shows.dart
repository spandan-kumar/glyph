import 'package:flutter/material.dart';

import '../../../app/devices.dart';
import '../../glance/glance_screen.dart';
import '../../../ui/scope.dart';
import '../../../ui/design/parts.dart';
import '../../../ui/design/toggle.dart';
import '../../../ui/design/tokens.dart';
import '../../../ui/design/type.dart';
import '../../../wled/presets.dart';
import '../device_manager.dart';
import 'common.dart';

/// Shows: saved items the device plays one after another, on its own.
class ShowsSection extends StatelessWidget {
  const ShowsSection({super.key, required this.manager, required this.store, required this.onPlay});

  final DeviceManager manager;
  final DeviceStore store;
  final Future<void> Function(int id) onPlay;

  @override
  Widget build(BuildContext context) {
    final shows = [for (final p in manager.playlists) if (!manager.isSystem(p)) p];
    final canCreate = keptItems(manager).isNotEmpty;
    final accent = accentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Runs on your device', style: LbType.small)),
        if (shows.isEmpty)
          EmptyNote(
            text: canCreate
                ? 'Line up a few saved animations and your device plays them one after another.'
                : 'Send a few animations to your device first, then line them up into a show.',
          ),
        for (final p in shows)
          Padding(
            key: ValueKey(p.id),
            padding: const EdgeInsets.only(bottom: 10),
            child: ShowCard(
              manager: manager,
              show: p,
              accent: accent,
              playing: store.playlistRunning && store.playlistId == p.id && store.isOn == true,
              onTap: () => guarded(context, () => onPlay(p.id)),
              onEdit: () => openShowEditor(context, manager, existing: p),
              onDelete: () => _delete(context, p),
            ),
          ),
        if (canCreate)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: OutlinedButton.icon(
              onPressed: () => openShowEditor(context, manager),
              icon: const Icon(Icons.add_sharp, size: 20),
              label: const Text('New show'),
            ),
          ),
        if (context.getInheritedWidgetOfExactType<AppScope>()?.glance != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlanceScreen())), icon: const Icon(Icons.smartphone_sharp), label: const Text('Phone Shows · needs your phone')),
        ],
      ],
    );
  }

  Future<void> _delete(BuildContext context, WledPreset p) async {
    final ok = await confirm(
      context,
      title: 'Delete “${p.name}”?',
      message: 'The animations in it stay on your device.',
    );
    if (!ok || !context.mounted) return;
    await guarded(context, () => manager.deletePreset(p.id), done: 'Deleted “${p.name}”');
  }
}

/// "3 animations · plays one after another · loops".
String showSummary(WledPlaylist pl) {
  final n = pl.entries.length;
  final len = pl.passDuration;
  return [
    '$n animation${n == 1 ? '' : 's'}',
    if (len != null && len > Duration.zero) formatTenths(len.inMilliseconds ~/ 100),
    pl.shuffle ? 'shuffled' : 'one after another',
    pl.repeat == 0 ? 'loops' : (pl.repeat == 1 ? 'once' : '${pl.repeat} times'),
  ].join(' · ');
}

class ShowCard extends StatelessWidget {
  const ShowCard({
    super.key,
    required this.manager,
    required this.show,
    this.playing = false,
    this.accent = Lb.phosphor,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final DeviceManager manager;
  final WledPreset show;
  final bool playing;
  final Color accent;
  final VoidCallback? onTap, onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final pl = show.playlist!;
    return LbPanel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (playing) ...[StatusDot(on: true, color: accent), const SizedBox(width: 8)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(show.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.heading),
                    const SizedBox(height: 2),
                    Text(showSummary(pl), maxLines: 2, overflow: TextOverflow.ellipsis, style: LbType.small),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Show options',
                shape: squareMenu,
                icon: const Icon(Icons.more_horiz_sharp, color: Lb.text2),
                onSelected: (v) => v == 'edit' ? onEdit?.call() : onDelete?.call(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: LayoutBuilder(
              builder: (context, c) {
                const size = 34.0, gap = 6.0;
                final fit = ((c.maxWidth + gap) / (size + gap)).floor();
                final entries = pl.entries;
                final shown = entries.length > fit ? fit - 1 : entries.length;
                return Row(
                  children: [
                    for (final (i, e) in entries.take(shown.clamp(0, entries.length)).indexed)
                      Padding(
                        key: ValueKey((i, e.presetId)),
                        padding: const EdgeInsets.only(right: gap),
                        child: SizedBox.square(
                          dimension: size,
                          child: _MiniTile(manager: manager, id: e.presetId),
                        ),
                      ),
                    if (entries.length > shown)
                      SizedBox.square(
                        dimension: size,
                        child: Center(child: Text('+${entries.length - shown}', style: LbType.label)),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  const _MiniTile({required this.manager, required this.id});

  final DeviceManager manager;
  final int id;

  @override
  Widget build(BuildContext context) {
    final p = manager.preset(id);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF050403),
        borderRadius: BorderRadius.circular(Lb.rTile),
        border: Border.all(color: Lb.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Lb.rTile),
        child: p == null ? const DotGlyph(color: Lb.text3, dim: true) : PresetThumb(manager: manager, preset: p),
      ),
    );
  }
}

Future<void> openShowEditor(BuildContext context, DeviceManager manager, {WledPreset? existing}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ShowEditor(manager: manager, existing: existing)),
    );

/// Picks saved items for a show and how long each one plays.
class ShowEditor extends StatefulWidget {
  const ShowEditor({super.key, required this.manager, this.existing});

  final DeviceManager manager;
  final WledPreset? existing;

  @override
  State<ShowEditor> createState() => _ShowEditorState();
}

class _ShowEditorState extends State<ShowEditor> {
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
    final id = await _pick(context, title: 'Add to the show');
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

  Future<int?> _pick(BuildContext context, {required String title}) {
    final choices = keptItems(m);
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 24),
          children: [
            SheetTitle(title),
            Wrap(
              spacing: 10,
              runSpacing: 14,
              children: [
                for (final p in choices)
                  SizedBox(
                    key: ValueKey(p.id),
                    width: 96,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, p.id),
                      child: Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: LedBezel(child: PresetThumb(manager: m, preset: p)),
                          ),
                          const SizedBox(height: 4),
                          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.small),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_pl.entries.isEmpty) return;
    setState(() => _saving = true);
    final name = _name.text.trim().isEmpty ? 'My show' : _name.text.trim();
    final ok = await guarded(context, () async {
      await m.savePlaylist(id: widget.existing?.id, name: name, playlist: _pl);
    }, done: 'Show saved — it\'s playing on your device');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _pl.entries;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New show' : 'Edit show'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: entries.isEmpty || _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 32),
        buildDefaultDragHandles: false,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              maxLength: 32,
              style: LbType.body,
              decoration: const InputDecoration(hintText: 'Name it, e.g. Evening mix'),
            ),
            Text('Your device plays these one after another, by itself.', style: LbType.small),
            const SizedBox(height: 16),
            _options(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: MonoLabel('In this show · ${entries.length}')),
                TextButton.icon(
                  onPressed: entries.length >= WledPlaylist.maxEntries ? null : _add,
                  icon: const Icon(Icons.add_sharp, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (entries.isEmpty) const EmptyNote(text: 'Add saved animations to play in order.'),
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
      0 => 'Stay on the last one',
      WledPlaylist.restorePrevious => 'Go back to what was playing',
      final id => keptName(m, id),
    };
    return RowGroup(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Expanded(child: Text('Repeat', style: LbType.bodyStrong)),
              SegmentedButton<bool>(
                style: squareSegments,
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('Forever')),
                  ButtonSegment(value: false, label: Text('Times')),
                ],
                selected: {_pl.repeat == 0},
                onSelectionChanged: (s) => setState(() => _pl = _pl.copyWith(repeat: s.first ? 0 : 1)),
              ),
            ],
          ),
        ),
        if (_pl.repeat > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(
              children: [
                Expanded(child: Text('Play it through', style: LbType.body)),
                IconButton(
                  tooltip: 'Fewer',
                  onPressed: _pl.repeat > 1
                      ? () => setState(() => _pl = _pl.copyWith(repeat: _pl.repeat - 1))
                      : null,
                  icon: const Icon(Icons.remove_sharp),
                ),
                Text('${_pl.repeat}×', style: LbType.bodyStrong),
                IconButton(
                  tooltip: 'More',
                  onPressed: _pl.repeat < 99
                      ? () => setState(() => _pl = _pl.copyWith(repeat: _pl.repeat + 1))
                      : null,
                  icon: const Icon(Icons.add_sharp),
                ),
              ],
            ),
          ),
        Row1(
          title: 'Shuffle',
          subtitle: 'A new order every time round',
          trailing: LbToggle(
            value: _pl.shuffle,
            onChanged: (v) => setState(() => _pl = _pl.copyWith(shuffle: v)),
          ),
        ),
        if (_pl.repeat > 0)
          Row1(
            title: 'When it ends',
            subtitle: endLabel,
            trailing: const Icon(Icons.chevron_right_sharp, color: Lb.text3),
            onTap: _pickEnd,
          ),
      ],
    );
  }

  Future<void> _pickEnd() async {
    final choice = await showActions(
      context,
      title: 'When it ends',
      actions: const [
        ActionItem('Stay on the last one', Icons.stop_sharp, '0'),
        ActionItem('Go back to what was playing', Icons.undo_sharp, 'back'),
        ActionItem('Play something else…', Icons.grid_view_sharp, 'pick'),
      ],
    );
    if (choice == null || !mounted) return;
    final id = switch (choice) {
      '0' => 0,
      'back' => WledPlaylist.restorePrevious,
      _ => await _pick(context, title: 'Then play'),
    };
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
      child: LbPanel(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_indicator_sharp, color: Lb.text3),
              ),
            ),
            SizedBox.square(
              dimension: 40,
              child: LedBezel(
                child: p == null
                    ? const DotGlyph(color: Lb.text3, dim: true)
                    : PresetThumb(manager: manager, preset: p),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p?.name ?? 'Removed from your device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbType.bodyStrong.copyWith(color: p == null ? Lb.danger : null),
                  ),
                  Wrap(
                    spacing: 10,
                    children: [
                      _ChipMenu(
                        icon: Icons.timer_sharp,
                        label: formatTenths(entry.durationDs),
                        values: _withCurrent(_durations, entry.durationDs),
                        format: formatTenths,
                        onSelected: (v) => onChanged(entry.copyWith(durationDs: v)),
                      ),
                      _ChipMenu(
                        icon: Icons.blur_on_sharp,
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
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.close_sharp, size: 20, color: Lb.text3),
            ),
          ],
        ),
      ),
    );
  }

  static String _tr(int ds) =>
      ds == 0 ? 'cut' : '${(ds / 10).toStringAsFixed(ds % 10 == 0 ? 0 : 1)} s fade';

  static List<int> _withCurrent(List<int> base, int v) => base.contains(v)
      ? base
      : ([...base, v]..sort((a, b) => a == 0 ? 1 : (b == 0 ? -1 : a - b)));
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
    shape: squareMenu,
    onSelected: onSelected,
    itemBuilder: (_) => [for (final v in values) PopupMenuItem(value: v, child: Text(format(v)))],
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Lb.text2),
          const SizedBox(width: 4),
          Text(label, style: LbType.mono),
        ],
      ),
    ),
  );
}
