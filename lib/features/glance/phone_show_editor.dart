import 'package:flutter/material.dart';

import '../../engine/registry.dart';
import '../../ui/design/parts.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/studio_kit.dart';
import 'glance_model.dart';
import 'glance_session.dart';
import 'glance_store.dart';

class PhoneShowEditor extends StatefulWidget {
  const PhoneShowEditor({super.key, required this.session, this.show});
  final GlanceSession session;
  final PhoneShow? show;
  @override
  State<PhoneShowEditor> createState() => _PhoneShowEditorState();
}

class _PhoneShowEditorState extends State<PhoneShowEditor> {
  late final _title = TextEditingController(
    text: widget.show?.title ?? 'My Show',
  );
  late final _entries = [...?widget.show?.entries];
  late final _id = widget.show?.id ?? GlanceStore.newId();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final entry = await Navigator.of(context).push<PhoneShowEntry>(
      MaterialPageRoute(builder: (_) => _ChooseEntry(session: widget.session)),
    );
    if (entry != null && mounted) setState(() => _entries.add(entry));
  }

  void _move(int from, int to) => setState(() {
    final e = _entries.removeAt(from);
    _entries.insert(to, e);
  });
  Future<void> _save() async {
    final show = PhoneShow(
      id: _id,
      title: _title.text.trim(),
      entries: _entries,
    );
    if (!show.valid) {
      setState(
        () => _error = 'Give your Show a title and add at least one item.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.store.saveShow(show);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn\'t save this Show. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => StudioScaffold(
    title: 'Phone Show',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 32),
      children: [
        Text('Needs your phone', style: LbType.heading),
        const SizedBox(height: 6),
        Text(
          'Cards, library looks and your creations, in order. Loops while Glyph stays connected. Device-saved looks are managed in Device → Shows.',
          style: LbType.body,
        ),
        const SizedBox(height: 18),
        StudioGroup(
          label: 'Show',
          child: TextField(
            controller: _title,
            maxLength: 64,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
        ),
        const MonoLabel('Order & duration'),
        const SizedBox(height: 10),
        for (final (i, e) in _entries.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: LbPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${i + 1}. ${widget.session.entryTitle(e)}',
                    style: LbType.bodyStrong,
                  ),
                  Text(
                    '${switch (e.kind) {
                      ShowEntryKind.card => 'Card',
                      ShowEntryKind.library => 'Library',
                      ShowEntryKind.creation => 'Made by you',
                    }} · ${e.seconds} seconds',
                    style: LbType.small,
                  ),
                  Row(
                    children: [
                      PopupMenuButton<int>(
                        tooltip: 'Duration',
                        shape: studioMenuShape,
                        onSelected: (v) =>
                            setState(() => _entries[i] = e.withSeconds(v)),
                        itemBuilder: (_) => [
                          for (final n in ({
                            3,
                            5,
                            10,
                            15,
                            30,
                            60,
                            120,
                            e.seconds,
                          }.toList()..sort()))
                            PopupMenuItem(value: n, child: Text('$n seconds')),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Duration', style: LbType.mono),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down_sharp, size: 16),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        style: studioIconStyle,
                        tooltip: 'Move up',
                        onPressed: i == 0 ? null : () => _move(i, i - 1),
                        icon: const Icon(Icons.arrow_upward_sharp, size: 18),
                      ),
                      IconButton(
                        style: studioIconStyle,
                        tooltip: 'Move down',
                        onPressed: i == _entries.length - 1
                            ? null
                            : () => _move(i, i + 1),
                        icon: const Icon(Icons.arrow_downward_sharp, size: 18),
                      ),
                      IconButton(
                        style: studioIconStyle,
                        tooltip: 'Remove item',
                        onPressed: () => setState(() => _entries.removeAt(i)),
                        icon: const Icon(Icons.close_sharp, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _entries.length < 24 ? _add : null,
          icon: const Icon(Icons.add_sharp),
          label: Text(_entries.length < 24 ? 'Add item' : '24 items maximum'),
        ),
        const SizedBox(height: 12),
        Text(
          'Missing items and weather older than two hours are skipped. If every item is unavailable, the display shows -- and checks again every three seconds. Notification alerts pause the Show, then it resumes where it left off.',
          style: LbType.small,
        ),
        const SizedBox(height: 18),
        if (_error != null)
          Text(_error!, style: LbType.small.copyWith(color: Lb.danger)),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save Show'),
        ),
        const SizedBox(height: 8),
        Text(
          'Changes take effect next time you start the Show from Glance.',
          style: LbType.small,
        ),
      ],
    ),
  );
}

class _ChooseEntry extends StatefulWidget {
  const _ChooseEntry({required this.session});
  final GlanceSession session;
  @override
  State<_ChooseEntry> createState() => _ChooseEntryState();
}

class _ChooseEntryState extends State<_ChooseEntry> {
  String _query = '';
  ShowEntryKind _kind = ShowEntryKind.card;
  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final entries = switch (_kind) {
      ShowEntryKind.card => [for (final c in s.store.cards) (c.title, c.id)],
      ShowEntryKind.creation => [
        for (final c in s.creations.items) (c.title, c.id),
      ],
      ShowEntryKind.library => [
        for (final c in s.catalog.search(_query))
          if (findGenerator(c.generatorId) case final g? when !g.liveOnly)
            (c.title, c.id),
      ],
    };
    final matches = entries
        .where((e) => e.$1.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return StudioScaffold(
      title: 'Add to Show',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Lb.gutter),
            child: Column(
              children: [
                SegmentedButton<ShowEntryKind>(
                  style: studioSegmentStyle,
                  segments: const [
                    ButtonSegment(
                      value: ShowEntryKind.card,
                      label: Text('Cards'),
                    ),
                    ButtonSegment(
                      value: ShowEntryKind.library,
                      label: Text('Library'),
                    ),
                    ButtonSegment(
                      value: ShowEntryKind.creation,
                      label: Text('Made by you'),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (v) => setState(() => _kind = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(labelText: 'Search'),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Lb.gutter),
              children: [
                if (matches.isEmpty)
                  Text('No items here yet.', style: LbType.small),
                for (final e in matches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LbPanel(
                      onTap: () =>
                          Navigator.pop(context, PhoneShowEntry(_kind, e.$2)),
                      child: Text(e.$1, style: LbType.body),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
