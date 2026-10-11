import 'dart:convert';
import 'dart:io' show ZLibDecoder, ZLibEncoder;
import 'dart:typed_data';

import '../engine/clip.dart';
import '../engine/frame.dart';

/// A drawing shared with the community: the one format the app writes into a
/// GitHub issue and `tool/community_design.dart` reads back. Pure Dart.
///
/// Wire form: `glyph-design:1:` + base64url(zlib(utf8(json))), no padding.
/// The issue body is untrusted, so [decode] bounds every size before and
/// after inflating and validates every field.
class CommunityDesign {
  CommunityDesign({
    required this.title,
    required this.width,
    required this.height,
    required this.colors,
    required this.frames,
    required this.ms,
  });

  static const prefix = 'glyph-design:1:';
  static const maxSide = 64, maxPixels = 4096, maxFrames = 48, maxTitle = 40;
  static const minMs = 20, maxMs = 10000;

  /// Colour keys in order; `.` is transparent (black on the device).
  static const keys = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  static const maxEncoded = 60000, maxInflated = 400000;

  final String title;
  final int width, height;

  /// Key → `#RRGGBB`.
  final Map<String, String> colors;

  /// Per frame, [height] rows of [width] characters.
  final List<List<String>> frames;
  final List<int> ms;

  /// Converts an editor clip. Black is transparent; more colours than [keys]
  /// are merged by dropping low bits until they fit.
  static CommunityDesign fromClip(FrameClip clip, {required String title}) {
    final t = cleanTitle(title);
    if (t.isEmpty) throw const CommunityDesignException('Give it a name.');
    if (clip.width > maxSide || clip.height > maxSide || clip.width * clip.height > maxPixels) {
      throw const CommunityDesignException('This drawing is too big to share.');
    }
    if (clip.frames.length > maxFrames) {
      throw const CommunityDesignException('Shared drawings can have up to $maxFrames frames.');
    }
    for (var drop = 0; drop <= 7; drop++) {
      final mask = (0xFF << drop) & 0xFF;
      final index = <int, String>{};
      final frames = <List<String>>[];
      var fits = true;
      for (final f in clip.frames) {
        final rows = <String>[];
        for (var y = 0; y < f.height && fits; y++) {
          final row = StringBuffer();
          for (var x = 0; x < f.width; x++) {
            final i = (y * f.width + x) * 3;
            var c = (f.rgb[i] & mask) << 16 | (f.rgb[i + 1] & mask) << 8 | (f.rgb[i + 2] & mask);
            // A dim pixel merged down to black stays lit, at the dimmest grey.
            if (c == 0 && (f.rgb[i] | f.rgb[i + 1] | f.rgb[i + 2]) != 0) c = (1 << drop) * 0x010101;
            if (c == 0) {
              row.write('.');
              continue;
            }
            final key = index[c] ??= index.length < keys.length ? keys[index.length] : '';
            if (key.isEmpty) {
              fits = false;
              break;
            }
            row.write(key);
          }
          rows.add(row.toString());
        }
        if (!fits) break;
        frames.add(rows);
      }
      if (!fits) continue;
      return CommunityDesign(
        title: t,
        width: clip.width,
        height: clip.height,
        colors: {for (final e in index.entries) e.value: _hex(e.key)},
        frames: frames,
        ms: [for (final d in clip.delaysMs) d.clamp(minMs, maxMs)],
      );
    }
    throw const CommunityDesignException('This drawing has too many colours to share.');
  }

  static String cleanTitle(String s) {
    final t = s.replaceAll(RegExp(r'[\x00-\x1F\x7F<>`\[\]\\]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > maxTitle ? t.substring(0, maxTitle).trim() : t;
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'title': title,
    'w': width,
    'h': height,
    'colors': colors,
    'frames': frames,
    'ms': ms,
  };

  String encode() {
    final packed = ZLibEncoder(level: 9).convert(utf8.encode(jsonEncode(toJson())));
    return prefix + base64Url.encode(packed).replaceAll('=', '');
  }

  /// Finds and decodes the first design token in [text] (an issue body).
  static CommunityDesign decode(String text) {
    final at = text.indexOf(prefix);
    if (at < 0) throw const CommunityDesignException('No design found.');
    final token = RegExp(r'[A-Za-z0-9_-]*').matchAsPrefix(text, at + prefix.length)![0]!;
    if (token.isEmpty || token.length > maxEncoded) {
      throw const CommunityDesignException('The design is empty or too large.');
    }
    final Uint8List packed;
    try {
      packed = base64Url.decode(base64Url.normalize(token));
    } on FormatException {
      throw const CommunityDesignException('The design text is damaged.');
    }
    return fromJson(jsonDecode(utf8.decode(_inflate(packed))));
  }

  static List<int> _inflate(List<int> packed) {
    final out = BytesBuilder(copy: false);
    final inflater = ZLibDecoder().startChunkedConversion(_Capped(out));
    try {
      inflater
        ..add(packed)
        ..close();
    } on CommunityDesignException {
      rethrow;
    } catch (_) {
      throw const CommunityDesignException('The design text is damaged.');
    }
    return out.takeBytes();
  }

  static CommunityDesign fromJson(Object? json) {
    Never bad(String why) => throw CommunityDesignException('Invalid design: $why.');
    if (json is! Map) bad('not an object');
    if (json['v'] != 1) bad('unknown version');
    final title = json['title'], w = json['w'], h = json['h'];
    if (title is! String || cleanTitle(title) != title || title.isEmpty) bad('title');
    if (w is! int || h is! int || w < 1 || h < 1 || w > maxSide || h > maxSide || w * h > maxPixels) bad('size');
    final rawColors = json['colors'];
    if (rawColors is! Map || rawColors.length > keys.length) bad('colours');
    final colors = <String, String>{};
    for (final e in rawColors.entries) {
      final k = e.key, v = e.value;
      if (k is! String || k.length != 1 || !keys.contains(k)) bad('colour key');
      if (v is! String || !RegExp(r'^#[0-9A-F]{6}$').hasMatch(v)) bad('colour value');
      colors[k] = v;
    }
    final rawFrames = json['frames'], rawMs = json['ms'];
    if (rawFrames is! List || rawFrames.isEmpty || rawFrames.length > maxFrames) bad('frame count');
    if (rawMs is! List || rawMs.length != rawFrames.length) bad('timing');
    final frames = <List<String>>[];
    for (final f in rawFrames) {
      if (f is! List || f.length != h) bad('frame height');
      final rows = <String>[];
      for (final r in f) {
        if (r is! String || r.length != w) bad('frame width');
        for (final ch in r.split('')) {
          if (ch != '.' && !colors.containsKey(ch)) bad('unknown colour "$ch"');
        }
        rows.add(r);
      }
      frames.add(rows);
    }
    final ms = <int>[];
    for (final m in rawMs) {
      if (m is! int || m < minMs || m > maxMs) bad('frame time');
      ms.add(m);
    }
    return CommunityDesign(title: title, width: w, height: h, colors: colors, frames: frames, ms: ms);
  }

  /// Back to frames, for previews (app sheet, issue GIF).
  FrameClip toClip() {
    final rgb = {for (final e in colors.entries) e.key: int.parse(e.value.substring(1), radix: 16)};
    Frame draw(List<String> rows) {
      final f = Frame(width, height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          if (rgb[rows[y][x]] case final c?) f.set(x, y, c);
        }
      }
      return f;
    }

    return FrameClip(width: width, height: height, frames: [for (final rows in frames) draw(rows)], delaysMs: List.of(ms));
  }

  /// A sprite entry for `assets/catalog/sprites/community.json`.
  Map<String, dynamic> toSprite({required String id, required String creator, required String url}) => {
    'id': id,
    'title': title,
    'tags': {'community', ...title.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 1)}.toList(),
    'colors': colors,
    'ms': ms.toSet().length == 1 ? ms.first : ms,
    'frames': frames,
    'source': {
      'work': title,
      'year': DateTime.now().toUtc().year,
      'creator': creator,
      'basis': 'Original drawing made in Glyph and shared by its creator.',
      'jurisdiction': 'worldwide',
      'notice': 'By $creator · CC0',
      'license': 'CC0-1.0',
      'url': url,
      'licenseUrl': 'https://creativecommons.org/publicdomain/zero/1.0/',
    },
  };

  static String _hex(int c) => '#${c.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class CommunityDesignException implements Exception {
  const CommunityDesignException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Collects inflated bytes, failing past [CommunityDesign.maxInflated] so a
/// zip bomb can't exhaust memory.
class _Capped implements Sink<List<int>> {
  _Capped(this._out);
  final BytesBuilder _out;

  @override
  void add(List<int> chunk) {
    if (_out.length + chunk.length > CommunityDesign.maxInflated) {
      throw const CommunityDesignException('The design is too large.');
    }
    _out.add(chunk);
  }

  @override
  void close() {}
}
