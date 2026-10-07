import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/features/glance/glance_model.dart';
import 'package:glyph/features/glance/glance_session.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/catalog_store.dart';
import 'package:glyph/library/remote_catalog.dart';
import 'package:glyph/library/user_library.dart';
import 'package:glyph/ui/tune/channels.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/device/fake_wled.dart';
import 'catalog_fixture.dart';
import 'remote_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a retired download degrades gracefully in favourites, recents, Glance rotations and rails', () async {
    SharedPreferences.setMockInitialValues({});
    SpriteLibrary.replaceRemote([]);
    final dir = await Directory.systemTemp.createTemp('glyph-removed');
    addTearDown(() async {
      SpriteLibrary.replaceRemote([]);
      await dir.delete(recursive: true);
    });
    final key = await TestKey.create();
    final base = Catalog.parse(
      File('assets/catalog/starter.json').readAsStringSync(),
    );
    final host = FakeHost(await signedFixture(key), etag: null);
    final store = CatalogStore(
      bundled: base,
      remote: RemoteCatalog(
        url: Uri.parse('https://example.com/glyph/'),
        client: host.client,
        cacheDir: () async => dir,
        publicKey: base64.encode(key.publicKey),
      ),
    );
    addTearDown(store.dispose);
    await store.check();
    expect(store.catalog.byId('remote-dot-item'), isNotNull);

    final library = UserLibrary();
    addTearDown(library.dispose);
    await library.toggleFavourite('remote-dot-item');
    await library.markPlayed('remote-dot-item');

    final fake = FakeWled();
    final devices = DeviceStore(clientFactory: fake.client);
    final playback = PlaybackController();
    final session = GlanceSession(
      devices: devices,
      playback: playback,
      catalog: store.catalog,
      creations: CreationsStore(directory: () async => dir),
    );
    addTearDown(() {
      session.dispose();
      playback.dispose();
    });
    const remote = PhoneShowEntry(ShowEntryKind.library, 'remote-dot-item');
    final bundled = PhoneShowEntry(ShowEntryKind.library, base.items.first.id);
    final show = PhoneShow(
      id: 'rotation',
      title: 'Rotation',
      entries: [remote, bundled],
    );
    expect(session.resolve(remote), isNotNull);
    expect(session.entryTitle(remote), 'Dot');

    // A later catalog (rollback or takedown) no longer carries the item.
    host.set = await key.publish(
      {
        ...remoteDocument(revision: 5),
        'sprites': [],
        'items': [(remoteDocument()['items'] as List).first],
      },
    );
    await store.check();
    session.catalog = store.catalog;
    expect(store.catalog.byId('remote-dot-item'), isNull);
    expect(findGenerator('sprite:remote-dot'), isNull);

    // Personal IDs stay put; lookups quietly skip them.
    expect(library.favourites, contains('remote-dot-item'));
    expect(session.resolve(remote), isNull);
    expect(session.resolve(bundled), isNotNull);
    expect(session.entryTitle(remote), 'Unavailable');
    final channels = assembleChannels(
      base: CatalogChannels(store.catalog, DateTime(2026, 10, 7)),
      favourites: library.favourites,
      recents: library.recents,
      creations: const [],
    );
    expect(channels.any((c) => c.id == 'favs'), isFalse);
    expect(channels.any((c) => c.id == 'lately'), isFalse);
    expect(generatorById('sprite:remote-dot'), isNotNull);

    // The running rotation keeps rendering the surviving entry.
    final effect = session.showGenerator(show).create(16, 16, 1);
    final frame = Frame(16, 16);
    for (var i = 0; i < 5; i++) {
      effect.render(frame, i * .05, .05, Params.defaultsFor(session.showGenerator(show), const {}), paletteById('neon'));
    }

    // Restoring the item brings the favourite back untouched.
    host.set = await signedFixture(key, revision: 6);
    await store.check();
    session.catalog = store.catalog;
    expect(session.resolve(remote), isNotNull);
    expect(library.favourites, contains('remote-dot-item'));
  });
}
