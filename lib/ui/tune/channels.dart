import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../app/creations.dart';
import '../../app/playback.dart';
import '../../engine/clip.dart';
import '../../library/bundled_catalog.dart';
import '../../library/catalog.dart';
import '../actions.dart';
import 'seasons.dart';

/// Something you can tune to: a catalog look or one of your own creations.
sealed class TuneEntry {
  const TuneEntry();

  /// Stable identity, used for "which tile is lit" and caption keys.
  String get key;
  String get title;

  /// Tiny mono caption under a tile.
  String get kind;

  bool isPlaying(PlaybackController playback);
  Future<void> play(BuildContext context);

  @override
  bool operator ==(Object other) => other is TuneEntry && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

final class ItemEntry extends TuneEntry {
  const ItemEntry(this.item);

  final LibraryItem item;

  @override
  String get key => 'i:${item.id}';
  @override
  String get title => item.title;
  @override
  String get kind => item.category;

  @override
  bool isPlaying(PlaybackController playback) => playback.item?.id == item.id;

  @override
  Future<void> play(BuildContext context) => GlyphActions.play(context, item);
}

final class CreationEntry extends TuneEntry {
  CreationEntry(this.creation);

  final Creation creation;

  /// One generator per entry so previews keep their state across rebuilds.
  late final ClipGenerator generator = ClipGenerator(creation.clip, title: creation.title);

  @override
  String get key => 'c:${creation.id}';
  @override
  String get title => creation.title;
  @override
  String get kind => switch (creation.kind) {
        'drawing' => 'Drawing',
        'import' => 'GIF',
        'text' => 'Words',
        _ => 'Made by you',
      };

  @override
  bool isPlaying(PlaybackController playback) {
    final g = playback.generator;
    return playback.item == null && g is ClipGenerator && identical(g.clip, creation.clip);
  }

  @override
  Future<void> play(BuildContext context) => GlyphActions.playClip(context, creation.clip, creation.title);
}

/// An ordered run of looks. The rail shows [items]; "See all" shows [all].
/// Swiping on the Stage walks [items] of the channel you last tuned from.
class Channel {
  Channel({required this.id, required this.name, required this.items, List<TuneEntry>? all, this.note})
      : all = all ?? items;

  final String id;
  final String name;

  /// Short mono line under the rail header ("Spooky season · evening").
  final String? note;
  final List<TuneEntry> items;
  final List<TuneEntry> all;

  bool get isEmpty => items.isEmpty;

  /// The same channel, surfing through everything instead of the rail picks.
  Channel expanded() =>
      identical(all, items) ? this : Channel(id: '$id/all', name: name, items: all, all: all, note: note);

  /// Custom runs retain their order; retired library IDs cannot be tuned
  /// through a registry fallback after a catalog rollback.
  Channel withCatalog(Catalog catalog) {
    List<TuneEntry> refresh(List<TuneEntry> entries) => [
      for (final entry in entries)
        if (entry is ItemEntry) ...[
          if (catalog.byId(entry.item.id) case final item?) ItemEntry(item),
        ] else entry,
    ];
    return Channel(id: id, name: name, note: note, items: refresh(items), all: refresh(all));
  }

  int indexOfPlaying(PlaybackController p) => items.indexWhere((e) => e.isPlaying(p));
}

/// Mood words offered as search suggestions.
const moods = ['cozy', 'spooky', 'space', 'party', 'calm', 'retro', 'love', 'nature'];

/// Categories folded into "Famous Classics".
const classicCategories = {'Classic Cartoons', 'Storybook', 'Monsters & Legends', 'Masterpieces'};

/// Categories that already have their own named rail.
const _railCategories = {...classicCategories, 'Chill', 'Party', 'Space'};

/// A part of the day, with tags that suit it.
class Daypart {
  const Daypart(this.title, this.tags);

  final String title;
  final List<String> tags;
}

Daypart daypartFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 11) return const Daypart('Morning', ['morning', 'sunrise', 'sun', 'sky', 'happy', 'spring']);
  if (h >= 11 && h < 17) return const Daypart('Afternoon', ['summer', 'colourful', 'bounce', 'happy', 'neon']);
  if (h >= 17 && h < 22) return const Daypart('Evening', ['cozy', 'warm', 'ambient', 'calm', 'flame', 'glow']);
  return const Daypart('Late night', ['night', 'sleep', 'stars', 'moon', 'aurora', 'calm']);
}

/// One look per animation so a rail isn't five colours of one thing.
List<LibraryItem> varied(Iterable<LibraryItem> src, {int limit = 24, Set<String>? seen}) {
  final gens = seen ?? <String>{};
  final out = <LibraryItem>[];
  for (final i in src) {
    if (out.length >= limit) break;
    if (gens.add(i.generatorId)) out.add(i);
  }
  return out;
}

List<TuneEntry> _entries(Iterable<LibraryItem> items) => [for (final i in items) ItemEntry(i)];

/// "Right now": the season's picks interleaved with picks for the time of
/// day, topped up from the featured shelf so it's never thin.
Channel rightNow(Catalog c, DateTime now) {
  final season = seasonFor(now);
  final part = daypartFor(now);
  final gens = <String>{};
  final seasonal = varied(seasonalItems(c, season, limit: 40), limit: 12, seen: gens);
  final daily = varied(c.tagged(part.tags), limit: 12, seen: gens);
  final out = <LibraryItem>[];
  for (var k = 0; k < max(seasonal.length, daily.length); k++) {
    if (k < seasonal.length) out.add(seasonal[k]);
    if (k < daily.length) out.add(daily[k]);
  }
  if (out.length < 12) {
    out.addAll(varied([...c.featured, ...c.items], limit: 12 - out.length, seen: gens));
  }
  return Channel(
    id: 'now',
    name: 'Right now',
    note: '${season.title} · ${part.title}',
    items: _entries(out.take(20)),
  );
}

/// The catalog-only channels, in rail order. Personal rails (favourites,
/// creations) are slotted in by the screen.
class CatalogChannels {
  CatalogChannels(this.catalog, DateTime now) {
    final c = catalog;
    nowChannel = rightNow(c, now);

    Channel make(String id, String name, Iterable<LibraryItem> all, {int limit = 24, String? note}) {
      final list = all.toList();
      return Channel(id: id, name: name, note: note, items: _entries(varied(list, limit: limit)), all: _entries(list));
    }

    List<LibraryItem> union(Iterable<LibraryItem> a, Iterable<LibraryItem> b) => {...a, ...b}.toList();

    final sprites = c.items.where((i) => i.isPixelArt).toList();
    final cute = sprites.where((i) => i.tags.contains('cute'));
    // Animations newer than anything shipped in the app: downloaded from
    // the remote catalog since the last app update.
    final fresh = bundledRevision > 0 ? c.items.where((i) => i.added > bundledRevision).toList() : const <LibraryItem>[];
    lead = [
      if (fresh.isNotEmpty) make('new', 'Just added', fresh, limit: 30),
      make('classics', 'Famous Classics', c.items.where((i) => classicCategories.contains(i.category)), limit: 30),
      make('pals', 'Pixel Pals', union(cute, sprites), limit: 30),
      make('calm', 'Calm', union(c.inCategory('Chill'), c.tagged(['calm']))),
      make('party', 'Party', union(c.inCategory('Party'), c.tagged(['party']))),
      make('space', 'Space', union(c.inCategory('Space'), c.tagged(['space']))),
    ].where((ch) => !ch.isEmpty).toList();
    rest = [
      for (final cat in c.categories)
        if (!_railCategories.contains(cat)) make('cat:$cat', cat, c.inCategory(cat)),
    ].where((ch) => !ch.isEmpty).toList();
  }

  final Catalog catalog;
  late final Channel nowChannel;

  /// Just added (when there is something new), Famous Classics, Pixel Pals,
  /// Calm, Party, Space.
  late final List<Channel> lead;

  /// Every other catalog category.
  late final List<Channel> rest;
}

/// All rails in display order.
List<Channel> assembleChannels({
  required CatalogChannels base,
  required Iterable<String> favourites,
  required Iterable<String> recents,
  required List<Creation> creations,
}) {
  final c = base.catalog;
  final favs = [for (final id in favourites) ?c.byId(id)];
  final recent = [for (final id in recents) ?c.byId(id)];
  return [
    base.nowChannel,
    ...base.lead,
    if (favs.isNotEmpty) Channel(id: 'favs', name: 'Your favourites', items: _entries(favs.reversed)),
    if (recent.isNotEmpty) Channel(id: 'lately', name: 'Lately', items: _entries(recent)),
    if (creations.isNotEmpty)
      Channel(id: 'mine', name: 'Made by you', items: [for (final x in creations) CreationEntry(x)]),
    ...base.rest,
  ];
}

/// A shuffled run of varied looks for "Surprise me", avoiding [avoid].
List<LibraryItem> surprisePicks(Catalog c, Random rnd, {String? avoid, int count = 24}) {
  final pool = List.of(c.items)..shuffle(rnd);
  return varied(pool.where((i) => i.generatorId != avoid), limit: count);
}
