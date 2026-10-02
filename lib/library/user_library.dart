import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's favourites and recently played items, persisted by item id.
/// Unknown ids (items removed from the catalog) are kept but simply never
/// match anything, so a catalog downgrade doesn't wipe someone's hearts.
class UserLibrary extends ChangeNotifier {
  UserLibrary({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  /// App-wide instance; Discover uses it unless one is injected.
  static final shared = UserLibrary();

  static const favouritesKey = 'library.favourites';
  static const recentsKey = 'library.recents';
  static const maxRecents = 24;

  final Future<SharedPreferences> Function() _prefs;
  final _favourites = <String>{};
  final _recents = <String>[];
  Future<void>? _loading;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  Set<String> get favourites => Set.unmodifiable(_favourites);

  /// Most recent first.
  List<String> get recents => List.unmodifiable(_recents);

  bool isFavourite(String id) => _favourites.contains(id);

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final p = await _prefs();
    // Merge rather than replace, in case the user tapped before load finished.
    _favourites.addAll(p.getStringList(favouritesKey) ?? const []);
    for (final id in p.getStringList(recentsKey) ?? const <String>[]) {
      if (!_recents.contains(id)) _recents.add(id);
    }
    if (_recents.length > maxRecents) _recents.removeRange(maxRecents, _recents.length);
    _loaded = true;
    notifyListeners();
  }

  Future<void> toggleFavourite(String id) async {
    if (!_favourites.remove(id)) _favourites.add(id);
    notifyListeners();
    await load();
    await (await _prefs()).setStringList(favouritesKey, _favourites.toList());
  }

  Future<void> markPlayed(String id) async {
    if (_recents.isNotEmpty && _recents.first == id) return;
    _recents
      ..remove(id)
      ..insert(0, id);
    if (_recents.length > maxRecents) _recents.removeLast();
    notifyListeners();
    await load();
    await (await _prefs()).setStringList(recentsKey, _recents);
  }

  Future<void> clearRecents() async {
    _recents.clear();
    notifyListeners();
    await (await _prefs()).remove(recentsKey);
  }
}
