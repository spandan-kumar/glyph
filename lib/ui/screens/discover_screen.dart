import 'package:flutter/material.dart';

import '../../library/catalog.dart';
import '../../library/user_library.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/discover/animation_card.dart';
import '../widgets/discover/seasons.dart';
import '../widgets/discover/shelf.dart';

enum _Sort { featured, az, newest }

const _favouritesChip = 'Favourites';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.library, this.now});

  /// Defaults to [UserLibrary.shared].
  final UserLibrary? library;

  /// Overrides today's date for the seasonal shelf (tests, screenshots).
  final DateTime? now;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  String _query = '';
  String? _category; // null = All, or a category, or [_favouritesChip]
  _Sort _sort = _Sort.featured;
  final _scroll = ScrollController();

  late final UserLibrary _library = widget.library ?? UserLibrary.shared;
  AppScope? _scope;
  String? _lastPlayed;

  // Shelves depend only on the catalog, so they're built once per catalog.
  Catalog? _shelvesFor;
  late List<(String, IconData, List<LibraryItem>)> _shelves;

  @override
  void initState() {
    super.initState();
    _library.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    if (!identical(scope.playback, _scope?.playback)) {
      _scope?.playback.removeListener(_onPlayback);
      scope.playback.addListener(_onPlayback);
    }
    _scope = scope;
  }

  @override
  void dispose() {
    _scope?.playback.removeListener(_onPlayback);
    _scroll.dispose();
    super.dispose();
  }

  /// Anything played from anywhere in the app lands in "Recently played".
  void _onPlayback() {
    final id = _scope?.playback.item?.id;
    if (id == null || id == _lastPlayed) return;
    _lastPlayed = id;
    _library.markPlayed(id);
  }

  void _buildShelves(Catalog c) {
    if (identical(c, _shelvesFor)) return;
    _shelvesFor = c;
    List<LibraryItem> varied(Iterable<LibraryItem> src, [int limit = 20]) {
      // One look per animation so a shelf isn't five colours of one thing.
      final gens = <String>{};
      return src.where((i) => gens.add(i.generatorId)).take(limit).toList();
    }

    final featured = c.featured.isNotEmpty ? c.featured : c.items.take(12).toList();
    final season = seasonFor(widget.now ?? DateTime.now());
    final newest = c.items.fold(0, (m, i) => i.added > m ? i.added : m);
    const classics = {'Classic Cartoons', 'Storybook', 'Monsters & Legends', 'Masterpieces'};
    _shelves = [
      ('Featured', Icons.auto_awesome, featured),
      ('Famous Classics', Icons.theater_comedy_outlined,
          varied(c.items.where((i) => classics.contains(i.category)), 30)),
      (season.title, Icons.celebration_outlined, seasonalItems(c, season)),
      ('Chill Vibes', Icons.spa_outlined, varied(c.inCategory('Chill'))),
      ('Party Mode', Icons.nightlife, varied(c.inCategory('Party'))),
      ('Pixel Art', Icons.grid_on, varied(c.items.where((i) => i.isPixelArt), 24)),
      if (newest > 1) ('Just Added', Icons.fiber_new_outlined, varied(c.items.where((i) => i.added == newest).toList().reversed, 16)),
    ];
  }

  List<LibraryItem> _visible(Catalog c) {
    var items = _query.isEmpty ? c.items : c.search(_query);
    if (_category == _favouritesChip) {
      final favs = _library.favourites;
      items = items.where((i) => favs.contains(i.id)).toList();
    } else if (_category != null) {
      items = items.where((i) => i.category == _category).toList();
    }
    // A search keeps its relevance order; sorting applies to browsing.
    if (_query.isNotEmpty) return items;
    switch (_sort) {
      case _Sort.featured:
        final featured = items.where((i) => i.featured != null).toList()
          ..sort((a, b) => a.featured!.compareTo(b.featured!));
        return [...featured, ...items.where((i) => i.featured == null)];
      case _Sort.az:
        return List.of(items)..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _Sort.newest:
        final order = {for (var k = 0; k < items.length; k++) items[k].id: k};
        return List.of(items)
          ..sort((a, b) {
            final r = b.added.compareTo(a.added);
            return r != 0 ? r : order[b.id]!.compareTo(order[a.id]!);
          });
    }
  }

  void _select(String? category) {
    setState(() => _category = category);
    if (_scroll.hasClients && _scroll.offset > 200) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = AppScope.of(context).catalog;
    _buildShelves(catalog);
    final browsing = _query.isEmpty && _category == null;

    // Hidden tabs (IndexedStack) stop every preview ticker underneath.
    return TickerMode(
      enabled: Visibility.of(context),
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _library,
          builder: (context, _) {
            final items = _visible(catalog);
            final recents = [for (final id in _library.recents) ?catalog.byId(id)];
            return CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _searchField(catalog)),
                SliverToBoxAdapter(child: _chips(catalog)),
                if (browsing) ...[
                  if (recents.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Shelf(title: 'Recently played', icon: Icons.history, items: recents, library: _library),
                    ),
                  for (final (title, icon, shelfItems) in _shelves)
                    SliverToBoxAdapter(
                      child: Shelf(title: title, icon: icon, items: shelfItems, library: _library),
                    ),
                ],
                SliverToBoxAdapter(child: _gridHeader(items.length, browsing)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  sliver: items.isEmpty
                      ? SliverToBoxAdapter(child: _empty())
                      : SliverGrid.builder(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 200,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.82,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, i) => AnimationCard(item: items[i], library: _library),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Row(
          children: [
            ShaderMask(
              shaderCallback: GlyphColors.brandGradient.createShader,
              child: const Text('Glyph',
                  style: TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
            ),
            const Spacer(),
            const _ConnectionPill(),
          ],
        ),
      );

  Widget _searchField(Catalog catalog) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: TextField(
          onChanged: (v) => setState(() => _query = v.trim()),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search ${catalog.items.length} animations',
            prefixIcon: const Icon(Icons.search, color: GlyphColors.textMuted),
          ),
        ),
      );

  Widget _chips(Catalog catalog) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            _chip('All', _category == null, () => _select(null)),
            _chip(_favouritesChip, _category == _favouritesChip, () => _select(_favouritesChip),
                icon: Icons.favorite),
            for (final c in catalog.categories) _chip(c, _category == c, () => _select(c)),
          ],
        ),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          avatar: icon == null ? null : Icon(icon, size: 16, color: GlyphColors.danger),
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _gridHeader(int count, bool browsing) {
    final label = _query.isNotEmpty
        ? '$count result${count == 1 ? '' : 's'}'
        : browsing
            ? 'Everything · $count'
            : '${_category!} · $count';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          if (_query.isEmpty)
            PopupMenuButton<_Sort>(
              tooltip: 'Sort',
              initialValue: _sort,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => const [
                PopupMenuItem(value: _Sort.featured, child: Text('Featured first')),
                PopupMenuItem(value: _Sort.az, child: Text('A–Z')),
                PopupMenuItem(value: _Sort.newest, child: Text('Newest')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.sort, size: 18, color: GlyphColors.textMuted),
                  const SizedBox(width: 6),
                  Text(switch (_sort) { _Sort.featured => 'Featured', _Sort.az => 'A–Z', _Sort.newest => 'Newest' },
                      style: const TextStyle(color: GlyphColors.textMuted)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty() {
    final favs = _category == _favouritesChip && _query.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Center(
        child: Column(children: [
          Icon(favs ? Icons.favorite_border : Icons.search_off, color: GlyphColors.textMuted, size: 32),
          const SizedBox(height: 12),
          Text(favs ? 'No favourites yet' : 'No animations match',
              style: const TextStyle(color: GlyphColors.textMuted)),
          if (favs)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Tap the heart or long-press any animation',
                  style: TextStyle(color: GlyphColors.textMuted, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill();

  @override
  Widget build(BuildContext context) {
    final devices = AppScope.of(context).devices;
    return ListenableBuilder(
      listenable: devices,
      builder: (context, _) {
        final on = devices.isConnected;
        final label = on
            ? (devices.info!.name)
            : devices.selected == null
                ? 'No matrix'
                : 'Offline';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: GlyphColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: GlyphColors.outline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? GlyphColors.success : GlyphColors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13)),
          ]),
        );
      },
    );
  }
}
