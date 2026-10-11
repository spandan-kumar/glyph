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
  test('unreadable entries and unknown fields round-trip unchanged', () async {
    final future = {'kind': 'hologram', 'id': 'f', 'title': 'Future'};
    SharedPreferences.setMockInitialValues({
      GlanceStore.key: jsonEncode({
        'version': 2,
        'cards': [future, card('a').toJson()],
        'shows': [
          {'id': 'x', 'title': 'x', 'entries': 'later'},
        ],
        'theme': {'a': 1},
      }),
    });
    final store = GlanceStore();
    addTearDown(store.dispose);
    await store.load();
    expect(store.cards.single.id, 'a');
    expect(store.unreadable, 2);
    await store.saveCard(card('b'));
    final saved = jsonDecode(
      (await SharedPreferences.getInstance()).getString(GlanceStore.key)!,
    ) as Map;
    expect(saved['version'], 1);
    expect(saved['theme'], {'a': 1});
    expect((saved['cards'] as List).last, future);
    expect((saved['cards'] as List).length, 3);
    expect((saved['shows'] as List).single['entries'], 'later');
  });
  test('a file that cannot be parsed is set aside, not overwritten', () async {
    SharedPreferences.setMockInitialValues({GlanceStore.key: '{not json'});
    final store = GlanceStore();
    addTearDown(store.dispose);
    await store.load();
    await store.saveCard(card('a'));
    final p = await SharedPreferences.getInstance();
    expect(p.getString('${GlanceStore.key}.unreadable'), '{not json');
    expect(p.getString(GlanceStore.key), contains('"version":1'));
  });
  test('load never truncates; only adding is capped', () async {
    SharedPreferences.setMockInitialValues({
      GlanceStore.key: jsonEncode({
        'cards': [for (var i = 0; i < 30; i++) card('$i').toJson()],
      }),
    });
    final store = GlanceStore();
    addTearDown(store.dispose);
    await store.load();
    expect(store.cards.length, 30);
    await expectLater(store.saveCard(card('new')), throwsStateError);
    await store.saveCard(card('3'));
    expect(
      (jsonDecode(
        (await SharedPreferences.getInstance()).getString(GlanceStore.key)!,
      ) as Map)['cards'],
      hasLength(30),
    );
  });
  test('a failed write does not notify or change state', () async {
    var fail = true;
    final store = GlanceStore(write: (_) async => !fail);
    addTearDown(store.dispose);
    await store.load();
    var notified = 0;
    store.addListener(() => notified++);
    await expectLater(store.saveCard(card('a')), throwsStateError);
    expect(store.cards, isEmpty);
    expect(notified, 0);
    fail = false;
    await store.saveCard(card('a'));
    expect(store.cards.length, 1);
    expect(notified, 1);
  });
  test('saving before load finishes cannot erase stored data', () async {
    SharedPreferences.setMockInitialValues({
      GlanceStore.key: jsonEncode({
        'cards': [card('old').toJson()],
      }),
    });
    final store = GlanceStore();
    addTearDown(store.dispose);
    await store.saveCard(card('new'));
    expect(store.cards.map((c) => c.id), containsAll(['old', 'new']));
  });
}
