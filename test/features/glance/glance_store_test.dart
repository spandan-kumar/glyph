import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/glance/glance_model.dart';
import 'package:glyph/features/glance/glance_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GlanceCard card(String id) => GlanceCard(
    id: id,
    title: 'Trip',
    kind: GlanceKind.counter,
    date: DateTime(2026, 10, 9),
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('configuration persists separately and deleting a card preserves Show references', () async {
    final store = GlanceStore();
    addTearDown(store.dispose);
    await store.load();
    await store.saveCard(card('a'));
    await store.saveShow(
      PhoneShow(
        id: 's',
        title: 'Morning',
        entries: [const PhoneShowEntry(ShowEntryKind.card, 'a')],
      ),
    );
    final reload = GlanceStore();
    addTearDown(reload.dispose);
    await reload.load();
    expect(reload.cards.single.id, 'a');
    expect(reload.shows.single.entries.single.id, 'a');
    await reload.deleteCard('a');
    expect(reload.shows.single.entries.single.id, 'a');
    expect(reload.cards, isEmpty);
  });
  test('corrupt individual entries do not hide valid configuration', () async {
    SharedPreferences.setMockInitialValues({
      'glance.cards-shows.v1': jsonEncode({
        'cards': [
          {'broken': true},
          card('a').toJson(),
          card('a').toJson(),
        ],
        'shows': [
          {'broken': true},
        ],
      }),
    });
    final store = GlanceStore();
    addTearDown(store.dispose);
    await store.load();
    expect(store.cards.length, 1);
    expect(store.shows, isEmpty);
    expect(store.loaded, true);
  });
  test(
    'bounded store permits updates at capacity and rejects new cards',
    () async {
      final store = GlanceStore();
      addTearDown(store.dispose);
      await store.load();
      for (var i = 0; i < 24; i++) {
        await store.saveCard(card('$i'));
      }
      await store.saveCard(card('0'));
      expect(store.cards.length, 24);
      await expectLater(store.saveCard(card('new')), throwsStateError);
    },
  );
}
