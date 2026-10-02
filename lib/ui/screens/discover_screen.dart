import 'package:flutter/material.dart';

import '../../library/catalog.dart';
import '../actions.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/live_preview.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  String _query = '';
  String? _category;

  List<LibraryItem> _visible(Catalog c) {
    var items = _query.isEmpty ? c.items : c.search(_query);
    if (_category != null) {
      items = items.where((i) => i.category == _category).toList();
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final catalog = scope.catalog;
    final items = _visible(catalog);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: GlyphColors.brandGradient.createShader,
                    child: const Text('Glyph',
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5)),
                  ),
                  const Spacer(),
                  const _ConnectionPill(),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search ${catalog.items.length} animations',
                  prefixIcon: const Icon(Icons.search, color: GlyphColors.textMuted),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _chip('All', _category == null, () => setState(() => _category = null)),
                  for (final c in catalog.categories)
                    _chip(c, _category == c, () => setState(() => _category = c)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: items.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(
                          child: Text('No animations match',
                              style: TextStyle(color: GlyphColors.textMuted))),
                    ),
                  )
                : SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _AnimationCard(item: items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onTap(),
        ),
      );
}

class _AnimationCard extends StatelessWidget {
  const _AnimationCard({required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final playback = AppScope.of(context).playback;
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final playing = playback.item?.id == item.id;
        return GestureDetector(
          onTap: () => GlyphActions.play(context, item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: GlyphColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: playing ? GlyphColors.primary : GlyphColors.outline,
                width: playing ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The preview takes whatever height the text leaves, so the
                // card never overflows at any text scale or grid width.
                Expanded(child: Center(child: LivePreview(item: item))),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                  child: Text(item.category,
                      style: const TextStyle(
                          fontSize: 12, color: GlyphColors.textMuted)),
                ),
              ],
            ),
          ),
        );
      },
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
