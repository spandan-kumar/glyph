import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/creations.dart';
import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../../engine/gif_encoder.dart';

// Sharing creations as GIFs or `.glyph` files, and reading `.glyph` back.
// The functions without a BuildContext are the reusable API; the
// context-taking ones add the iPad popover anchor and error toasts.

/// Current `.glyph` file version. Readers accept this and anything older.
const glyphFileVersion = 1;
const glyphFileExtension = 'glyph';

/// Largest clip a `.glyph` file may hold, so a hostile file can't OOM us.
const _maxGlyphSide = 256, _maxGlyphFrames = 2000;

/// Serialises [c] as a versioned `.glyph` document.
String encodeGlyphFile(Creation c) => jsonEncode({
      'format': 'glyph',
      'version': glyphFileVersion,
      'creation': c.toJson(),
    });

/// Parses a `.glyph` document (or a bare `Creation.toJson`). Throws
/// [FormatException] with a user-readable message when it can't.
Creation parseGlyphFile(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const FormatException('This isn\'t a Glyph file.');
  }
  if (root is! Map) throw const FormatException('This isn\'t a Glyph file.');
  final Map body;
  if (root['format'] == 'glyph') {
    final v = root['version'];
    if (v is! int || v < 1) throw const FormatException('Unknown Glyph file version.');
    if (v > glyphFileVersion) {
      throw const FormatException('Made with a newer Glyph. Update the app to open it.');
    }
    final c = root['creation'];
    if (c is! Map) throw const FormatException('The Glyph file is empty.');
    body = c;
  } else {
    body = root;
  }
  try {
    final clip = body['clip'] as Map;
    final w = clip['w'] as int, h = clip['h'] as int;
    final frames = clip['frames'] as List, delays = clip['delays'] as List;
    if (w < 1 || h < 1 || w > _maxGlyphSide || h > _maxGlyphSide) {
      throw const FormatException('Unsupported size in the Glyph file.');
    }
    if (frames.isEmpty || frames.length > _maxGlyphFrames || frames.length != delays.length) {
      throw const FormatException('The Glyph file has a broken frame list.');
    }
    for (final f in frames) {
      if (base64Decode(f as String).length != w * h * 3) {
        throw const FormatException('The Glyph file has a damaged frame.');
      }
    }
    final json = Map<String, dynamic>.from(body);
    json['updatedAt'] ??= DateTime.now().toIso8601String();
    json['kind'] ??= 'import';
    json['title'] ??= 'Imported';
    json['id'] ??= 'imported';
    return Creation.fromJson(json);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('The Glyph file is damaged.');
  }
}

/// Parses [bytes] and adds the creation to [store] under a new id, so an
/// import never overwrites something already there.
Future<Creation> importGlyphFile(CreationsStore store, Uint8List bytes) async {
  final c = parseGlyphFile(utf8.decode(bytes, allowMalformed: true));
  return store.save(title: c.title, kind: c.kind, clip: c.clip, meta: c.meta);
}

/// Encodes [clip] as a looping GIF that keeps each frame's own delay,
/// upscaled with hard pixel edges so it isn't a speck in a chat app.
Uint8List encodeShareGif(FrameClip clip, {int targetSide = 320}) {
  final side = math.max(clip.width, clip.height);
  var k = (targetSide / side).floor().clamp(1, 24);
  // Keep the encoder's work (pixels × frames) sensible on long clips.
  while (k > 1 && clip.width * clip.height * k * k * clip.frames.length > 30000000) {
    k--;
  }
  final frames = k == 1 ? clip.frames : [for (final f in clip.frames) _upscale(f, k)];
  final cs = [for (final d in clip.delaysMs) math.max(2, (d / 10).round())];
  return encodeGif(frames, cs);
}

Frame _upscale(Frame f, int k) {
  final o = Frame(f.width * k, f.height * k);
  final ow = o.width;
  for (var y = 0; y < o.height; y++) {
    final sy = y ~/ k;
    for (var x = 0; x < ow; x++) {
      final si = (sy * f.width + x ~/ k) * 3, di = (y * ow + x) * 3;
      o.rgb[di] = f.rgb[si];
      o.rgb[di + 1] = f.rgb[si + 1];
      o.rgb[di + 2] = f.rgb[si + 2];
    }
  }
  return o;
}

Uint8List _encodeShareGifMessage(FrameClip clip) => encodeShareGif(clip);

/// Writes [c] as a GIF into [dir] (default: a temp share folder).
Future<File> writeCreationGif(Creation c, {Directory? dir}) async {
  final bytes = await compute(_encodeShareGifMessage, c.clip);
  return _write(dir, '${fileSlug(c.title)}.gif', bytes);
}

/// Writes [c] as a `.glyph` file into [dir] (default: a temp share folder).
Future<File> writeCreationGlyph(Creation c, {Directory? dir}) =>
    _write(dir, '${fileSlug(c.title)}.$glyphFileExtension', utf8.encode(encodeGlyphFile(c)));

Future<File> _write(Directory? dir, String name, List<int> bytes) async {
  final d = dir ?? await Directory('${(await getTemporaryDirectory()).path}/share')
      .create(recursive: true);
  return File('${d.path}/$name').writeAsBytes(bytes, flush: true);
}

/// Opens the system share sheet for [file]. [origin] anchors the iPad popover.
Future<ShareResult> shareFile(File file, String mimeType, {String? title, Rect? origin}) =>
    SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      title: title,
      subject: title,
      sharePositionOrigin: origin,
    ));

String fileSlug(String s) {
  final slug = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) return 'glyph';
  return slug.length > 40 ? slug.substring(0, 40) : slug;
}

// ---------------------------------------------------------------------------
// UI wrappers

Future<void> shareCreationAsGif(BuildContext context, Creation c) => _share(
    context, () => writeCreationGif(c), 'image/gif', c.title);

Future<void> shareCreationFile(BuildContext context, Creation c) => _share(
    context, () => writeCreationGlyph(c), 'application/json', c.title);

Future<void> _share(
    BuildContext context, Future<File> Function() write, String mime, String title) async {
  final origin = _originOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final file = await write();
    await shareFile(file, mime, title: title, origin: origin);
  } catch (e) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('Couldn\'t share: $e'), behavior: SnackBarBehavior.floating));
  }
}

Rect? _originOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize && box.size != Size.zero) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final size = MediaQuery.maybeSizeOf(context);
  // share_plus needs a non-empty rect on iPad.
  return size == null ? null : Rect.fromCenter(center: size.center(Offset.zero), width: 1, height: 1);
}
