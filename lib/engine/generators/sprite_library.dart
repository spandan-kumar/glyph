import 'sprite.dart';
import 'sprite_data.g.dart';

/// Every sprite the app knows: the packs compiled in from
/// `assets/catalog/sprites/` (see tool/build_sprites.dart) plus any registered
/// at runtime, e.g. from a remote catalog. Decoded lazily, once.
abstract final class SpriteLibrary {
  static final _byId = <String, SpriteGenerator>{};
  static final _bundled = <String>{};
  static final _remote = <String>{};
  static var _loaded = false;

  static void _ensure() {
    if (_loaded) return;
    _loaded = true;
    for (final src in builtInSpritePacks) {
      for (final s in Sprite.parsePack(src)) {
        final g = SpriteGenerator(s);
        _byId[g.id] = g;
        _bundled.add(g.id);
      }
    }
  }

  static List<SpriteGenerator> get all {
    _ensure();
    return List.unmodifiable(_byId.values);
  }

  static SpriteGenerator? byId(String generatorId) {
    if (!generatorId.startsWith(SpriteGenerator.prefix)) return null;
    _ensure();
    return _byId[generatorId];
  }

  static bool isBundled(String id) {
    _ensure();
    return _bundled.contains(id);
  }

  /// Installs a prevalidated snapshot in one synchronous step. Existing
  /// playback holds its generator; retired downloads leave the lookup table.
  static void replaceRemote(List<SpriteGenerator> sprites) {
    _ensure();
    for (final id in _remote) {
      _byId.remove(id);
    }
    _remote.clear();
    for (final g in sprites) {
      if (_bundled.contains(g.id)) continue;
      _byId[g.id] = g;
      _remote.add(g.id);
    }
  }

  /// Adds sprites from a pack JSON object; existing ids are kept, so a
  /// remote pack can't replace a built-in drawing. Returns the new ones.
  static List<SpriteGenerator> register(Map<String, dynamic> pack) {
    _ensure();
    final added = <SpriteGenerator>[];
    for (final s in Sprite.parsePackJson(pack)) {
      final g = SpriteGenerator(s);
      if (_byId.containsKey(g.id)) continue;
      _byId[g.id] = g;
      added.add(g);
    }
    return added;
  }
}
