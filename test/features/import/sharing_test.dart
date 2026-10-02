import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/features/import/decode.dart';
import 'package:glyph/features/import/sharing.dart';

Creation _creation() {
  final a = Frame(4, 2)..fill(0xFF0000);
  final b = Frame(4, 2)..set(1, 1, 0x00FF00);
  return Creation(
    id: 'abc',
    title: 'My Cat!',
    kind: 'import',
    clip: FrameClip(width: 4, height: 2, frames: [a, b], delaysMs: [120, 80]),
    updatedAt: DateTime.utc(2026, 1, 2),
    meta: const {'source': {'name': 'cat.gif'}},
  );
}

void main() {
  test('.glyph round-trips a creation', () {
    final c = _creation();
    final text = encodeGlyphFile(c);
    final j = jsonDecode(text) as Map;
    expect(j['format'], 'glyph');
    expect(j['version'], glyphFileVersion);
    final back = parseGlyphFile(text);
    expect(back.title, c.title);
    expect(back.kind, 'import');
    expect(back.meta, c.meta);
    expect(back.clip.delaysMs, [120, 80]);
    expect(back.clip.frames[0].rgb, c.clip.frames[0].rgb);
    expect(back.clip.frames[1].get(1, 1), 0x00FF00);
  });

  test('.glyph rejects newer versions, junk and damaged frames', () {
    final c = _creation();
    final j = jsonDecode(encodeGlyphFile(c)) as Map<String, dynamic>;
    expect(() => parseGlyphFile(jsonEncode({...j, 'version': 99})),
        throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('newer'))));
    expect(() => parseGlyphFile('not json'), throwsFormatException);
    final broken = jsonDecode(encodeGlyphFile(c)) as Map<String, dynamic>;
    (broken['creation']['clip']['frames'] as List)[0] = base64Encode([1, 2, 3]);
    expect(() => parseGlyphFile(jsonEncode(broken)), throwsFormatException);
  });

  test('importGlyphFile saves under a new id', () async {
    final dir = await Directory.systemTemp.createTemp('glyph_share');
    addTearDown(() => dir.delete(recursive: true));
    final store = CreationsStore(directory: () async => dir);
    final saved = await importGlyphFile(store, utf8.encode(encodeGlyphFile(_creation())));
    expect(saved.id, isNot('abc'));
    expect(saved.title, 'My Cat!');
    expect(store.items.single.clip.frames.length, 2);
  });

  test('share GIF keeps per-frame delays and is upscaled', () async {
    final gif = encodeShareGif(_creation().clip);
    final src = decodeSource(gif);
    expect(src.frameCount, 2);
    expect(src.delaysMs, [120, 80]);
    expect(src.sourceWidth, 96); // 4 px × 24 (max scale)
    expect(src.sourceHeight, 48);
  });

  test('share files are written with slugged names', () async {
    final dir = await Directory.systemTemp.createTemp('glyph_share');
    addTearDown(() => dir.delete(recursive: true));
    final f = await writeCreationGlyph(_creation(), dir: dir);
    expect(f.path.endsWith('my-cat.glyph'), isTrue);
    expect(parseGlyphFile(await f.readAsString()).title, 'My Cat!');
    expect(fileSlug('***'), 'glyph');
  });
}
