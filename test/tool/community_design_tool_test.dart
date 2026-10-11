import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/library/community_design.dart';

import '../../tool/community_design.dart';

CommunityDesign drawing({
  String title = 'Tiny Fish',
  int side = 16,
  int count = 2,
}) => CommunityDesign.fromClip(
  FrameClip(
    width: side,
    height: side,
    frames: [
      for (var i = 0; i < count; i++)
        Frame(side, side)..set(i % side, i % side, 0xFFB547),
    ],
    delaysMs: List.filled(count, 120),
  ),
  title: title,
);

Map<String, dynamic> add(
  CommunityDesign design, {
  String credit = '',
  Map<String, dynamic>? pack,
  Set<String> titles = const {},
  Set<String> ids = const {},
  String author = 'artist',
  String url = 'https://github.com/spandan-kumar/glyph/issues/12',
  int issue = 12,
}) => appendDesign(
  design: design,
  issue: issue,
  author: author,
  url: url,
  added: 5,
  credit: credit,
  pack: pack,
  catalogTitles: titles,
  spriteIds: ids,
);

void main() {
  test('slug is safe, bounded, and has a non-Latin fallback', () {
    expect(designSlug('  Fish & CHIPS --! '), 'fish-chips');
    expect(designSlug('a' * 29 + ' xx'), 'a' * 29);
    expect(designSlug('a' * 40).length, 30);
    expect(designSlug('灯'), 'drawing');
    expect(designSlug(r'$(touch /tmp/x) `hi`'), 'touch-tmp-x-hi');
  });

  test(
    'credit strips markup, controls, compiler delimiters and bounds Unicode',
    () {
      expect(
        cleanCredit('<b>**Jane**</b> [Doe](https://example.org)\n'),
        'Jane Doe',
      );
      expect(cleanCredit("'''\u0000`_*~"), '');
      expect(cleanCredit('🌟' * 50).runes.length, 40);
    },
  );

  test('credit comes only from the issue section, ignores fenced headings', () {
    expect(
      creditFromBody(
        '### Design\n```text\n### How should we credit you?\nFake\n```\n'
        '### How should we credit you?\n\n**Jane**\n\n### Before sharing\n- [x] Done',
      ),
      'Jane',
    );
    expect(
      creditFromBody(
        '### How should we credit you?\n\n_No response_\n\n### Rules',
      ),
      '',
    );
    expect(creditFromBody('No section'), '');
  });

  test(
    'append creates a CC0 pack and does not mutate it on later additions',
    () {
      final pack = add(drawing());
      final sprite = (pack['sprites'] as List).single as Map;
      expect(pack['category'], 'Community');
      expect(sprite['id'], 'community-tiny-fish-12');
      expect(sprite['source'], containsPair('creator', '@artist'));
      expect(sprite['source'], containsPair('license', 'CC0-1.0'));
      final next = add(drawing(title: 'Wave'), pack: pack);
      expect((pack['sprites'] as List).length, 1);
      expect((next['sprites'] as List).length, 2);
    },
  );

  test('title collisions are case insensitive, including credited titles', () {
    final pack = add(
      drawing(),
      credit: '**Jane**',
      titles: {'tiny fish', 'Tiny Fish by Jane'},
    );
    expect(
      (pack['sprites'] as List).single['title'],
      'Tiny Fish by Jane (12-2)',
    );
    expect((pack['sprites'] as List).single['source']['creator'], 'Jane');
  });

  test('refuses duplicate ids and hostile issue metadata', () {
    expect(
      () => add(drawing(), pack: add(drawing())),
      throwsA(isA<CommunityDesignException>()),
    );
    expect(
      () => add(drawing(), ids: {'community-tiny-fish-12'}),
      throwsA(isA<CommunityDesignException>()),
    );
    for (final author in ['../x', 'a\nwrite', r'$(whoami)', '-flag']) {
      expect(
        () => add(drawing(), author: author),
        throwsA(isA<CommunityDesignException>()),
      );
    }
    for (final url in [
      'https://evil.test/issues/12',
      'https://github.com/spandan-kumar/glyph/issues/13',
      'https://github.com/spandan-kumar/glyph/issues/12?x=1',
    ]) {
      expect(
        () => add(drawing(), url: url),
        throwsA(isA<CommunityDesignException>()),
      );
    }
    expect(
      () => add(drawing(), issue: 0),
      throwsA(isA<CommunityDesignException>()),
    );
  });

  test('valid check writes a scaled GIF, JSON and safe report; failed recheck cleans artifacts', () {
    final out = Directory.systemTemp.createTempSync('glyph-community-test-');
    addTearDown(() => out.deleteSync(recursive: true));
    final design = drawing(title: '*Fish* @everyone &amp;');
    expect(
      checkSubmission('### Design\n```text\n${design.encode()}\n```', out),
      0,
    );
    final bytes = File('${out.path}/preview.gif').readAsBytesSync();
    expect(ascii.decode(bytes.take(6).toList()), 'GIF89a');
    expect(bytes[6] | bytes[7] << 8, 128);
    expect(
      jsonDecode(File('${out.path}/design.json').readAsStringSync()),
      design.toJson(),
    );
    final report = File('${out.path}/report.md').readAsStringSync();
    expect(report, contains(communityMarker));
    expect(report, contains('&#42;Fish&#42; &#64;everyone &#38;amp;'));
    expect(checkSubmission('No token', out), 1);
    expect(File('${out.path}/preview.gif').existsSync(), isFalse);
    expect(File('${out.path}/design.json').existsSync(), isFalse);
    expect(
      File('${out.path}/report.md').readAsStringSync(),
      contains('No design found'),
    );
    expect(
      File('${out.path}/report.md').readAsStringSync(),
      contains(shareAgain),
    );
  });

  test('malformed inflated JSON gets a friendly report', () {
    final out = Directory.systemTemp.createTempSync('glyph-community-test-');
    addTearDown(() => out.deleteSync(recursive: true));
    final token =
        CommunityDesign.prefix +
        base64Url.encode(ZLibEncoder().convert(utf8.encode('{')));
    expect(checkSubmission(token, out), 1);
    expect(
      File('${out.path}/report.md').readAsStringSync(),
      contains('The design text is damaged'),
    );
  });

  test('maximum design preview respects encoder allocation limits', () {
    final bytes = previewGif(drawing(side: 64, count: 48));
    expect(bytes[6] | bytes[7] << 8, 384);
    expect(bytes.last, 0x3B);
  });

  test('blank and compiler-breaking designs fail before approval', () {
    final blank = CommunityDesign.fromClip(
      FrameClip(width: 2, height: 2, frames: [Frame(2, 2)], delaysMs: [100]),
      title: 'Blank',
    );
    expect(
      () => decodeSubmission(blank.encode()),
      throwsA(isA<CommunityDesignException>()),
    );
    expect(
      () => decodeSubmission(drawing(title: "Fish'''s").encode()),
      throwsA(isA<CommunityDesignException>()),
    );
  });

  test('validator permits only issue-backed CC0 community provenance', () {
    final out = Directory.systemTemp.createTempSync(
      'glyph-community-validator-',
    );
    addTearDown(() => out.deleteSync(recursive: true));
    final pack = add(drawing());
    final sprite = (pack['sprites'] as List).single as Map;
    final source = Map<String, dynamic>.from(sprite['source'] as Map);
    final file = File('${out.path}/pack.json');
    int validate(Map<String, dynamic> value) {
      sprite['source'] = value;
      file.writeAsStringSync(jsonEncode(pack));
      return Process.runSync('python3', [
        'skills/glyph-animation/scripts/validate_sprite.py',
        '--pack',
        file.path,
      ]).exitCode;
    }

    expect(validate(source), 0);
    for (final field in ['downloadUrl', 'sha256', 'file']) {
      expect(validate({...source, field: null}), 1, reason: field);
    }
    expect(validate({...source, 'license': 'MIT'}), 1);
    expect(validate({...source}..remove('license')), 1);
    expect(validate({...source, 'licenseUrl': 'https://example.org/'}), 1);
    expect(
      validate({
        ...source,
        'url': 'https://github.com/spandan-kumar/glyph/issues/0',
      }),
      1,
    );
    expect(
      validate({
        ...source,
        'url': 'https://github.com/other/repo/issues/12',
        'downloadUrl': 'https://example.org/art.png',
        'sha256': 'a' * 64,
        'file': 'art.png',
      }),
      1,
    );
    // Imported art outside Community still needs every pinned-download field.
    pack['category'] = 'Animals';
    expect(validate(source), 1);
    expect(
      validate({
        ...source,
        'downloadUrl': 'https://example.org/art.png',
        'sha256': 'a' * 64,
        'file': 'art.png',
      }),
      0,
    );
  });

  test('source stays readable by published apps', () {
    // RemoteCatalog in shipped apps drops sprites whose source has a
    // non-string value other than year, so the whole drawing would vanish.
    final pack = add(drawing(title: 'Old App Safe'));
    final source = ((pack['sprites'] as List).single as Map)['source'] as Map;
    for (final e in source.entries) {
      expect(e.key == 'year' ? e.value is int : e.value is String, isTrue, reason: '${e.key}');
    }
    expect(source['added'], '5');
  });
}
