import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glance_model.dart';

/// Cards and rotations (phone-driven sequences; stored under the legacy
/// `shows` key). Entries this build cannot read are kept as raw JSON and
/// written back unchanged, so a newer or damaged record is never lost.
class GlanceStore extends ChangeNotifier {
  GlanceStore({@visibleForTesting Future<bool> Function(String value)? write})
    : _write = write; // ignore: prefer_initializing_formals
  final Future<bool> Function(String value)? _write;
  static const key = 'glance.cards-shows.v1';
  static const version = 1;
  static const maxCards = 24, maxShows = 12;
  static const maxBytes = 1024 * 1024;

  List<GlanceCard> _cards = [];
  List<PhoneShow> _shows = [];
  List<Object?> _rawCards = [], _rawShows = [];
  Map<String, Object?> _extra = {};
  List<GlanceCard> get cards => List.unmodifiable(_cards);
  List<PhoneShow> get shows => List.unmodifiable(_shows);
  GlanceCard? card(String id) => _cards.where((c) => c.id == id).firstOrNull;
  PhoneShow? show(String id) => _shows.where((s) => s.id == id).firstOrNull;

  /// Count of stored entries this build could not read (kept, not shown).
  int get unreadable => _rawCards.length + _rawShows.length;
  bool loaded = false;
  bool _disposed = false;
  Future<void>? _loading;
  Future<void> _writing = Future.value();
  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (_disposed) return;
    final raw = p.getString(key);
    if (raw != null) {
      try {
        if (raw.length > maxBytes) throw const FormatException('too large');
        final data = jsonDecode(raw) as Map;
        _extra = {
          for (final e in data.entries)
            if (e.key is String && e.key != 'cards' && e.key != 'shows')
              e.key as String: e.value,
        };
        for (final c in data['cards'] as List? ?? const []) {
          try {
            final card = GlanceCard.fromJson(c as Map);
            if (this.card(card.id) != null) throw const FormatException('dup');
            _cards.add(card);
          } catch (_) {
            _rawCards.add(c);
          }
        }
        for (final s in data['shows'] as List? ?? const []) {
          try {
            final show = PhoneShow.fromJson(s as Map);
            if (this.show(show.id) != null) throw const FormatException('dup');
            _shows.add(show);
          } catch (_) {
            _rawShows.add(s);
          }
        }
      } catch (_) {
        // Unparseable as a whole: keep the bytes aside before anything is
        // written over them.
        _cards = [];
        _shows = [];
        _rawCards = [];
        _rawShows = [];
        _extra = {};
        try {
          await p.setString('$key.unreadable', raw);
        } catch (_) {}
      }
    }
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> saveCard(GlanceCard value) async {
    if (!value.valid) throw ArgumentError('Invalid card');
    await _mutate(() {
      if (_cards.length >= maxCards && card(value.id) == null) {
        throw StateError('You can keep up to $maxCards cards.');
      }
      return ([..._cards.where((c) => c.id != value.id), value], _shows);
    });
  }

  Future<void> saveShow(PhoneShow value) async {
    if (!value.valid) throw ArgumentError('Invalid rotation');
    await _mutate(() {
      if (_shows.length >= maxShows && show(value.id) == null) {
        throw StateError('You can keep up to $maxShows rotations.');
      }
      return (_cards, [..._shows.where((s) => s.id != value.id), value]);
    });
  }

  Future<void> deleteCard(String id) async {
    // References remain visible as unavailable so rotations are never silently rewritten.
    await _mutate(() => ([..._cards.where((c) => c.id != id)], _shows));
  }

  Future<void> deleteShow(String id) async {
    await _mutate(() => (_cards, [..._shows.where((s) => s.id != id)]));
  }

  /// Runs after load and after earlier writes; commits and notifies only once
  /// the write has succeeded, so a failed write leaves memory and disk equal.
  Future<void> _mutate((List<GlanceCard>, List<PhoneShow>) Function() change) {
    final run = _writing.catchError((_) {}).then((_) async {
      await load();
      if (_disposed) return;
      final (cards, shows) = change();
      final raw = jsonEncode({
        ..._extra,
        'version': version,
        'cards': [...cards.map((c) => c.toJson()), ..._rawCards],
        'shows': [...shows.map((s) => s.toJson()), ..._rawShows],
      });
      final ok = _write != null
          ? await _write(raw)
          : await (await SharedPreferences.getInstance()).setString(key, raw);
      if (!ok) {
        throw StateError('Could not save.');
      }
      _cards = cards;
      _shows = shows;
      if (!_disposed) notifyListeners();
    });
    _writing = run;
    return run;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
