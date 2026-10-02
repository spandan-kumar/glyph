import '../../../library/catalog.dart';

/// A date-driven collection for the "seasonal" shelf.
class Season {
  const Season(this.title, this.tags);

  final String title;
  final List<String> tags;
}

/// Picks the collection for [now]. Moving festivals (Diwali, Eid, Easter)
/// use generous windows rather than exact dates.
Season seasonFor(DateTime now) {
  final m = now.month, d = now.day;
  bool from(int m1, int d1, int m2, int d2) {
    final v = m * 100 + d, a = m1 * 100 + d1, b = m2 * 100 + d2;
    return a <= b ? v >= a && v <= b : v >= a || v <= b;
  }

  if (from(12, 26, 1, 7)) return const Season('New Year Countdown', ['new year', 'nye', 'fireworks', 'celebrate']);
  if (from(1, 8, 1, 31)) return const Season('Winter Cozy', ['winter', 'snow', 'cozy', 'cold']);
  if (from(2, 1, 2, 15)) return const Season("Valentine's Day", ['valentine', 'love', 'heart', 'romantic']);
  if (from(2, 16, 3, 31)) return const Season('Spring Festivals', ['holi', 'eid', 'ramadan', 'spring', 'st patricks']);
  if (from(4, 1, 4, 30)) return const Season('Easter & Spring', ['easter', 'spring', 'bunny', 'flower']);
  if (from(5, 1, 5, 31)) return const Season('In Bloom', ['flower', 'garden', 'spring', 'butterfly']);
  if (from(6, 1, 8, 31)) return const Season('Summer Vibes', ['summer', 'beach', 'tropical', 'sun']);
  if (from(9, 1, 9, 30)) return const Season('Hello Autumn', ['autumn', 'fall', 'leaf', 'harvest']);
  if (from(10, 1, 10, 31)) return const Season('Spooky Season', ['halloween', 'spooky']);
  if (from(11, 1, 11, 20)) return const Season('Festival of Lights', ['diwali', 'festival of lights', 'diya', 'lights']);
  if (from(11, 21, 11, 30)) return const Season('Harvest Time', ['thanksgiving', 'harvest', 'autumn']);
  return const Season('Holiday Season', ['christmas', 'hanukkah', 'winter', 'snow']);
}

/// Up to [limit] items for [season], favouring items matching earlier tags
/// and avoiding several looks of the same animation in a row.
List<LibraryItem> seasonalItems(Catalog catalog, Season season, {int limit = 20}) {
  final out = <LibraryItem>[];
  final gens = <String>{};
  for (final tag in season.tags) {
    for (final i in catalog.tagged([tag])) {
      if (out.length >= limit) return out;
      if (out.contains(i) || !gens.add(i.generatorId)) continue;
      out.add(i);
    }
  }
  return out;
}
