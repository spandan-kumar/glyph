import 'dart:convert';
import 'dart:io' show ZLibEncoder;

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generators/sprite.dart';
import 'package:glyph/library/community_design.dart';

FrameClip _clip({int w = 16, int h = 16, int frames = 2, int colours = 3}) => FrameClip(
  width: w,
  height: h,
  frames: [
    for (var f = 0; f < frames; f++)
      Frame(w, h)..let((fr) {
        for (var i = 0; i < w * h; i++) {
          final k = (i + f) % (colours + 1);
          if (k > 0) fr.set(i % w, i ~/ w, 0x101010 * k + k);
        }
      }),
  ],
  delaysMs: List.filled(frames, 120),
);

extension<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}

String _wire(Object json) =>
    CommunityDesign.prefix + base64Url.encode(ZLibEncoder().convert(utf8.encode(jsonEncode(json)))).replaceAll('=', '');

void main() {
  test('round-trips a clip through the issue text', () {
    final clip = _clip();
    final d = CommunityDesign.fromClip(clip, title: '  Tiny   Fish ');
    expect(d.title, 'Tiny Fish');
    final back = CommunityDesign.decode('Some text\n\n```\n${d.encode()}\n```\n');
    expect(back.toJson(), d.toJson());
    final out = back.toClip();
    for (var f = 0; f < clip.frames.length; f++) {
      expect(out.frames[f].rgb, clip.frames[f].rgb);
    }
    expect(out.delaysMs, [120, 120]);
  });

  test('black is transparent and needs no colour key', () {
    final d = CommunityDesign.fromClip(_clip(colours: 1), title: 'Dots');
    expect(d.colors.length, 1);
    expect(d.frames.first.first, contains('.'));
  });

  test('merges colours past the key limit', () {
    final w = 64, h = 64;
    final f = Frame(w, h);
    for (var i = 0; i < w * h; i++) {
      f.set(i % w, i ~/ w, (i * 2654435761) & 0xFFFFFF | 0x010101);
    }
    final d = CommunityDesign.fromClip(FrameClip(width: w, height: h, frames: [f], delaysMs: [100]), title: 'Noise');
    expect(d.colors.length, lessThanOrEqualTo(CommunityDesign.keys.length));
    expect(CommunityDesign.decode(d.encode()).toJson(), d.toJson());
  });

  test('refuses what cannot be shared', () {
    expect(() => CommunityDesign.fromClip(_clip(), title: '  '), throwsA(isA<CommunityDesignException>()));
    expect(() => CommunityDesign.fromClip(_clip(w: 65, h: 8), title: 'x'), throwsA(isA<CommunityDesignException>()));
    expect(() => CommunityDesign.fromClip(_clip(frames: 49), title: 'x'), throwsA(isA<CommunityDesignException>()));
  });

  test('cleans titles of markup and control characters', () {
    expect(CommunityDesign.cleanTitle('<b>Hi</b> `x` [y](z)\n'), 'bHi/b x y(z)');
    expect(CommunityDesign.cleanTitle('a' * 80).length, CommunityDesign.maxTitle);
  });

  group('decode rejects hostile input', () {
    final good = CommunityDesign.fromClip(_clip(), title: 'Ok').toJson();
    Map<String, dynamic> with_(String k, Object? v) => {...good, k: v};

    for (final (name, json) in [
      ('version', with_('v', 2)),
      ('size', with_('w', 100)),
      ('pixels', with_('w', 64)..['h'] = 65),
      ('colour value', with_('colors', {'A': 'red'})),
      ('colour key', with_('colors', {'AB': '#FFFFFF'})),
      ('unknown colour', with_('colors', <String, String>{})),
      ('timing count', with_('ms', [100])),
      ('frame time', with_('ms', [1, 1])),
      ('title markup', with_('title', '<script>')),
      ('frame width', with_('frames', [['...'], ['...']])),
    ]) {
      test(name, () => expect(() => CommunityDesign.decode(_wire(json)), throwsA(isA<CommunityDesignException>())));
    }

    test('missing token', () => expect(() => CommunityDesign.decode('nothing here'), throwsA(isA<CommunityDesignException>())));
    test('damaged base64', () => expect(() => CommunityDesign.decode('${CommunityDesign.prefix}@@@'), throwsA(isA<CommunityDesignException>())));
    test('not zlib', () => expect(() => CommunityDesign.decode('${CommunityDesign.prefix}aGVsbG8'), throwsA(isA<CommunityDesignException>())));
    test('zip bomb', () {
      final bomb = CommunityDesign.prefix +
          base64Url.encode(ZLibEncoder(level: 9).convert(List.filled(5000000, 0x20))).replaceAll('=', '');
      expect(bomb.length, lessThan(CommunityDesign.maxEncoded));
      expect(() => CommunityDesign.decode(bomb), throwsA(isA<CommunityDesignException>()));
    });
    test('oversized token', () {
      expect(() => CommunityDesign.decode(CommunityDesign.prefix + 'A' * (CommunityDesign.maxEncoded + 1)),
          throwsA(isA<CommunityDesignException>()));
    });
  });

  test('becomes a sprite the catalog parser accepts', () {
    final d = CommunityDesign.fromClip(_clip(), title: 'Tiny Fish');
    final sprite = d.toSprite(id: 'community-tiny-fish-12', creator: '@someone', url: 'https://github.com/x/y/issues/12');
    final parsed = Sprite.parsePackJson({
      'pack': 'community',
      'category': 'Community',
      'sprites': [sprite],
    });
    expect(parsed.single.id, 'community-tiny-fish-12');
    expect(sprite['tags'], containsAll(['community', 'tiny', 'fish']));
    expect((sprite['source'] as Map)['notice'], 'By @someone · CC0');
  });
}
