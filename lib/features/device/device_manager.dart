import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/devices.dart';
import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../import/decode.dart';
import 'boot_intro.dart';
import '../../wled/presets.dart';
import '../../wled/schedule.dart';
import '../../wled/wled_client.dart';

/// What's stored on the selected matrix: presets, playlists, files and the
/// schedule. Requests run one after another because WLED's web server (and
/// the weak Wi‑Fi it often sits on) copes badly with bursts.
class DeviceManager extends ChangeNotifier {
  DeviceManager(this.store) {
    BootIntro.revision.addListener(_introChanged);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    BootIntro.revision.removeListener(_introChanged);
    super.dispose();
  }

  /// Requests can finish after the screen that owned this has gone.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// The intro was (re)installed or its end changed: read the device again.
  void _introChanged() {
    if (_host != null && store.isConnected) {
      _forgetAllPictures();
      scheduleMicrotask(load);
    }
  }

  final DeviceStore store;

  /// presets.json writes happen in the device loop after the request
  /// returns, so re-reads wait a moment.
  static const saveSettle = Duration(milliseconds: 700);

  String? _host;
  int _selection = -1;
  int _seenKept = 0;
  List<WledPreset> _presets = const [];
  Map<String, int> _files = const {};
  WledSchedule? _schedule;
  List<String> _effects = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  String? _scheduleError;
  bool _filesListed = false;
  final _thumbs = <String, Future<Uint8List>>{};
  final _clips = <String, Future<FrameClip?>>{};
  Future<void> _queue = Future.value();
  int _loadGen = 0;

  List<WledPreset> get presets => _presets;
  List<WledPreset> get playlists => [
    for (final p in _presets)
      if (p.isPlaylist) p,
  ];
  List<WledPreset> get playable => [
    for (final p in _presets)
      if (!p.isPlaylist) p,
  ];
  Map<String, int> get files => _files;

  /// The Glyph intro's presets on this device (see [BootIntro]).
  BootIntroLayout get bootIntro => BootIntroLayout.of(_presets, _schedule?.bootPreset ?? 0);

  /// System items (the intro and its Power-on playlist) the app hides and
  /// never deletes.
  bool isSystem(WledPreset p) => bootIntro.isSystem(p.id);

  bool isSystemFile(String path) => _key(path) == '/${BootIntro.fileName}';

  /// What plays at power-on (after the intro when it's installed); 0 for
  /// nothing / the Glyph logo.
  int get powerOnLook => bootIntro.powerOnLook;

  /// Whether [file] ("duck.gif" or "/duck.gif") is on the device.
  bool hasFile(String file) {
    final f = (file.startsWith('/') ? file : '/$file').toLowerCase();
    return _files.keys.any((k) => k.toLowerCase() == f);
  }

  /// A saved item whose animation file has been deleted from the device.
  /// False while the file list is unknown.
  bool isFileMissing(WledPreset p) {
    final gif = p.gifName;
    return gif != null && _filesListed && !hasFile(gif);
  }
  WledSchedule? get schedule => _schedule;
  bool get isLoading => _loading;
  bool get isLoaded => _loaded;
  String? get error => _error;
  String? get scheduleError => _scheduleError;

  WledClient? get _client => store.client;
  bool _current(WledClient c, int selection) =>
      !_disposed && store.isCurrent(c, selection);

  /// Reloads when the selected device changed since the last load. Safe to
  /// call from build: the load starts in a microtask.
  void syncHost() {
    final h = store.isConnected ? store.selected?.host : null;
    if (h == _host && _selection == store.selectionGeneration) {
      // Something new was kept elsewhere in the app (e.g. Tune's Keep).
      if (h != null && store.keptRevision != _seenKept) {
        _seenKept = store.keptRevision;
        // A file may have been sent again under the same name.
        _forgetAllPictures();
        scheduleMicrotask(reloadPresets);
      }
      return;
    }
    _seenKept = store.keptRevision;
    _selection = store.selectionGeneration;
    _host = h;
    _presets = const [];
    _files = const {};
    _filesListed = false;
    _schedule = null;
    _effects = const [];
    _forgetAllPictures();
    _loaded = false;
    _loading = false;
    _error = _scheduleError = null;
    if (h != null) scheduleMicrotask(load);
  }

  Future<void> load() async {
    final c = _client;
    if (c == null) return;
    final selection = store.selectionGeneration, request = ++_loadGen;
    bool current() => _current(c, selection) && request == _loadGen;
    _loading = true;
    notifyListeners();
    await _serial(() async {
      if (!current()) return;
      try {
        final presets = await c.presetList();
        if (!current()) return;
        _presets = presets;
        _error = null;
      } catch (e) {
        if (!current()) return;
        _error = 'Couldn\'t load presets: ${_msg(e)}';
      }
      try {
        final files = await c.files();
        if (!current()) return;
        _setFiles(files);
      } catch (_) {
        // Listing is optional; the Files tab shows what it has.
      }
      try {
        final schedule = await c.schedule();
        if (!current()) return;
        _schedule = schedule;
        _scheduleError = null;
      } catch (e) {
        if (!current()) return;
        _scheduleError = _msg(e);
      }
      if (_effects.isEmpty) {
        try {
          final effects = await c.effects();
          if (!current()) return;
          _effects = effects;
        } catch (_) {}
      }
    });
    if (!current()) return;
    _loading = false;
    _loaded = c == _client;
    notifyListeners();
  }

  Future<void> reloadPresets({bool settle = true}) async {
    final c = _client;
    if (c == null) return;
    final selection = store.selectionGeneration;
    if (settle) await Future<void>.delayed(saveSettle);
    await _serial(() async {
      if (!_current(c, selection)) return;
      final presets = await c.presetList();
      if (!_current(c, selection)) return;
      _presets = presets;
      try {
        final files = await c.files();
        if (!_current(c, selection)) return;
        _setFiles(files);
      } catch (_) {}
    });
    if (_current(c, selection)) notifyListeners();
  }

  WledPreset? preset(int id) {
    for (final p in _presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  String presetName(int id) => preset(id)?.name ?? 'Saved animation';

  String? effectName(int? id) =>
      id != null && id >= 0 && id < _effects.length ? _effects[id] : null;

  /// Presets whose Image effect plays [file] ("duck.gif" or "/duck.gif").
  List<WledPreset> presetsUsingFile(String file) {
    final f = (file.startsWith('/') ? file.substring(1) : file).toLowerCase();
    return [
      for (final p in _presets)
        if (p.gifName?.toLowerCase() == f) p,
    ];
  }

  List<WledPreset> playlistsUsing(int id) => [
    for (final p in playlists)
      if (p.playlist!.entries.any((e) => e.presetId == id)) p,
  ];

  List<WledTimer> timersUsing(int id) => [
    for (final t in _schedule?.timers ?? const <WledTimer>[])
      if (t.presetId == id) t,
  ];

  int? get freePresetId {
    final used = {for (final p in _presets) p.id};
    for (var id = 1; id <= 250; id++) {
      if (!used.contains(id)) return id;
    }
    return null;
  }

  /// The bytes of a GIF on the device, cached until the file changes.
  Future<Uint8List> gif(String name) {
    final path = name.startsWith('/') ? name : '/$name';
    final key = _key(name);
    final c = _client;
    if (c == null) return Future.error(StateError('Not connected'));
    return _thumbs[key] ??= _serial(() => c.fileBytes(path)).catchError((Object e) {
      _thumbs.remove(key);
      throw e;
    });
  }

  /// A GIF on the device decoded for previews, or null when it can't be
  /// read. Cached until the file is deleted or changes size; a failed read
  /// is retried next time. Each new decode is a new object, so previews can
  /// tell a replaced file from the old one.
  Future<FrameClip?> gifClip(String name) {
    final key = _key(name);
    return _clips[key] ??= () async {
      try {
        final src = await compute(decodeSourceMessage, await gif(name));
        return FrameClip(
          width: src.width,
          height: src.height,
          delaysMs: src.delaysMs,
          frames: [for (final f in src.frames) Frame(src.width, src.height)..rgb.setAll(0, f)],
        );
      } catch (_) {
        scheduleMicrotask(() => _clips.remove(key));
        return null;
      }
    }();
  }

  static String _key(String name) => (name.startsWith('/') ? name : '/$name').toLowerCase();

  void _forget(String path) {
    final key = _key(path);
    _thumbs.remove(key);
    _clips.remove(key);
  }

  void _forgetAllPictures() {
    _thumbs.clear();
    _clips.clear();
  }

  /// Takes a fresh file listing; pictures of files that went away or
  /// changed size are dropped from the caches.
  void _setFiles(Map<String, int> next) {
    final before = {for (final e in _files.entries) _key(e.key): e.value};
    final after = {for (final e in next.entries) _key(e.key): e.value};
    for (final MapEntry(:key, :value) in before.entries) {
      if (after[key] != value) _forget(key);
    }
    _files = next;
    _filesListed = true;
  }

  Future<void> apply(int id) => store.applyPreset(id);

  Future<void> rename(int id, String name) async {
    final c = _client, selection = store.selectionGeneration;
    if (c == null) return;
    await c.renamePreset(id, name);
    if (!_current(c, selection)) return;
    await reloadPresets(settle: false);
    if (!_current(c, selection)) return;
    await store.refreshState();
  }

  /// Deletes preset [id], and its GIF when [withFile] and no other preset
  /// uses it.
  Future<void> deletePreset(int id, {bool withFile = false}) async {
    final c = _client;
    if (c == null) return;
    final selection = store.selectionGeneration;
    if (bootIntro.isSystem(id)) {
      throw WledException('Your device needs this to start up');
    }
    final gif = preset(id)?.gifName;
    final wasPowerOnLook = bootIntro.installed && powerOnLook == id;
    await c.withPresetMutation(() async {
      if (!_current(c, selection)) return;
      await c.deletePreset(id);
      // Don't leave the intro handing over to a preset that's gone.
      if (wasPowerOnLook) await BootIntro.setPowerOnLook(c, 0);
      if (withFile &&
          gif != null &&
          presetsUsingFile(gif).every((p) => p.id == id)) {
        await c.deleteFile('/$gif');
        _forget(gif);
      }
    });
    if (!_current(c, selection)) return;
    await reloadPresets(settle: false);
    if (!_current(c, selection)) return;
    await store.refresh();
  }

  Future<void> deleteFile(String path) async {
    if (isSystemFile(path)) {
      throw WledException('Your device needs this to start up');
    }
    final c = _client, selection = store.selectionGeneration;
    if (c == null) return;
    await c.withPresetMutation(() async {
      if (_current(c, selection)) await c.deleteFile(path);
    });
    if (!_current(c, selection)) return;
    _forget(path);
    await reloadPresets(settle: false);
    if (!_current(c, selection)) return;
    await store.refresh();
  }

  /// Saves (and starts) a playlist; returns its preset id.
  Future<int> savePlaylist({
    int? id,
    required String name,
    required WledPlaylist playlist,
  }) async {
    final c = _client;
    if (c == null) throw WledException('Not connected');
    final selection = store.selectionGeneration;
    final pid = await c.withPresetMutation(() async {
      if (!_current(c, selection)) {
        throw WledException('Selected device changed');
      }
      final pid = id ?? await c.firstFreePresetId();
      await c.savePlaylist(id: pid, name: name, playlist: playlist);
      return pid;
    });
    if (!_current(c, selection)) return pid;
    await reloadPresets(settle: false);
    if (!_current(c, selection)) return pid;
    // The save already started it but without an id ("pl": 0); applying the
    // stored preset gives the running playlist its id.
    await store.applyPreset(pid);
    return pid;
  }

  Future<void> saveTimers(List<WledTimer> timers) async {
    final c = _client;
    if (c == null) return;
    final selection = store.selectionGeneration;
    await c.saveTimers(timers);
    if (!_current(c, selection)) return;
    await _reloadSchedule(c);
  }

  Future<void> setBootPreset(int id) async {
    final c = _client;
    if (c == null) return;
    final selection = store.selectionGeneration;
    if (bootIntro.installed) {
      // The intro stays first; the choice becomes what follows it.
      await BootIntro.setPowerOnLook(c, id);
      if (!_current(c, selection)) return;
      await reloadPresets(settle: false);
    } else {
      await c.setBootPreset(id);
    }
    if (!_current(c, selection)) return;
    await _reloadSchedule(c);
  }

  Future<void> _reloadSchedule(WledClient c) async {
    final selection = store.selectionGeneration;
    try {
      final schedule = await _serial(c.schedule);
      if (!_current(c, selection)) return;
      _schedule = schedule;
      _scheduleError = null;
    } catch (e) {
      if (!_current(c, selection)) return;
      _scheduleError = _msg(e);
    }
    notifyListeners();
  }

  Future<T> _serial<T>(Future<T> Function() task) {
    final next = _queue.then((_) => task());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  static String _msg(Object e) => e is WledException ? e.message : '$e';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  return kb < 1024
      ? '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB'
      : '${(kb / 1024).toStringAsFixed(1)} MB';
}

String formatTenths(int ds) {
  if (ds == 0) return 'forever';
  final s = ds / 10;
  if (s < 60) return '${s % 1 == 0 ? s.toInt() : s.toStringAsFixed(1)} s';
  final m = s ~/ 60, r = (s % 60).round();
  return r == 0 ? '$m min' : '$m min $r s';
}
