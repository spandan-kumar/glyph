import 'catalog.dart';
import 'legacy_ids.dart';

class CatalogSearchResult {
  const CatalogSearchResult(
    this.items, {
    this.correctedQuery,
    this.suggestions = const [],
  });
  final List<LibraryItem> items;
  final String? correctedQuery;
  final List<String> suggestions;
}

final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _size = RegExp(r'\b(\d+)\s*[x×]\s*(\d+)\b');
final _number = RegExp(r'^\d+$');
final _collection = RegExp(r'\bcollection\s*:\s*(?:"([^"]+)"|([^\s]+))');
// Small, explicit spelling equivalents; subjects and franchise aliases belong
// in reviewed item metadata, not a query-specific exception list.
const _equivalents = {
  'grey': 'gray',
  'cosy': 'cozy',
  'colour': 'color',
  'colours': 'colors',
  'colourful': 'colorful',
};
const _descriptors = {
  'red',
  'green',
  'blue',
  'yellow',
  'purple',
  'cyan',
  'orange',
  'white',
  'black',
  'pink',
  'gray',
  'brown',
  'teal',
  'gold',
  'warm',
  'cold',
  'calm',
  'cozy',
  'spooky',
  'party',
  'bounce',
  'float',
  'sway',
  'pulse',
  'shake',
  'scroll',
  'still',
  'pixel',
  'art',
  'sprite',
  'neon',
  'colorful',
  'colourful',
};

String _normalize(String text) => text
    .toLowerCase()
    .replaceAllMapped(_size, (m) => '${m[1]}x${m[2]}')
    .split(_separators)
    .where((w) => w.isNotEmpty)
    .map((w) => _equivalents[w] ?? w)
    .join(' ');

class _Entry {
  _Entry(this.item, String Function(String) normalize)
    : title = normalize(item.title),
      aliases = item.aliases.map(normalize).toSet(),
      collection = normalize(item.collection ?? item.category),
      words = {} {
    void addWord(String word, int score) {
      if (word.isNotEmpty && score > (words[word] ?? 0)) words[word] = score;
    }

    void add(String text, int score) {
      for (final word in normalize(text).split(' ')) {
        addWord(word, score);
      }
    }

    add(item.title, 80);
    for (final alias in item.aliases) {
      add(alias, 70);
    }
    for (final subject in item.subjects) {
      add(subject, 60);
    }
    for (final tag in item.tags) {
      for (final word in normalize(tag).split(' ')) {
        addWord(
          word,
          _descriptors.contains(word) || _size.hasMatch(word) ? 25 : 45,
        );
      }
    }
    add(item.category, 20);
    if (item.collection != null) add(item.collection!, 20);
  }
  final LibraryItem item;
  final String title, collection;
  final Set<String> aliases;
  final Map<String, int> words;
}

class _Query {
  _Query(String raw) {
    var text = raw.toLowerCase();
    collections = [
      for (final m in _collection.allMatches(text)) _normalize(m[1] ?? m[2]!),
    ];
    text = text.replaceAll(_collection, ' ');
    sizes = [for (final m in _size.allMatches(text)) '${m[1]}x${m[2]}'];
    text = text.replaceAll(_size, ' ');
    phrase = _normalize(text);
    tokens = phrase.split(' ').where((t) => t.isNotEmpty).toSet().toList();
  }
  late final List<String> collections, sizes, tokens;
  late final String phrase;
  bool allows(_Entry e) =>
      collections.every((c) => c == e.collection) &&
      sizes.every((s) => e.words.containsKey(s));
  String replacePhrase(String phrase) => [
    for (final c in collections) 'collection:"$c"',
    ...sizes,
    phrase,
  ].join(' ');
}

/// Cached content-only word index. No network, generator/palette matches or
/// inferred subjects. A new Catalog (including a merge) builds a fresh index.
class CatalogSearch {
  CatalogSearch(List<LibraryItem> items) {
    // Colours, categories and shared tags repeat thousands of times. Normalize
    // each distinct string once while building, then discard this scratch map.
    final normalized = <String, String>{};
    String normalize(String text) =>
        normalized.putIfAbsent(text, () => _normalize(text));
    _entries = [for (final item in items) _Entry(item, normalize)];
    for (var i = 0; i < _entries.length; i++) {
      final item = _entries[i].item;
      final source = RegExp(r'^imported-(\d+)$').firstMatch(item.id)?[1];
      (_identities[normalize(item.id)] ??=
              <int>{})
          .add(i);
      if (source != null) {
        (_identities[source] ??= <int>{}).add(i);
        (_identities[normalize(item.generatorId)] ??= <int>{}).add(i);
      }
      for (final word in _entries[i].words.keys) {
        (_index[word] ??= <int>{}).add(i);
      }
    }
  }
  late final List<_Entry> _entries;
  final _index = <String, Set<int>>{};
  final _identities = <String, Set<int>>{};
  late final _vocabulary = _index.keys
      .where((w) => RegExp(r'^\p{L}{4,}$', unicode: true).hasMatch(w))
      .toList();

  CatalogSearchResult search(String text) {
    final query = _Query(importedCollectionId(text));
    final direct = _match(query);
    if (direct.isNotEmpty || query.tokens.isEmpty) {
      return CatalogSearchResult(direct);
    }
    // Only an unknown alphabetic word may be corrected. IDs, dimensions,
    // collections and known words never get broadened to make a match.
    final alternatives = <String, String>{};
    for (final token in query.tokens) {
      final limit = token.length >= 8
          ? 2
          : token.length >= 4
          ? 1
          : 0;
      if (limit == 0 ||
          _index.containsKey(token) ||
          !RegExp(r'^\p{L}+$', unicode: true).hasMatch(token)) {
        continue;
      }
      var best = limit + 1;
      String? closest;
      var ambiguous = false;
      for (final word in _vocabulary) {
        if ((word.length - token.length).abs() > limit) continue;
        final distance = _distance(token, word);
        if (distance < best) {
          best = distance;
          closest = word;
          ambiguous = false;
        } else if (distance == best) {
          ambiguous = true;
        }
      }
      if (closest != null && best <= limit && !ambiguous) {
        alternatives[token] = closest;
      }
    }
    if (alternatives.isNotEmpty) {
      final phrase = query.tokens.map((t) => alternatives[t] ?? t).join(' ');
      final corrected = query.replacePhrase(phrase);
      final matches = _match(_Query(corrected));
      if (matches.isNotEmpty) {
        return CatalogSearchResult(matches, correctedQuery: corrected);
      }
    }
    return CatalogSearchResult(const [], suggestions: _suggest(query));
  }

  List<LibraryItem> _match(_Query q) {
    // Source-ID lookups retain every record, including duplicate content.
    final exactIds = [
      for (final i in _identities[q.phrase] ?? const <int>{})
        if (q.allows(_entries[i])) _entries[i].item,
    ];
    if (exactIds.isNotEmpty) return exactIds;
    Set<int>? candidates;
    final matches = <String, Set<String>>{};
    for (var t = 0; t < q.tokens.length; t++) {
      final token = q.tokens[t];
      final words = <String>{if (_index.containsKey(token)) token};
      // Complete only the final, unfinished word. An existing whole word such
      // as "cat" must not expand into "cathedral".
      if (words.isEmpty &&
          t == q.tokens.length - 1 &&
          token.length >= 4 &&
          !_number.hasMatch(token)) {
        words.addAll(_index.keys.where((w) => w.startsWith(token)));
      }
      matches[token] = words;
      final ids = {for (final word in words) ...?_index[word]};
      candidates = candidates == null ? ids : candidates.intersection(ids);
      if (candidates.isEmpty) return [];
    }
    final scored = <(int, int, int)>[];
    for (final i
        in candidates ?? List.generate(_entries.length, (i) => i).toSet()) {
      final e = _entries[i];
      if (!q.allows(e)) continue;
      var score = 0, subjectOnly = true;
      for (final token in q.tokens) {
        var best = 0;
        for (final word in matches[token]!) {
          final value = e.words[word] ?? 0;
          final weighted = word == token ? value : value - 5;
          if (weighted > best) best = weighted;
        }
        score += best;
        if (best < 40) subjectOnly = false;
      }
      final tier = q.phrase.isNotEmpty && q.phrase == e.title
          ? 0
          : e.aliases.contains(q.phrase)
          ? 1
          : subjectOnly
          ? 2
          : 3;
      if (q.phrase.isNotEmpty && ' ${e.title} '.contains(' ${q.phrase} ')) {
        score += 40;
      }
      scored.add((tier, score, i));
    }
    scored.sort((a, b) {
      var order = a.$1.compareTo(b.$1);
      if (order == 0) order = b.$2.compareTo(a.$2);
      return order == 0 ? a.$3.compareTo(b.$3) : order;
    });
    final seen = <String>{};
    return [
      for (final result in scored)
        if (seen.add(_contentKey(_entries[result.$3].item)))
          _entries[result.$3].item,
    ];
  }

  List<String> _suggest(_Query q) {
    if (q.phrase.length < 4 || q.tokens.any(_number.hasMatch)) return [];
    final scored = <(String, double)>[];
    final seen = <String>{};
    for (final e in _entries) {
      if (!q.allows(e)) continue;
      for (final name in [e.title, ...e.aliases]) {
        if (!seen.add(name) || name.split(' ').length != q.tokens.length) {
          continue;
        }
        if ((name.length - q.phrase.length).abs() > 4) continue;
        final distance = _distance(q.phrase, name);
        final ratio =
            distance /
            (name.length > q.phrase.length ? name.length : q.phrase.length);
        if (distance <= 4 && ratio <= 0.35) scored.add((name, ratio));
      }
    }
    scored.sort((a, b) {
      final order = a.$2.compareTo(b.$2);
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
    return scored.take(3).map((s) => q.replacePhrase(s.$1)).toList();
  }
}

String _contentKey(LibraryItem item) {
  final sha = item.asset?.extra['sha256'];
  return item.asset?.type == 'clip-gzip' && sha is String
      ? 'clip:$sha'
      : 'id:${item.id}';
}

// Adjacent transpositions count as one spelling slip.
int _distance(String a, String b) {
  var before = List<int>.filled(b.length + 1, 0);
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      var best = previous[j] + 1;
      if (row[j - 1] + 1 < best) best = row[j - 1] + 1;
      final replace = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      if (replace < best) best = replace;
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          before[j - 2] + 1 < best) {
        best = before[j - 2] + 1;
      }
      row[j] = best;
    }
    before = previous;
    previous = row;
  }
  return previous.last;
}
