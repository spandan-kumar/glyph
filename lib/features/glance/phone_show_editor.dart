import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/clip.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../../engine/registry.dart';
import '../../ui/design/parts.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/led_loop.dart';
import '../../ui/make/studio_kit.dart';
import 'glance_model.dart';
import 'glance_session.dart';
import 'glance_store.dart';

// Stored as a PhoneShow; people know it as a Rotation, which can't be
// confused with the Shows that play on the device itself.

/// Builds a Rotation: cards, library animations and creations that take
/// turns on the device, a few seconds each. Pops with the rotation's id.
class RotationEditor extends StatefulWidget {
  const RotationEditor({super.key, required this.session, this.show});
  final GlanceSession session;
  final PhoneShow? show;
  @override
  State<RotationEditor> createState() => _RotationEditorState();
}

class _RotationEditorState extends State<RotationEditor> {
  late final _title = TextEditingController(text: widget.show?.title ?? '');
  late final _entries = [...?widget.show?.entries];
  late final _id = widget.show?.id ?? GlanceStore.newId();
  bool _saving = false;
  String? _error;
  // Rebuilt when the entries change, so the stage restarts from the top.
  int _revision = 0;

  static const _durations = [5, 10, 15, 30, 60];

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  PhoneShow get _rotation => PhoneShow(
        id: _id,
        title: _title.text.trim().isEmpty ? 'My rotation' : _title.text.trim(),
        entries: _entries,
      );

  Future<void> _add() async {
    final entry = await showModalBottomSheet<PhoneShowEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChooseEntry(session: widget.session),
    );
    if (entry != null && mounted) {
      HapticFeedback.lightImpact();
      setState(() {
        _entries.add(entry);
        _revision++;
      });
    }
  }

  void _edit(void Function() change) => setState(() {
        HapticFeedback.selectionClick();
        change();
        _revision++;
      });

  int _nextDuration(int s) => _durations.firstWhere((d) => d > s, orElse: () => _durations.first);

  Future<void> _save() async {
    if (_entries.isEmpty) return setState(() => _error = 'Add at least one thing to rotate.');
    HapticFeedback.lightImpact();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.store.saveShow(_rotation);
      if (mounted) Navigator.pop(context, _id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn’t save. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final total = _entries.fold(0, (a, e) => a + e.seconds);
    return StudioScaffold(
      title: widget.show == null ? 'New rotation' : 'Edit rotation',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: _entries.isEmpty
                  ? AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Lb.ledOff,
                          borderRadius: BorderRadius.circular(Lb.rControl),
                          border: Border.all(color: Lb.line),
                        ),
                        alignment: Alignment.center,
                        child: Text('ADD SOMETHING\nTO ROTATE', textAlign: TextAlign.center, style: LbType.label),
                      ),
                    )
                  : LedLoop(
                      generator: s.showGenerator(_rotation),
                      resetKey: _revision,
                      width: s.playback.frame.width,
                      height: s.playback.frame.height,
                      glow: true,
                      bezel: true,
                      borderRadius: Lb.rControl,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _entries.isEmpty
                ? 'Each takes a turn on your device, then it starts over.'
                : '${_entries.length} ${_entries.length == 1 ? 'thing' : 'things'} · '
                    '${total >= 60 ? '${(total / 60).toStringAsFixed(total % 60 == 0 ? 0 : 1)} min' : '$total s'} per loop',
            textAlign: TextAlign.center,
            style: LbType.small.copyWith(color: Lb.text2),
          ),
          const SizedBox(height: 24),
          const MonoLabel('Name'),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            maxLength: 64,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Morning, Desk, Party…', counterText: ''),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(child: MonoLabel('In order')),
            if (_entries.isNotEmpty) const MonoLabel('Tap time to change'),
          ]),
          const SizedBox(height: 8),
          LbPanel(
            padding: EdgeInsets.zero,
            // So removing a row closes the gap instead of jumping.
            child: AnimatedSize(
              duration: Lb.fast,
              curve: Lb.ease,
              alignment: Alignment.topCenter,
              child: Column(children: [
              for (final (i, e) in _entries.indexed) ...[
                _EntryRow(
                  key: ValueKey('$i-${e.kind.name}-${e.id}'),
                  session: s,
                  entry: e,
                  first: i == 0,
                  last: i == _entries.length - 1,
                  onDuration: () => _edit(() => _entries[i] = e.withSeconds(_nextDuration(e.seconds))),
                  onUp: () => _edit(() => _entries.insert(i - 1, _entries.removeAt(i))),
                  onDown: () => _edit(() => _entries.insert(i + 1, _entries.removeAt(i))),
                  onRemove: () => _edit(() => _entries.removeAt(i)),
                ),
                const Divider(height: 1),
              ],
              InkWell(
                onTap: _entries.length < 24 ? _add : null,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const Icon(Icons.add_sharp, color: Lb.text2),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(_entries.length < 24 ? 'Add a card or animation' : '24 is the most',
                          style: LbType.body),
                    ),
                  ]),
                ),
              ),
            ]),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: LbType.small.copyWith(color: Lb.danger)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save rotation'),
          ),
          const SizedBox(height: 10),
          Text(
            'Anything that isn’t available — a deleted card, weather with no signal — is skipped. '
            'A notification alert pauses the rotation, then it carries on.',
            style: LbType.small.copyWith(color: Lb.text3),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.session,
    required this.entry,
    required this.first,
    required this.last,
    required this.onDuration,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });
  final GlanceSession session;
  final PhoneShowEntry entry;
  final bool first, last;
  final VoidCallback onDuration, onUp, onDown, onRemove;

  @override
  Widget build(BuildContext context) {
    final look = session.resolve(entry);
    final kind = switch (entry.kind) {
      ShowEntryKind.card => 'Card',
      ShowEntryKind.library => 'Animation',
      ShowEntryKind.creation => 'Made by you',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(children: [
        SizedBox.square(
          dimension: 40,
          child: look == null
              ? Container(
                  decoration: BoxDecoration(color: Lb.ledOff, borderRadius: BorderRadius.circular(Lb.rTile)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.block_sharp, size: 16, color: Lb.text3),
                )
              : LedLoop(generator: look.generator, palette: look.palette, borderRadius: Lb.rTile),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(session.entryTitle(entry), maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.body),
            Text(look == null ? '$kind · not available' : kind,
                style: LbType.small.copyWith(color: look == null ? Lb.danger : Lb.text2)),
          ]),
        ),
        Semantics(
          button: true,
          label: '${entry.seconds} seconds, tap to change',
          excludeSemantics: true,
          child: InkWell(
            onTap: onDuration,
            borderRadius: BorderRadius.circular(Lb.rControl),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Lb.rControl),
                border: Border.all(color: Lb.line),
              ),
              child: Text('${entry.seconds}s', style: LbType.mono.copyWith(color: Lb.text)),
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          shape: studioMenuShape,
          icon: const Icon(Icons.more_vert_sharp, color: Lb.text3),
          onSelected: (v) => switch (v) {
            'up' => onUp(),
            'down' => onDown(),
            _ => onRemove(),
          },
          itemBuilder: (_) => [
            if (!first) const PopupMenuItem(value: 'up', child: Text('Move up')),
            if (!last) const PopupMenuItem(value: 'down', child: Text('Move down')),
            const PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ]),
    );
  }
}

/// Pick something to add: your cards, things you made, or any animation.
class _ChooseEntry extends StatefulWidget {
  const _ChooseEntry({required this.session});
  final GlanceSession session;
  @override
  State<_ChooseEntry> createState() => _ChooseEntryState();
}

class _ChooseEntryState extends State<_ChooseEntry> {
  String _query = '';
  late ShowEntryKind _kind = widget.session.store.cards.isNotEmpty ? ShowEntryKind.card : ShowEntryKind.library;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final q = _query.toLowerCase();
    final entries = <(String, String, Generator, Palette?)>[
      if (_kind == ShowEntryKind.card)
        for (final c in s.store.cards) (c.title, c.id, s.cardGenerator(c), null),
      if (_kind == ShowEntryKind.creation)
        for (final c in s.creations.items) (c.title, c.id, ClipGenerator(c.clip, title: c.title), null),
      if (_kind == ShowEntryKind.library)
        for (final c in s.catalog.search(_query).take(60))
          if (findGenerator(c.generatorId) case final g? when !g.liveOnly) (c.title, c.id, g, paletteById(c.paletteId)),
    ].where((e) => _kind == ShowEntryKind.library || e.$1.toLowerCase().contains(q)).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 12),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Add to rotation', style: LbType.title),
                const SizedBox(height: 12),
                SegmentedButton<ShowEntryKind>(
                  style: studioSegmentStyle,
          showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ShowEntryKind.card, label: Text('Cards')),
                    ButtonSegment(value: ShowEntryKind.library, label: Text('Animations')),
                    ButtonSegment(value: ShowEntryKind.creation, label: Text('Yours')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (v) {
                    HapticFeedback.selectionClick();
                    setState(() => _kind = v.first);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    hintText: _kind == ShowEntryKind.library ? 'Search animations: cozy, space, fire…' : 'Search',
                    prefixIcon: const Icon(Icons.search_sharp),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ]),
            ),
          ),
          if (entries.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Lb.gutter),
                child: Text(
                  switch (_kind) {
                    ShowEntryKind.card => 'No cards yet — make one on the Glance screen.',
                    ShowEntryKind.creation => 'Nothing made yet — draw or write something in Make.',
                    ShowEntryKind.library => 'Nothing matches.',
                  },
                  style: LbType.small,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 24),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 110,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.8,
                ),
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final (title, id, g, pal) = entries[i];
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, PhoneShowEntry(_kind, id)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: LedLoop(generator: g, palette: pal, borderRadius: Lb.rTile),
                      ),
                      const SizedBox(height: 6),
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.small),
                    ]),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
