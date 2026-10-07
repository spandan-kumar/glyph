import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'device.dart';
import 'presets.dart';
import 'schedule.dart';

class _PresetMutation {
  _PresetMutation(this.host);
  final String host;
  bool active = true;
}

class WledException implements Exception {
  WledException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'WledException: $message';
}

/// WLED JSON/HTTP API. Endpoints verified against wled/WLED v16.0.1 and
/// v0.14.4 sources (wled00/wled_server.cpp, json.cpp, presets.cpp).
class WledClient {
  WledClient(this.host, {http.Client? client})
      : _http = client ?? http.Client(),
        _base = Uri.parse('http://${_authority(host)}');

  static const timeout = Duration(seconds: 4);
  static const uploadTimeout = Duration(seconds: 40);
  static const presetSaveSettle = Duration(milliseconds: 700);
  static final _presetQueues = <String, Future<void>>{};
  static final _mutationKey = Object();

  /// Longest GIF file name (without the leading slash) accepted by
  /// [gifSegmentName]: ESP8266 builds cap segment names at 32 chars
  /// (WLED_MAX_SEGNAME_LEN in const.h) and LittleFS paths stay short.
  static const maxGifNameLength = 31;

  final String host;
  final http.Client _http;
  final Uri _base;
  final _createdGifs = <String>{};

  /// Boot rewrites and JSON preset saves must share a queue, even when two
  /// clients address the same host. Nested calls retain the operation's lock.
  Future<T> withPresetMutation<T>(Future<T> Function() operation) {
    final key = host.toLowerCase();
    final held = Zone.current[_mutationKey];
    if (held is _PresetMutation && held.host == key && held.active) {
      return operation();
    }
    final next = (_presetQueues[key] ?? Future<void>.value()).then((_) {
      final lease = _PresetMutation(key);
      return runZoned(() async {
        try {
          return await operation();
        } finally {
          lease.active = false;
        }
      }, zoneValues: {_mutationKey: lease});
    });
    final settled = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _presetQueues[key] = settled;
    settled.then((_) {
      if (identical(_presetQueues[key], settled)) _presetQueues.remove(key);
    });
    return next;
  }

  Future<WledInfo> info() async => WledInfo.fromJson(await _getMap('/json/info'));

  Future<Map<String, dynamic>> state() => _getMap('/json/state');

  /// Effect names; the list index is the effect id.
  Future<List<String>> effects() async {
    final j = await _get('/json/eff');
    if (j is! List) throw WledException('Unexpected /json/eff response');
    return [for (final e in j) '$e'];
  }

  Future<DeviceCapabilities> capabilities() async {
    final i = await info();
    final fx = await effects();
    final live = await liveConfig();
    return DeviceCapabilities.detect(i, fx, realtimeEnabled: live?.enabled);
  }

  /// Realtime settings from /cfg.json `if.live`: whether UDP realtime is
  /// received at all, its timeout and whether LED maps apply ("rlm"). Null
  /// when the config cannot be read (e.g. settings PIN).
  Future<({bool enabled, Duration timeout, bool respectsLedMaps})?>
      liveConfig() async {
    try {
      final live = _mapOf(_mapOf((await _getMap('/cfg.json'))['if'])['live']);
      if (live.isEmpty) return null;
      final t = live['timeout'];
      return (
        enabled: live['en'] != false,
        timeout: Duration(milliseconds: (t is num ? t.toInt() : 25) * 100),
        respectsLedMaps: live['rlm'] == true,
      );
    } on WledException {
      return null;
    }
  }

  /// Colour gamma settings from /json/cfg (`light.gc`, `if.live."no-gc"`),
  /// which decide whether streamed frames need gamma applied by the app.
  /// Null when the config cannot be read.
  Future<LedColorConfig?> ledColorConfig() async {
    try {
      final cfg = await config();
      if (cfg['light'] is! Map && cfg['if'] is! Map) return null;
      return LedColorConfig.fromConfig(cfg);
    } on WledException {
      return null;
    }
  }

  Future<void> setState(Map<String, dynamic> s) {
    if (s.containsKey('psave') || s.containsKey('pdel')) {
      return withPresetMutation(() async {
        await _setState(s);
        // The HTTP response precedes the device-loop filesystem write.
        await Future<void>.delayed(presetSaveSettle);
      });
    }
    return _setState(s);
  }

  Future<void> _setState(Map<String, dynamic> s) async {
    final res = await _send(() => _http.post(_uri('/json/state'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(s)));
    _check(res, '/json/state');
  }

  Future<void> setBrightness(int bri) => setState({'bri': bri.clamp(0, 255)});

  Future<void> power(bool on) => setState({'on': on});

  /// `"live": false` calls exitRealtime(), which zeroes the realtime timeout
  /// and restores the effect immediately (json.cpp deserializeState, udp.cpp
  /// exitRealtime). Stop sending DDP first, or the next packet re-enters live.
  Future<void> exitLive() => setState({'live': false});

  /// Clears a realtime override ("lor") set from the WLED UI; while it is
  /// non-zero WLED ignores incoming DDP pixels (e131.cpp handleDDPPacket).
  Future<void> prepareStream() => setState({'lor': 0});

  /// Multipart POST to /upload. WLED ignores the field name and uses the
  /// part's filename as the path, prepending "/" if missing
  /// (wled_server.cpp handleUpload). Returns 401 when the settings PIN is
  /// locked. Never upload cfg.json: that triggers a reboot.
  Future<void> uploadFile(String path, Uint8List bytes) async {
    final name = path.startsWith('/') ? path : '/$path';
    final req = http.MultipartRequest('POST', _uri('/upload'))
      ..files.add(http.MultipartFile.fromBytes('data', bytes, filename: name));
    final res = await _send(() async {
      final streamed = await _http.send(req);
      return http.Response.fromStream(streamed);
    }, uploadTimeout);
    if (res.statusCode == 401) {
      throw WledException('Device is PIN-locked; unlock settings to upload');
    }
    _check(res, '/upload');
  }

  /// Root files as path → size in bytes. Uses `/edit?list=/`, which both the
  /// v16 handler and the older SPIFFSEditor understand.
  Future<Map<String, int>> files() async {
    final j = await _get('/edit?list=/');
    if (j is! List) return const {};
    return {
      for (final f in j.whereType<Map>())
        if (f['type'] != 'dir' && f['name'] is String)
          _slash(f['name'] as String): (f['size'] as num?)?.toInt() ?? 0,
    };
  }

  /// Deletes a file. v16 uses `GET /edit?func=delete&path=` (wled_server.cpp
  /// createEditHandler); 0.14/0.15 use SPIFFSEditor's `DELETE /edit` with a
  /// form field `path`. A GIF that segment 0 is playing is released first.
  Future<void> deleteFile(String path) async {
    final p = _slash(path);
    await _releaseFile(p.substring(1));
    final res = await _send(() => _http.get(_uri('/edit')
        .replace(queryParameters: {'func': 'delete', 'path': p})));
    if (res.statusCode == 200 && res.body.contains('deleted')) return;
    final legacy = await _send(() async {
      final req = http.Request('DELETE', _uri('/edit'))
        ..bodyFields = {'path': p};
      return http.Response.fromStream(await _http.send(req));
    });
    _check(legacy, '/edit');
  }

  /// Preset id → name, skipping the placeholder id 0 and empty slots.
  Future<Map<int, String>> presets() async {
    Object? j;
    try {
      j = await _get('/presets.json');
    } on WledException catch (e) {
      if (e.cause == 404) return {}; // no presets file yet
      rethrow;
    }
    if (j is! Map) return {};
    final out = <int, String>{};
    for (final MapEntry(:key, :value) in j.entries) {
      final id = int.tryParse('$key');
      if (id == null || id == 0 || value is! Map || value.isEmpty) continue;
      out[id] = value['n'] is String ? value['n'] as String : 'Preset $id';
    }
    return out;
  }

  Future<int> firstFreePresetId() async {
    final used = await presets();
    for (var id = 1; id <= 250; id++) {
      if (!used.containsKey(id)) return id;
    }
    throw WledException('All 250 preset slots are in use');
  }

  Future<void> deletePreset(int id) => setState({'pdel': id});

  /// Applies preset [id]. WLED ignores `{"ps": id}` when id is already the
  /// current preset even if the state has since changed (json.cpp
  /// `presetCycCurr != currentPreset`), so in that case the stored preset
  /// body is posted directly.
  Future<void> applyPreset(int id) async {
    if ((await state())['ps'] != id) return setState({'ps': id});
    final body = _mapOf((await _getMap('/presets.json'))['$id']);
    if (body.isEmpty || body.containsKey('playlist') || body.containsKey('win')) {
      return setState({'ps': id});
    }
    await setState({...body, 'pd': id}..remove('n')..remove('ql'));
  }

  /// Plays a GIF already on the device's filesystem on segment 0.
  ///
  /// The Image effect reads the file named by the segment name: it prepends
  /// "/" itself and only accepts names ending in ".gif"
  /// (image_loader.cpp renderImageToSegment), so `n` is "anim.gif", not
  /// "/anim.gif". It reloads only when the name changes. sx 128 is normal
  /// speed; ix is blur, so it is zeroed.
  Future<void> playGif(String fileName, {required int imageEffectId}) =>
      setState({
        'on': true,
        'seg': {
          'id': 0,
          'fx': imageEffectId,
          'n': gifSegmentName(fileName),
          'sx': 128,
          'ix': 0,
          'frz': false,
        },
      });

  /// Saves the current state as preset [id] (first free slot by default).
  /// Without an "o" key WLED snapshots the live state; "ib" includes
  /// brightness, "sb" segment bounds. The write happens asynchronously in the
  /// device loop (presets.cpp savePreset). Names are capped at 32 chars.
  Future<int> saveCurrentAsPreset(String name, {int? id}) => withPresetMutation(
    () async {
      final pid = id ?? await firstFreePresetId();
      if (pid < 1 || pid > 250) throw WledException('Preset id must be 1..250');
      await setState({
        'psave': pid,
        'n': name.length > 32 ? name.substring(0, 32) : name,
        'ib': true,
        'sb': true,
      });
      return pid;
    },
  );

  /// Uploads [gif], plays it on segment 0 and saves that as a preset.
  /// Returns the preset id.
  Future<int> saveGifToDevice({
    required String fileName,
    required Uint8List gif,
    required String presetName,
    required DeviceCapabilities caps,
    int? presetId,
    Future<void> Function()? beforeSwitch,
    void Function(int attempt)? onRetry,
    bool Function()? canSwitch,
  }) => withPresetMutation(() async {
    final fx = caps.imageEffectId;
    if (!caps.canPlayGifs || fx == null) {
      throw WledException(
        'This device cannot play GIFs (needs WLED 16+ on an ESP32-family chip)',
      );
    }
    final baseName = gifSegmentName(fileName);
    final listing = await files();
    final presets = await presetList();
    final previous = presets
        .where((p) => p.id == presetId)
        .firstOrNull
        ?.gifName;
    final segments = (await state())['seg'];
    final used = {
      for (final path in listing.keys) path.substring(1).toLowerCase(),
      for (final p in presets)
        if (p.gifName != null) p.gifName!.toLowerCase(),
      if (segments is List)
        for (final s in segments.whereType<Map>())
          if (s['n'] is String) (s['n'] as String).toLowerCase(),
    };
    var name = baseName;
    if (used.contains(name.toLowerCase())) {
      final stem = baseName.substring(0, baseName.length - 4);
      for (var revision = 0; revision < 256; revision++) {
        final suffix = revision.toRadixString(16).padLeft(2, '0');
        final candidate =
            '${stem.substring(0, min(stem.length, 24))}-$suffix.gif';
        if (!used.contains(candidate.toLowerCase())) {
          name = candidate;
          break;
        }
      }
      if (name == baseName) {
        throw WledException(
          'Remove unused versions of this animation before sending again',
        );
      }
    }
    if (!caps.fitsFile(gif.length)) {
      final freeKb =
          (caps.freeFsBytes - DeviceCapabilities.fsSafetyMarginBytes) ~/ 1024;
      throw WledException(
        'GIF is ${(gif.length / 1024).ceil()} KB but the device has only '
        '${freeKb < 0 ? 0 : freeKb} KB free',
      );
    }
    final pid = presetId ?? await firstFreePresetId();
    if (canSwitch != null && !canSwitch()) {
      throw WledException('Send cancelled: playback changed');
    }
    var committed = false;
    try {
      // Never overwrite a file the device or a Saved look still uses.
      await uploadFileReliably('/$name', gif, onRetry: onRetry);
      _createdGifs.add(name);
      if (canSwitch != null && !canSwitch()) {
        throw WledException('Send cancelled: playback changed');
      }
      committed = true;
      await playGif(name, imageEffectId: fx);
      await beforeSwitch?.call();
      await exitLive();
      try {
        await saveCurrentAsPreset(presetName, id: pid);
      } on WledException {
        // A lost HTTP reply can follow a successful asynchronous device write.
        // The staged filename is unique, so an older Saved entry cannot match.
        await Future<void>.delayed(presetSaveSettle);
        WledPreset? saved;
        try {
          saved = (await presetList()).where((p) => p.id == pid).firstOrNull;
        } on WledException {
          // Keep the original failure when the write cannot be confirmed.
        }
        final label = presetName.length > 32 ? presetName.substring(0, 32) : presetName;
        if (saved?.name != label || saved?.gifName != name ||
            saved?.effectId != fx || saved?.body['on'] != true) {
          rethrow;
        }
      }
      // Only retire files this client created, and never shared content.
      if (previous != null && _createdGifs.contains(previous)) {
        try {
          final saved = await presetList();
          final segs = (await state())['seg'];
          final playing =
              segs is List &&
              segs.whereType<Map>().any((s) => s['n'] == previous);
          if (!playing && saved.every((p) => p.gifName != previous)) {
            await deleteFile('/$previous');
            _createdGifs.remove(previous);
          }
        } catch (_) {}
      }
      return pid;
    } catch (_) {
      if (!committed) {
        try {
          await deleteFile('/$name');
          _createdGifs.remove(name);
        } catch (_) {}
      }
      rethrow;
    }
  });

  /// Replacement files retain enough of the original name for catalog
  /// matching after restarting the app.
  static bool matchesGifName(String baseName, String fileName) {
    final base = (baseName.startsWith('/') ? baseName.substring(1) : baseName).toLowerCase();
    if (base.length <= 4 || !base.endsWith('.gif')) return false;
    final file = fileName.toLowerCase();
    if (base == file) return true;
    final stem = base.substring(0, base.length - 4);
    final prefix = '${stem.substring(0, min(stem.length, 24))}-';
    return file.startsWith(prefix) &&
        RegExp(r'^[0-9a-f]{2}\.gif$').hasMatch(file.substring(prefix.length));
  }

  /// Uploads [bytes] to [path] and checks the stored size, retrying up to
  /// [attempts] times. Weak Wi-Fi often drops an ESP32 off the network for
  /// tens of seconds mid-upload, so between attempts we wait (up to ~30 s)
  /// for it to answer again.
  Future<void> uploadFileReliably(String path, Uint8List bytes,
      {int attempts = 3, void Function(int attempt)? onRetry}) async {
    final p = _slash(path);
    WledException? last;
    for (var a = 1; a <= attempts; a++) {
      if (a > 1) {
        onRetry?.call(a);
        await _waitUntilReachable(const Duration(seconds: 30));
      }
      try {
        await uploadFile(p, bytes);
        final stored = (await files())[p];
        // Older firmware lists without sizes; trust the 200 then.
        if (stored == null || stored == bytes.length || stored == 0) return;
        last = WledException('Saved file is ${stored}B, expected ${bytes.length}B');
      } on WledException catch (e) {
        last = e;
      }
    }
    throw WledException(
        'Your matrix kept dropping off Wi-Fi while saving. Move it closer to the router and try again.',
        last);
  }

  Future<void> _waitUntilReachable(Duration limit) async {
    final until = DateTime.now().add(limit);
    while (DateTime.now().isBefore(until)) {
      try {
        await _send(() => _http.get(_uri('/json/info')), const Duration(seconds: 3));
        return;
      } on WledException {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// If segment 0 is showing [name], switch its effect to Solid so the GIF
  /// decoder closes the file (segment reset → endImagePlayback, FX_fcn.cpp
  /// resetIfRequired). Needed before deleting the file (LittleFS refuses
  /// while it is open: "Delete failed", observed on 16.0.1) or re-uploading
  /// it (the decoder only reloads when the segment name changes).
  Future<void> _releaseFile(String name) async {
    final segs = (await state())['seg'];
    final seg0 = segs is List && segs.isNotEmpty ? segs.first : null;
    if (seg0 is Map && seg0['n'] == name) {
      await setState({
        'tt': 0,
        'seg': {'id': 0, 'fx': 0}
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Validates and normalises a GIF file name to the segment-name form the
  /// Image effect expects (no leading slash, lowercase ".gif" suffix).
  static String gifSegmentName(String fileName) {
    var n = fileName.startsWith('/') ? fileName.substring(1) : fileName;
    if (n.toLowerCase().endsWith('.gif') && !n.endsWith('.gif')) {
      n = '${n.substring(0, n.length - 4)}.gif';
    }
    if (!n.endsWith('.gif') || n.length <= 4) {
      throw WledException('GIF file name must end in .gif: $fileName');
    }
    if (n.length > maxGifNameLength || n.contains('/')) {
      throw WledException(
          'GIF file name must be at most $maxGifNameLength chars with no folders: $fileName');
    }
    return n;
  }

  /// Live device config (GET /json/cfg serializes the running config, so it
  /// is current right after a POST, unlike the /cfg.json file which is
  /// written later in the device loop).
  Future<Map<String, dynamic>> config() => _getMap('/json/cfg');

  /// Partial config update via POST /json/cfg. Only keys present are changed
  /// (cfg.cpp deserializeConfig uses `x = json | x` throughout) and the
  /// config is then saved to flash; nothing reboots unless "rb" is sent.
  /// Returns 401 when a settings PIN is set and not unlocked.
  Future<void> setConfig(Map<String, dynamic> patch) async {
    final res = await _send(() => _http.post(_uri('/json/cfg'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(patch)));
    if (res.statusCode == 401) {
      throw WledException('WLED firmware settings are PIN-locked; unlock them in WLED first', 401);
    }
    _check(res, '/json/cfg');
  }

  /// Renames the device itself (cfg id.name, the "server description" shown
  /// in the WLED UI and /json/info "name"; at most 32 chars).
  Future<void> setDeviceName(String name) {
    final n = name.trim();
    if (n.isEmpty) throw WledException('Name can\'t be empty');
    return setConfig({
      'id': {'name': n.length > 32 ? n.substring(0, 32) : n}
    });
  }

  Future<WledSchedule> schedule() async => WledSchedule.fromConfig(await config());

  /// Replaces every timer (an empty list removes them all).
  Future<void> saveTimers(List<WledTimer> timers) {
    if (timers.length > WledSchedule.maxTimers) {
      throw WledException('At most ${WledSchedule.maxTimers} schedules');
    }
    for (final t in timers) {
      final err = t.validate();
      if (err != null) throw WledException(err);
    }
    return setConfig(WledSchedule.timersPatch(timers));
  }

  /// Preset applied at power-on; 0 for none.
  Future<void> setBootPreset(int presetId) =>
      setConfig(WledSchedule.bootPresetPatch(presetId));

  /// Every stored preset with its JSON body, sorted by id.
  Future<List<WledPreset>> presetList() async {
    try {
      return WledPreset.parseAll(await _get('/presets.json'));
    } on WledException catch (e) {
      if (e.cause == 404) return const [];
      rethrow;
    }
  }

  /// Saves a playlist preset the way the WLED UI does (index.js saveP):
  /// `"o": true` with a "playlist" object makes savePreset store the
  /// playlist rather than a state snapshot. WLED loads (starts) the playlist
  /// as part of the same request and writes it in the next loop iteration.
  Future<void> savePlaylist(
      {required int id, required String name, required WledPlaylist playlist}) {
    if (id < 1 || id > 250) throw WledException('Preset id must be 1..250');
    if (playlist.entries.isEmpty) throw WledException('Add at least one preset');
    if (playlist.entries.length > WledPlaylist.maxEntries) {
      throw WledException('At most ${WledPlaylist.maxEntries} entries');
    }
    if (playlist.entries.any((e) => e.presetId == id)) {
      throw WledException('A playlist can\'t contain itself');
    }
    final n = name.trim().isEmpty ? 'Playlist $id' : name.trim();
    return setState({
      'psave': id,
      'n': n.length > 32 ? n.substring(0, 32) : n,
      'playlist': playlist.toJson(),
      'on': true,
      'o': true,
    });
  }

  /// Renames preset [id] keeping its content. State and API presets are
  /// re-saved as an API call (`"o": true`), which savePreset writes verbatim
  /// minus o/v/time/error/psave; WLED also applies the body, so the preset
  /// starts playing. Playlists are re-saved (and so restarted).
  Future<void> renamePreset(int id, String name) =>
      withPresetMutation(() async {
        final n = name.trim();
        if (n.isEmpty) throw WledException('Name can\'t be empty');
        final body = _mapOf((await _getMap('/presets.json'))['$id']);
        if (body.isEmpty) throw WledException('Preset $id no longer exists');
        final preset = WledPreset(id: id, name: n, body: body);
        final pl = preset.playlist;
        if (pl != null) return savePlaylist(id: id, name: n, playlist: pl);
        await setState({
          ...Map<String, dynamic>.of(body)
            ..remove('psave')
            ..remove('pdel')
            ..remove('rb')
            ..remove('np'),
          'psave': id,
          'n': n.length > 32 ? n.substring(0, 32) : n,
          'o': true,
        });
      });

  /// Advances a running device playlist (json.cpp "np").
  Future<void> nextInPlaylist() => setState({'np': true});

  /// Nightlight (json.cpp "nl", led.cpp handleNightlight): mode 1 fades
  /// brightness to [targetBri] over [minutes], 0 waits then jumps to it, 2
  /// also fades to the secondary colour. Fading from off does nothing. Mode 3
  /// runs the Sunrise effect instead (a sunrise when off, a sunset when on,
  /// at most 60 min) and ignores [targetBri].
  Future<void> setNightlight(
          {required bool on, int? minutes, int? mode, int? targetBri}) =>
      setState({
        'nl': {
          'on': on,
          if (minutes != null) 'dur': minutes.clamp(1, 255),
          if (mode != null) 'mode': mode.clamp(0, 3),
          if (targetBri != null) 'tbri': targetBri.clamp(0, 255),
        }
      });

  /// Raw bytes of a file on the device filesystem (e.g. "/duck.gif"); WLED
  /// serves FS files at their path. Retried once.
  Future<Uint8List> fileBytes(String path) async {
    final p = _slash(path);
    http.Response? res;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        res = await _send(() => _http.get(_uri(Uri.encodeFull(p))), uploadTimeout);
        break;
      } on WledException {
        if (attempt == 1) rethrow;
      }
    }
    _check(res!, p);
    return res.bodyBytes;
  }

  void close() => _http.close();

  Uri _uri(String path) => _base.resolve(path);

  Future<Map<String, dynamic>> _getMap(String path) async {
    final j = await _get(path);
    if (j is! Map) throw WledException('Unexpected $path response');
    return j.cast<String, dynamic>();
  }

  /// GETs are retried once: weak Wi‑Fi drops the odd request.
  Future<Object?> _get(String path) async {
    http.Response? res;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        res = await _send(() => _http.get(_uri(path)));
        break;
      } on WledException {
        if (attempt == 1) rethrow;
      }
    }
    final r = res!;
    _check(r, path);
    try {
      return jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    } on FormatException catch (e) {
      throw WledException('Invalid JSON from $path', e);
    }
  }

  Future<http.Response> _send(Future<http.Response> Function() request,
      [Duration limit = timeout]) async {
    try {
      return await request().timeout(limit);
    } on TimeoutException catch (e) {
      throw WledException('$host did not respond in ${limit.inSeconds}s', e);
    } on http.ClientException catch (e) {
      throw WledException('Cannot reach $host: ${e.message}', e);
    } on Exception catch (e) {
      // SocketException and friends (dart:io is not imported to keep this
      // usable everywhere package:http is).
      throw WledException('Cannot reach $host: $e', e);
    }
  }

  void _check(http.Response res, String path) {
    if (res.statusCode == 200) return;
    throw WledException(
        '$path returned HTTP ${res.statusCode}', res.statusCode);
  }

  static String _slash(String p) => p.startsWith('/') ? p : '/$p';

  static Map<String, dynamic> _mapOf(Object? v) =>
      v is Map ? v.cast<String, dynamic>() : const {};

  static String _authority(String host) =>
      ':'.allMatches(host).length > 1 && !host.startsWith('[')
          ? '[$host]'
          : host;
}
