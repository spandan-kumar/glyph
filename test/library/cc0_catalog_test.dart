import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/engine/gif_baker.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/library/catalog.dart';

void main() {
  final catalog = Catalog.parse(
    File('assets/catalog/catalog.json').readAsStringSync(),
  );
  final artists = SpriteLibrary.all
      .where((g) => g.sprite.source?['license'] == 'CC0-1.0')
      .toList();

  test('CC0 art has one credited new item and source provenance', () {
    expect(artists, isNotEmpty);
    for (final g in artists) {
      final source = g.sprite.source!;
      expect(source['url'], startsWith('https://'));
      expect(
        source['licenseUrl'],
        'https://creativecommons.org/publicdomain/zero/1.0/',
      );
      expect(source['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      final item = catalog.items.where((i) => i.generatorId == g.id).single;
      expect(item.notice, contains(source['creator']));
      expect(item.notice, contains('CC0'));
      expect(item.tags, contains('cc0'));
      expect(item.tags, isNot(contains('classic')));
      expect(item.added, 4);
      expect(catalog.search(item.title).first.id, item.id);
    }
  });

  test('artist loops retain their full timing on both device sizes', () {
    for (final g in artists) {
      for (final n in [16, 32]) {
        final loop = renderDeviceLoop(
          generator: g,
          params: Params.defaultsFor(g),
          palette: paletteById(g.defaultPalette),
          width: n,
          height: n,
        );
        expect(
          loop.seconds,
          closeTo(g.sprite.loopMs / 1000, 1e-8),
          reason: '${g.id} at $n',
        );
        expect(loop.frameSeconds, everyElement(inExclusiveRange(0, 1.001)));
        expect(
          loop.frameSeconds!.reduce((a, b) => a + b),
          closeTo(loop.seconds, 1e-8),
        );
        expect(bakeLoop(loop).bytes.take(6), 'GIF89a'.codeUnits);
      }
    }
  });
}
