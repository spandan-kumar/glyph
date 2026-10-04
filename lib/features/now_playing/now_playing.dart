import 'dart:typed_data';

/// What's playing on the phone, as reported by its media session.
class NowPlaying {
  NowPlaying({
    required this.title,
    this.artist = '',
    this.album = '',
    this.app = '',
    this.durationMs = 0,
    this.positionMs = 0,
    DateTime? at,
    this.speed = 1,
    this.playing = true,
    this.art,
    this.artSize = 0,
  })  : at = at ?? DateTime.now(),
        artId = art == null ? 0 : _hash(art);

  /// From the Android bridge's event map; null when nothing is playing.
  static NowPlaying? fromMap(Map<Object?, Object?> m) {
    final title = m['title'] as String?;
    if (title == null || title.isEmpty) return null;
    final art = m['art'] as Uint8List?;
    final size = (m['artSize'] as num?)?.toInt() ?? 0;
    final ok = art != null && size > 0 && art.length == size * size * 3;
    return NowPlaying(
      title: title,
      artist: (m['artist'] as String?) ?? '',
      album: (m['album'] as String?) ?? '',
      app: _appLabel(m['app'] as String?),
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
      at: DateTime.fromMillisecondsSinceEpoch((m['atMs'] as num?)?.toInt() ?? 0),
      speed: (m['speed'] as num?)?.toDouble() ?? 1,
      playing: m['playing'] == true,
      art: ok ? art : null,
      artSize: ok ? size : 0,
    );
  }

  final String title, artist, album, app;

  /// Track length; 0 when the app doesn't say (live radio, some videos).
  final int durationMs;

  /// The position at [at]; it moves on at [speed] while [playing].
  final int positionMs;
  final DateTime at;
  final double speed;
  final bool playing;

  /// The cover as [artSize]² RGB, centre-cropped; null when there's none.
  final Uint8List? art;
  final int artSize;

  /// Cheap fingerprint of [art], so a re-sent cover isn't re-processed.
  final int artId;

  /// Same song (the cover or timing may still change).
  String get trackKey => '$app\u0000$title\u0000$artist';

  int positionAt(DateTime now) {
    var p = positionMs.toDouble();
    if (playing) p += now.difference(at).inMicroseconds / 1000 * speed;
    final max = durationMs > 0 ? durationMs.toDouble() : double.infinity;
    return p.clamp(0, max).round();
  }

  /// 0..1 through the track, or null when its length is unknown.
  double? progressAt(DateTime now) => durationMs <= 0 ? null : positionAt(now) / durationMs;

  static int _hash(Uint8List b) {
    var h = b.length;
    for (var i = 0; i < b.length; i += 7) {
      h = (h * 31 + b[i]) & 0x3FFFFFFF;
    }
    return h;
  }
}

/// The player's name; a bare package id ("com.spotify.music", when Android
/// wouldn't say) is no name at all.
String _appLabel(String? app) =>
    app == null || RegExp(r'^[a-z][\w]*(\.[\w]+)+$').hasMatch(app) ? '' : app;

/// Anything that knows what's playing: the phone's media sessions, or the
/// studio tile's demo.
abstract class NowPlayingFeed {
  NowPlaying? get current;
}

/// "3:07" style time.
String formatTrackTime(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
