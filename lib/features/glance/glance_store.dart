import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glance_model.dart';

class GlanceStore extends ChangeNotifier {
  List<GlanceCard> _cards = [];
  List<PhoneShow> _shows = [];
  List<GlanceCard> get cards => List.unmodifiable(_cards);
  List<PhoneShow> get shows => List.unmodifiable(_shows);
  GlanceCard? card(String id) => _cards.where((c) => c.id == id).firstOrNull;
  PhoneShow? show(String id) => _shows.where((s) => s.id == id).firstOrNull;
  bool loaded = false;
  bool _disposed = false;
  Future<void> _writing = Future.value();
  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    if (_disposed) return;
    final raw = p.getString('glance.cards-shows.v1');
    if (raw != null && raw.length <= 128 * 1024) {
      try {
        final data = jsonDecode(raw) as Map;
        for (final c in (data['cards'] as List? ?? []).take(24)) {
          try {
            final card = GlanceCard.fromJson(c as Map);
            if (this.card(card.id) == null) _cards.add(card);
          } catch (_) {}
        }
        for (final s in (data['shows'] as List? ?? []).take(12)) {
          try {
            final show = PhoneShow.fromJson(s as Map);
            if (this.show(show.id) == null) _shows.add(show);
          } catch (_) {}
        }
      } catch (_) {}
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> saveCard(GlanceCard value) async {
    if (!value.valid) throw ArgumentError('Invalid card');
    if (_cards.length >= 24 && card(value.id) == null) {
      throw StateError('You can keep up to 24 cards.');
    }
    _cards = [..._cards.where((c) => c.id != value.id), value];
    notifyListeners();
    await _save();
  }

  Future<void> saveShow(PhoneShow value) async {
    if (!value.valid) throw ArgumentError('Invalid Show');
    if (_shows.length >= 12 && show(value.id) == null) {
      throw StateError('You can keep up to 12 phone Shows.');
    }
    _shows = [..._shows.where((s) => s.id != value.id), value];
    notifyListeners();
    await _save();
  }

  Future<void> deleteCard(String id) async {
    _cards.removeWhere((c) => c.id == id);
    // References remain visible as unavailable so Shows are never silently rewritten.
    notifyListeners();
    await _save();
  }

  Future<void> deleteShow(String id) async {
    _shows.removeWhere((s) => s.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> _save() {
    final raw = jsonEncode({
      'cards': _cards.map((c) => c.toJson()).toList(),
      'shows': _shows.map((s) => s.toJson()).toList(),
    });
    _writing = _writing.catchError((_) {}).then((_) async {
      final p = await SharedPreferences.getInstance();
      await p.setString('glance.cards-shows.v1', raw);
    });
    return _writing;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
