import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/clip.dart';

/// Something the user made: a drawing, imported GIF or text animation.
class Creation {
  Creation({
    required this.id,
    required this.title,
    required this.kind,
    required this.clip,
    required this.updatedAt,
    this.meta = const {},
  });

  final String id;
  final String title;

  /// 'drawing' | 'import' | 'text' (free-form so features can add kinds).
  final String kind;
  final FrameClip clip;
  final DateTime updatedAt;

  /// Feature-specific data needed to re-open the creation for editing
  /// (e.g. text settings). Must be JSON-encodable.
  final Map<String, dynamic> meta;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind,
        'updatedAt': updatedAt.toIso8601String(),
        'meta': meta,
        'clip': clip.toJson(),
      };

  factory Creation.fromJson(Map<String, dynamic> j) => Creation(
        id: j['id'] as String,
        title: j['title'] as String,
        kind: j['kind'] as String,
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        meta: Map<String, dynamic>.from(j['meta'] as Map? ?? const {}),
        clip: FrameClip.fromJson(Map<String, dynamic>.from(j['clip'] as Map)),
      );
}

/// Persists creations as one JSON file each in the app documents directory.
class CreationsStore extends ChangeNotifier {
  CreationsStore({Future<Directory> Function()? directory})
      : _directory = directory ?? _defaultDir;

  final Future<Directory> Function() _directory;
  List<Creation> _items = [];
  bool _loaded = false;

  List<Creation> get items => List.unmodifiable(_items);
  bool get isLoaded => _loaded;

  static Future<Directory> _defaultDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/creations').create(recursive: true);
  }

  Future<void> load() async {
    final dir = await _directory();
    final out = <Creation>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        out.add(Creation.fromJson(jsonDecode(await f.readAsString())));
      } catch (_) {
        // A corrupt file shouldn't take the whole list down.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _items = out;
    _loaded = true;
    notifyListeners();
  }

  /// Inserts or replaces by id. Pass `id: null` to create a new one.
  Future<Creation> save({
    String? id,
    required String title,
    required String kind,
    required FrameClip clip,
    Map<String, dynamic> meta = const {},
  }) async {
    final c = Creation(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      title: title,
      kind: kind,
      clip: clip,
      meta: meta,
      updatedAt: DateTime.now(),
    );
    final dir = await _directory();
    await File('${dir.path}/${c.id}.json').writeAsString(jsonEncode(c.toJson()));
    _items = [c, ..._items.where((x) => x.id != c.id)];
    notifyListeners();
    return c;
  }

  Future<void> delete(String id) async {
    final dir = await _directory();
    final f = File('${dir.path}/$id.json');
    if (await f.exists()) await f.delete();
    _items = _items.where((x) => x.id != id).toList();
    notifyListeners();
  }
}
