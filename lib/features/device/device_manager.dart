import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/devices.dart';
import '../../wled/presets.dart';
import '../../wled/schedule.dart';
import '../../wled/wled_client.dart';

/// What's stored on the selected matrix: presets, playlists, files and the
/// schedule. Requests run one after another because WLED's web server (and
/// the weak Wi‑Fi it often sits on) copes badly with bursts.
class DeviceManager extends ChangeNotifier {
  DeviceManager(this.store);

  final DeviceStore store;

  /// presets.json writes happen in the device loop after the request
  /// returns, so re-reads wait a moment.
  static const saveSettle = Duration(milliseconds: 700);

  String? _host;
  List<WledPreset> _presets = const [];
  Map<String, int> _files = const {};
  WledSchedule? _schedule;
  List<String> _effects = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  String? _scheduleError;
  final _thumbs = <String, Future<Uint8List>>{};
  Future<void> _queue = Future.value();

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
  WledSchedule? get schedule => _schedule;
  bool get isLoading => _loading;
  bool get isLoaded => _loaded;
  String? get error => _error;
  String? get scheduleError => _scheduleError;

  WledClient? get _client => store.client;

  /// Reloads when the selected device changed since the last load. Safe to
  /// call from build: the load starts in a microtask.
  void syncHost() {
    final h = store.isConnected ? store.selected?.host : null;
    if (h == _host) return;
    _host = h;
    _presets = const [];
    _files = const {};
    _schedule = null;
    _effects = const [];
    _thumbs.clear();
    _loaded = false;
    _error = _scheduleError = null;
    if (h != null) scheduleMicrotask(load);
  }

  Future<void> load() async {
    final c = _client;
    if (c == null) return;
    _loading = true;
    notifyListeners();
    await _serial(() async {
      try {
        _presets = await c.presetList();
        _error = null;
      } catch (e) {
        _error = 'Couldn\'t load presets: ${_msg(e)}';
      }
      try {
        _files = await c.files();
      } catch (_) {
        // Listing is optional; the Files tab shows what it has.
      }
      try {
        _schedule = await c.schedule();
        _scheduleError = null;
      } catch (e) {
        _scheduleError = _msg(e);
      }
      if (_effects.isEmpty) {
        try {
          _effects = await c.effects();
        } catch (_) {}
      }
    });
    _loading = false;
    _loaded = c == _client;
    notifyListeners();
  }

  Future<void> reloadPresets({bool settle = true}) async {
    final c = _client;
    if (c == null) return;
    if (settle) await Future<void>.delayed(saveSettle);
    await _serial(() async {
      _presets = await c.presetList();
      try {
        _files = await c.files();
      } catch (_) {}
    });
    notifyListeners();
  }

  WledPreset? preset(int id) {
    for (final p in _presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  String presetName(int id) => preset(id)?.name ?? 'Preset $id';

  String? effectName(int? id) =>
      id != null && id >= 0 && id < _effects.length ? _effects[id] : null;

  /// One-line description: what the preset shows.
  String describe(WledPreset p) {
    switch (p.kind) {
      case PresetKind.playlist:
        final pl = p.playlist!;
        final n = pl.entries.length;
        return 'Playlist · $n preset${n == 1 ? '' : 's'}';
      case PresetKind.api:
        return 'API command';
      case PresetKind.state:
        if (p.turnsOff) return 'Turns the matrix off';
        final gif = p.gifName;
        if (gif != null) return 'GIF · $gif';
        final fx = effectName(p.effectId);
        return fx != null ? 'Effect · $fx' : 'Saved state';
    }
  }

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

  /// First frame/animation of a GIF on the device, cached per session.
  Future<Uint8List> gif(String name) {
    final key = name.startsWith('/') ? name : '/$name';
    final c = _client;
    if (c == null) return Future.error(StateError('Not connected'));
    return _thumbs[key] ??= _serial(() => c.fileBytes(key)).catchError((Object e) {
      _thumbs.remove(key);
      throw e;
    });
  }

  Future<void> apply(int id) => store.applyPreset(id);

  Future<void> rename(int id, String name) async {
    await _client?.renamePreset(id, name);
    await reloadPresets();
    await store.refreshState();
  }

  /// Deletes preset [id], and its GIF when [withFile] and no other preset
  /// uses it.
  Future<void> deletePreset(int id, {bool withFile = false}) async {
    final c = _client;
    if (c == null) return;
    final gif = preset(id)?.gifName;
    await c.deletePreset(id);
    if (withFile && gif != null && presetsUsingFile(gif).every((p) => p.id == id)) {
      await c.deleteFile('/$gif');
      _thumbs.remove('/$gif');
    }
    await reloadPresets(settle: false);
    await store.refresh();
  }

  Future<void> deleteFile(String path) async {
    await _client?.deleteFile(path);
    _thumbs.remove(path.startsWith('/') ? path : '/$path');
    await reloadPresets(settle: false);
    await store.refresh();
  }

  /// Saves (and starts) a playlist; returns its preset id.
  Future<int> savePlaylist({int? id, required String name, required WledPlaylist playlist}) async {
    final c = _client;
    if (c == null) throw WledException('Not connected');
    final pid = id ?? freePresetId;
    if (pid == null) throw WledException('All 250 preset slots are in use');
    await c.savePlaylist(id: pid, name: name, playlist: playlist);
    await reloadPresets();
    // The save already started it but without an id ("pl": 0); applying the
    // stored preset gives the running playlist its id.
    await store.applyPreset(pid);
    return pid;
  }

  Future<void> saveTimers(List<WledTimer> timers) async {
    final c = _client;
    if (c == null) return;
    await c.saveTimers(timers);
    await _reloadSchedule(c);
  }

  Future<void> setBootPreset(int id) async {
    final c = _client;
    if (c == null) return;
    await c.setBootPreset(id);
    await _reloadSchedule(c);
  }

  Future<void> _reloadSchedule(WledClient c) async {
    try {
      _schedule = await _serial(c.schedule);
      _scheduleError = null;
    } catch (e) {
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
