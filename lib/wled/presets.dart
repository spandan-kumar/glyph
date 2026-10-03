/// Presets and device-side playlists as stored in /presets.json.
///
/// A preset is a saved state ("seg", "on", "bri", …), an HTTP API call
/// ("win") or a playlist (a "playlist" object). Format verified against
/// wled/WLED v16.0.1 wled00/presets.cpp (savePreset, doSaveState) and
/// wled00/playlist.cpp (loadPlaylist, serializePlaylist).
library;

enum PresetKind { state, playlist, api }

class WledPreset {
  const WledPreset({required this.id, required this.name, required this.body});

  final int id;
  final String name;

  /// The stored JSON, including "n".
  final Map<String, dynamic> body;

  PresetKind get kind => body['playlist'] is Map
      ? PresetKind.playlist
      : body.containsKey('win')
      ? PresetKind.api
      : PresetKind.state;

  bool get isPlaylist => kind == PresetKind.playlist;

  WledPlaylist? get playlist => body['playlist'] is Map
      ? WledPlaylist.fromJson((body['playlist'] as Map).cast<String, dynamic>())
      : null;

  /// Quick-load label ("ql"), shown by WLED as a button.
  String? get quickLabel => body['ql'] is String ? body['ql'] as String : null;

  /// A preset that only switches the light off (e.g. "WLED Turn Off").
  bool get turnsOff => body['on'] == false && segments.isEmpty;

  List<Map<String, dynamic>> get segments {
    final s = body['seg'];
    final list = s is List
        ? s
        : s is Map
        ? [s]
        : const [];
    return [
      for (final e in list)
        if (e is Map && (e['stop'] != 0 || e.length > 2)) e.cast<String, dynamic>(),
    ];
  }

  Map<String, dynamic>? get _mainSegment {
    final segs = segments;
    if (segs.isEmpty) return null;
    final main = body['mainseg'];
    return segs.firstWhere(
      (s) => s['id'] == main,
      orElse: () => segs.firstWhere((s) => s.containsKey('fx'), orElse: () => segs.first),
    );
  }

  /// GIF the Image effect plays: it reads the file named by the segment name
  /// (image_loader.cpp), e.g. "duck.gif" → /duck.gif.
  String? get gifName {
    for (final s in segments) {
      final n = s['n'];
      if (n is String && n.toLowerCase().endsWith('.gif')) return n;
    }
    return null;
  }

  int? get effectId {
    final fx = _mainSegment?['fx'];
    return fx is num ? fx.toInt() : null;
  }

  /// First colour of the main segment as 0xRRGGBB, when stored.
  int? get primaryColor {
    final col = _mainSegment?['col'];
    if (col is! List || col.isEmpty || col.first is! List) return null;
    final c = (col.first as List).whereType<num>().toList();
    if (c.length < 3) return null;
    return (c[0].toInt() & 0xFF) << 16 | (c[1].toInt() & 0xFF) << 8 | (c[2].toInt() & 0xFF);
  }

  /// Parses /presets.json, skipping the placeholder id 0 and empty slots.
  static List<WledPreset> parseAll(Object? json) {
    if (json is! Map) return const [];
    final out = <WledPreset>[];
    for (final MapEntry(:key, :value) in json.entries) {
      final id = int.tryParse('$key');
      if (id == null || id < 1 || id > 250 || value is! Map || value.isEmpty) {
        continue;
      }
      final body = value.cast<String, dynamic>();
      final n = body['n'];
      out.add(WledPreset(id: id, name: n is String && n.isNotEmpty ? displayName(n) : 'Preset $id', body: body));
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }
}

/// One step of a playlist. Durations and transitions are in tenths of a
/// second, as WLED stores them; a duration of 0 stays on that entry forever.
class PlaylistEntry {
  const PlaylistEntry({required this.presetId, this.durationDs = 100, this.transitionDs = 7});

  final int presetId;
  final int durationDs;
  final int transitionDs;

  Duration get duration => Duration(milliseconds: durationDs * 100);

  PlaylistEntry copyWith({int? presetId, int? durationDs, int? transitionDs}) => PlaylistEntry(
    presetId: presetId ?? this.presetId,
    durationDs: durationDs ?? this.durationDs,
    transitionDs: transitionDs ?? this.transitionDs,
  );

  @override
  bool operator ==(Object other) =>
      other is PlaylistEntry &&
      other.presetId == presetId &&
      other.durationDs == durationDs &&
      other.transitionDs == transitionDs;

  @override
  int get hashCode => Object.hash(presetId, durationDs, transitionDs);
}

/// `{"ps":[…], "dur":[…], "transition":[…], "repeat":n, "r":shuffle, "end":id}`.
class WledPlaylist {
  const WledPlaylist({
    required this.entries,
    this.repeat = 0,
    this.shuffle = false,
    this.endPreset = 0,
  });

  /// WLED loads at most 100 entries (playlist.cpp loadPlaylist).
  static const maxEntries = 100;

  /// `end` value that restores whatever was playing before the playlist.
  static const restorePrevious = 255;

  /// Upper bound of `dur` (tenths) before WLED clamps it.
  static const maxDurationDs = 42949670;

  final List<PlaylistEntry> entries;

  /// Times to play through; 0 loops forever.
  final int repeat;
  final bool shuffle;

  /// Preset applied when a finite playlist ends: 0 stays on the last entry,
  /// [restorePrevious] returns to the preset that was active before.
  final int endPreset;

  /// Total length of one pass, or null if an entry lasts forever.
  Duration? get passDuration {
    if (entries.any((e) => e.durationDs == 0)) return null;
    return Duration(milliseconds: entries.fold<int>(0, (s, e) => s + e.durationDs) * 100);
  }

  WledPlaylist copyWith({
    List<PlaylistEntry>? entries,
    int? repeat,
    bool? shuffle,
    int? endPreset,
  }) => WledPlaylist(
    entries: entries ?? this.entries,
    repeat: repeat ?? this.repeat,
    shuffle: shuffle ?? this.shuffle,
    endPreset: endPreset ?? this.endPreset,
  );

  /// Mirrors loadPlaylist: "dur"/"transition" may be arrays or a single
  /// number, and a short array repeats its last value. A negative "repeat"
  /// means "forever, shuffled".
  factory WledPlaylist.fromJson(Map<String, dynamic> j) {
    final ps = j['ps'];
    final ids = [
      for (final p in ps is List ? ps : const [])
        if (p is num) p.toInt(),
    ];
    final n = ids.length.clamp(0, maxEntries);
    List<int> expand(Object? v, int fallback) {
      final list = v is List
          ? [
              for (final e in v)
                if (e is num) e.toInt(),
            ]
          : <int>[];
      if (list.isEmpty) list.add(v is num ? v.toInt() : fallback);
      return [for (var i = 0; i < n; i++) i < list.length ? list[i] : list.last];
    }

    final dur = expand(j['dur'], 100);
    final tr = expand(j['transition'], 7);
    var repeat = j['repeat'] is num ? (j['repeat'] as num).toInt() : 0;
    var shuffle = j['r'] == true || (j['r'] is num && j['r'] != 0);
    if (repeat < 0) {
      repeat = 0;
      shuffle = true;
    }
    final end = j['end'] is num ? (j['end'] as num).toInt() : 0;
    return WledPlaylist(
      entries: [
        for (var i = 0; i < n; i++)
          PlaylistEntry(
            presetId: ids[i],
            durationDs: dur[i].clamp(0, maxDurationDs),
            transitionDs: tr[i].clamp(0, 65535),
          ),
      ],
      repeat: repeat.clamp(0, 127),
      shuffle: shuffle,
      endPreset: end == restorePrevious || (end >= 0 && end <= 250) ? end : 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'ps': [for (final e in entries) e.presetId],
    'dur': [for (final e in entries) e.durationDs.clamp(0, maxDurationDs)],
    'transition': [for (final e in entries) e.transitionDs.clamp(0, 65535)],
    'repeat': repeat.clamp(0, 127),
    'r': shuffle,
    'end': endPreset,
  };
}

/// Presets saved by other apps are often named after their file
/// ("pipplee.gif", "my_cat-2.gif"); show those as words ("Pipplee",
/// "My cat 2"). Names people typed are left alone.
String displayName(String raw) {
  final m = RegExp(r'^(.+)\.(gif|png|jpe?g|webp|bmp)$', caseSensitive: false).firstMatch(raw.trim());
  if (m == null) return raw;
  final words = m.group(1)!.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  if (words.isEmpty) return raw;
  return words[0].toUpperCase() + words.substring(1);
}
