import 'package:flutter/material.dart';

import '../design/ambient.dart';
import '../design/led_text.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import 'channels.dart';
import 'mini_stage.dart';
import 'tiles.dart';
import 'tune_controller.dart';

Route<T> _route<T>(TuneController tune, Widget page) => PageRouteBuilder<T>(
      transitionDuration: Lb.medium,
      reverseTransitionDuration: Lb.fast,
      pageBuilder: (context, _, _) => TuneScope(
        controller: tune,
        child: Scaffold(backgroundColor: Colors.transparent, body: AmbientBackdrop(child: page)),
      ),
      transitionsBuilder: (context, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Lb.ease),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Lb.ease)),
          child: child,
        ),
      ),
    );

/// "See all": the whole channel as a grid, with the mini-stage pinned on
/// top so you can surf from here too.
Future<void> openChannelPage(BuildContext context, Channel channel) =>
    Navigator.of(context).push(_route(TuneScope.read(context), _ChannelPage(channel: channel.expanded())));

class _ChannelPage extends StatelessWidget {
  const _ChannelPage({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, Lb.gutter, 12),
            child: Row(children: [
              const BackButton(color: Lb.text),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    header: true,
                    label: channel.name,
                    child: LedText(channel.name.toUpperCase(), dot: 4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${channel.all.length}', style: LbType.label),
            ]),
          ),
          const MiniStage(),
          Expanded(
            child: CustomScrollView(
              slivers: [TileGrid(channel: channel, entries: channel.all)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Search: instant results as tiles, moods as square hairline tokens. Tuning in
/// closes the page and returns `true`.
Future<bool?> openSearch(BuildContext context, TuneController tune) =>
    Navigator.of(context).push<bool>(_route(tune, const _SearchPage()));

class _SearchPage extends StatefulWidget {
  const _SearchPage();

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _field = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _set(String q) {
    _field.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    setState(() => _query = q.trim());
  }

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.of(context).catalog;
    final results = _query.isEmpty ? const <TuneEntry>[] : [for (final i in catalog.search(_query)) ItemEntry(i)];
    final channel = Channel(id: 'search', name: 'Search · $_query', items: results);
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, Lb.gutter, 0),
              child: Row(children: [
                const BackButton(color: Lb.text),
                Expanded(
                  child: TextField(
                    controller: _field,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    style: LbType.body,
                    onChanged: (v) => setState(() => _query = v.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search ${catalog.items.length} looks',
                      prefixIcon: const Icon(Icons.search_sharp, color: Lb.text3, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close_sharp, size: 18, color: Lb.text3),
                              onPressed: () => _set(''),
                            ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(Lb.gutter, 12, Lb.gutter, 4),
                children: [
                  for (final m in moods)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _MoodChip(label: m, selected: _query.toLowerCase() == m, onTap: () => _set(m)),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Lb.gutter, 14, Lb.gutter, 4),
              child: Text(
                _query.isEmpty
                    ? 'TRY A MOOD, A COLOUR OR A THING'
                    : '${results.length} ${results.length == 1 ? 'LOOK' : 'LOOKS'}',
                style: LbType.label,
              ),
            ),
          ),
          if (_query.isNotEmpty && results.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Lb.gutter, 40, Lb.gutter, 0),
                child: Column(children: [
                  const LedText('?', dot: 6, color: Lb.text3),
                  const SizedBox(height: 14),
                  Text('Nothing called that yet.', style: LbType.body.copyWith(color: Lb.text2)),
                  const SizedBox(height: 4),
                  Text('Try a mood like “cozy” or “space”.', style: LbType.small),
                ]),
              ),
            )
          else
            TileGrid(
              channel: channel,
              entries: results,
              onTuned: () => Navigator.of(context).pop(true),
            ),
        ],
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Lb.raised : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Lb.rControl)),
        side: BorderSide(color: selected ? Lb.text2 : Lb.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label, style: LbType.small.copyWith(color: selected ? Lb.text : Lb.text2)),
        ),
      ),
    );
  }
}
