import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../wled/ddp_group.dart';
import '../wled/device.dart';
import '../wled/layout.dart';
import '../wled/wled_client.dart';

typedef WledClientFactory = WledClient Function(String host);

/// Saved devices plus the live connection to the selected one: its info,
/// capabilities and power/brightness state, and which other saved matrices
/// mirror the live stream.
class DeviceStore extends ChangeNotifier {
  DeviceStore({WledClientFactory? clientFactory})
      : _factory = clientFactory ?? ((h) => WledClient(h));

  static const _prefsKey = 'devices.v1';
  static const _selectedKey = 'devices.selected';
  static const _mirrorsKey = 'devices.mirrors';

  /// Brightness writes are coalesced while a slider is dragged.
  static const brightnessDebounce = Duration(milliseconds: 150);

  final WledClientFactory _factory;

  List<SavedDevice> _saved = [];
  SavedDevice? _selected;
  WledClient? _client;
  WledInfo? _info;
  DeviceCapabilities? _caps;
  String? _error;
  bool _loading = false;

  bool? _on;
  int? _bri;
  int? _presetId;
  int? _playlistId;
  bool _playlistRunning = false;
  bool _nightlight = false;
  Timer? _briTimer;
  int _stateGen = 0;

  Set<String> _mirrorHosts = {};
  final _peerInfo = <String, WledInfo>{};
  final _peerOnline = <String, bool>{};
  final _peerClients = <String, WledClient>{};

  List<SavedDevice> get saved => List.unmodifiable(_saved);
  SavedDevice? get selected => _selected;
  WledClient? get client => _client;
  WledInfo? get info => _info;
  DeviceCapabilities? get caps => _caps;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isConnected => _info != null;

  /// Power from /json/state; null until read.
  bool? get isOn => _on;

  /// Master brightness 0–255 from /json/state (optimistic while dragging).
  int? get brightness => _bri;

  /// Active preset id, or null when none (WLED reports -1).
  int? get presetId => _presetId;

  /// Bumped whenever the app keeps something new on the matrix, so views
  /// that list kept items know to reload.
  int get keptRevision => _keptRevision;
  int _keptRevision = 0;

  /// Title of what the app last kept, while the matrix is still playing it.
  String? get keptTitle => _presetId != null && _presetId == _keptPresetId ? _keptTitle : null;

  /// The GIF the matrix is playing on its own (segment 0 on the Image
  /// effect), from its reported state; null when it shows anything else.
  String? get playingGif => _playingGif;
  String? _playingGif;

  /// Whether the matrix is playing [title] on its own as something Glyph
  /// kept. Survives app restarts because it's read from the matrix's state.
  bool isPlayingKept(String title) =>
      keptTitle == title || (_playingGif != null && _playingGif == keptFileName(title));
  String? _keptTitle;
  int? _keptPresetId;

  /// Records that [presetId] (titled [title]) was just kept and is now
  /// playing. WLED doesn't mark a freshly saved preset as current, so its
  /// state alone can't tell us.
  void noteKept(int presetId, String title) {
    _presetId = _keptPresetId = presetId;
    _keptTitle = title;
    _on = true;
    _keptRevision++;
    _stateGen++;
    notifyListeners();
  }

  /// Preset id of the running device playlist, if known.
  int? get playlistId => _playlistId;

  /// A device playlist is running. WLED reports "pl": 0 for one started by a
  /// save (no preset id yet) and -1 for none.
  bool get playlistRunning => _playlistRunning;
  bool get nightlightOn => _nightlight;

  /// Saved hosts (other than the selected one) that mirror the live stream.
  Set<String> get mirrorHosts =>
      Set.unmodifiable(_mirrorHosts.where((h) => h != _selected?.host));

  /// Last /json/info of another saved device, from [probeSaved].
  WledInfo? peerInfo(String host) =>
      host == _selected?.host ? _info : _peerInfo[host];

  /// Reachability of a saved device from the last probe; null if unknown.
  bool? isOnline(String host) =>
      host == _selected?.host ? (_info != null ? true : null) : _peerOnline[host];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        _saved = (jsonDecode(raw) as List)
            .map((e) => SavedDevice.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        _saved = [];
      }
    }
    _mirrorHosts = (prefs.getStringList(_mirrorsKey) ?? const []).toSet();
    final host = prefs.getString(_selectedKey);
    final match = _saved.where((d) => d.host == host);
    if (match.isNotEmpty) await select(match.first);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_saved.map((d) => d.toJson()).toList()));
    if (_selected != null) await prefs.setString(_selectedKey, _selected!.host);
    await prefs.setStringList(_mirrorsKey, _mirrorHosts.toList());
  }

  Future<void> addAndSelect(String host, String name) async {
    final existing = _saved.where((d) => d.host == host);
    final device = existing.isNotEmpty
        ? existing.first
        : SavedDevice(host: host, name: name, layout: const MatrixLayout());
    if (existing.isEmpty) _saved = [..._saved, device];
    await select(device);
  }

  Future<void> select(SavedDevice d) async {
    if (_selected?.host != d.host) {
      _briTimer?.cancel();
      _clearState();
      _info = null;
      _caps = null;
    }
    _selected = d;
    _client = _factory(d.host);
    await _persist();
    await refresh();
  }

  Future<void> remove(SavedDevice d) async {
    _saved = _saved.where((x) => x.host != d.host).toList();
    _mirrorHosts.remove(d.host);
    _peerInfo.remove(d.host);
    _peerOnline.remove(d.host);
    _peerClients.remove(d.host)?.close();
    if (_selected?.host == d.host) {
      _selected = null;
      _client = null;
      _info = null;
      _caps = null;
      _clearState();
    }
    await _persist();
    notifyListeners();
  }

  Future<void> updateLayout(MatrixLayout layout) async {
    final d = _selected;
    if (d == null) return;
    await updateSaved(d.copyWith(layout: layout));
  }

  /// Replaces the saved entry with the same host (name, layout, …).
  Future<void> updateSaved(SavedDevice updated) async {
    _saved = [for (final x in _saved) x.host == updated.host ? updated : x];
    if (_selected?.host == updated.host) _selected = updated;
    await _persist();
    notifyListeners();
  }

  /// Renames the selected matrix on the device itself and in the app.
  Future<void> renameOnDevice(String name) async {
    final c = _client, d = _selected;
    if (c == null || d == null) return;
    await c.setDeviceName(name);
    final n = name.trim();
    await updateSaved(d.copyWith(name: n.length > 32 ? n.substring(0, 32) : n));
    await refresh();
  }

  /// Re-reads /json/info, capabilities and /json/state.
  Future<void> refresh() async {
    final c = _client;
    if (c == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final info = await c.info();
      _caps = await c.capabilities();
      _info = info;
      // The name stored on the matrix is the one people set and recognise;
      // keep the saved entry in step with it (and the MAC, for re-finding).
      // The factory default "WLED" is less useful than the network name.
      final raw = info.name.trim();
      final name = raw.toUpperCase() == 'WLED' ? '' : raw;
      if (_selected != null &&
          ((info.mac.isNotEmpty && _selected!.mac != info.mac) || (name.isNotEmpty && _selected!.name != name))) {
        final updated = _selected!.copyWith(
          mac: info.mac.isNotEmpty ? info.mac : null,
          name: name.isNotEmpty ? name : null,
        );
        _saved = [for (final x in _saved) x.host == updated.host ? updated : x];
        _selected = updated;
        unawaited(_persist());
      }
      await _readState(c);
    } catch (e) {
      _info = null;
      _caps = null;
      _error = 'Can\'t reach ${_selected?.host}: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Re-reads power, brightness and the active preset.
  Future<void> refreshState() async {
    final c = _client;
    if (c == null) return;
    try {
      await _readState(c);
    } catch (_) {
      // Keep the last known values; the next action retries.
    }
    notifyListeners();
  }

  Future<void> _readState(WledClient c) async {
    final gen = ++_stateGen;
    final s = await c.state();
    // A write issued meanwhile wins over this (older) read.
    if (gen != _stateGen || c != _client) return;
    _applyState(s);
  }

  void _clearState() {
    _on = null;
    _bri = _presetId = _playlistId = null;
    _keptPresetId = null;
    _keptTitle = null;
    _playingGif = null;
    _playlistRunning = false;
    _nightlight = false;
  }

  void _applyState(Map<String, dynamic> s) {
    if (s['on'] is bool) _on = s['on'] as bool;
    if (s['bri'] is num && _briTimer == null) _bri = (s['bri'] as num).toInt();
    final ps = s['ps'], pl = s['pl'];
    // WLED reports no current preset after a fresh save (ps = -1), so keep
    // our record of what we kept until the matrix reports something else.
    _presetId = ps is num && ps > 0
        ? ps.toInt()
        : (_presetId != null && _presetId == _keptPresetId ? _presetId : null);
    _playlistId = pl is num && pl > 0 ? pl.toInt() : null;
    _playlistRunning = pl is num && pl >= 0;
    final nl = s['nl'];
    _nightlight = nl is Map && nl['on'] == true;
    final segs = s['seg'];
    final seg0 = segs is List && segs.isNotEmpty && segs.first is Map ? segs.first as Map : null;
    final fx = seg0?['fx'], n = seg0?['n'];
    _playingGif = fx is num && fx == _caps?.imageEffectId && n is String && n.isNotEmpty ? n : null;
  }

  Future<void> setPower(bool on) async {
    final c = _client;
    if (c == null) return;
    final before = _on;
    _on = on;
    _stateGen++;
    notifyListeners();
    try {
      await c.power(on);
    } catch (e) {
      _on = before;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> togglePower() => setPower(!(_on ?? true));

  /// Updates immediately and writes after [brightnessDebounce] of quiet, so
  /// it can be wired straight to a slider's onChanged.
  void setBrightness(int bri) {
    final c = _client;
    if (c == null) return;
    _bri = bri.clamp(0, 255);
    _stateGen++;
    notifyListeners();
    _briTimer?.cancel();
    _briTimer = Timer(brightnessDebounce, () async {
      _briTimer = null;
      final v = _bri;
      if (v == null) return;
      try {
        // Brightness 0 would switch WLED off; keep at least 1 while on.
        await c.setBrightness(v < 1 ? 1 : v);
      } catch (_) {
        // A dropped write is corrected by the next refresh.
      }
    });
  }

  /// Applies [id] and re-reads state.
  Future<void> applyPreset(int id) async {
    final c = _client;
    if (c == null) return;
    await c.applyPreset(id);
    _presetId = id;
    _on = true;
    _stateGen++;
    notifyListeners();
    // Presets load asynchronously on the device.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await refreshState();
  }

  Future<void> setNightlight(bool on, {int? minutes, int? mode, int? targetBri}) async {
    final c = _client;
    if (c == null) return;
    await c.setNightlight(on: on, minutes: minutes, mode: mode, targetBri: targetBri);
    _nightlight = on;
    if (on) _on = true;
    _stateGen++;
    notifyListeners();
  }

  // --- Mirroring ----------------------------------------------------------

  Future<void> setMirror(String host, bool enabled) async {
    if (enabled) {
      _mirrorHosts.add(host);
    } else {
      _mirrorHosts.remove(host);
    }
    await _persist();
    notifyListeners();
    if (enabled && !_peerInfo.containsKey(host)) await probeSaved(hosts: [host]);
  }

  /// Reads /json/info of other saved devices (all by default) for status,
  /// size and quick switching. Unreachable ones are marked offline.
  Future<void> probeSaved({Iterable<String>? hosts}) async {
    final targets = (hosts ?? _saved.map((d) => d.host))
        .where((h) => h != _selected?.host)
        .toList();
    await Future.wait(targets.map((h) async {
      try {
        _peerInfo[h] = await _peer(h).info();
        _peerOnline[h] = true;
      } catch (_) {
        _peerOnline[h] = false;
      }
    }));
    notifyListeners();
  }

  WledClient _peer(String host) => _peerClients[host] ??= _factory(host);

  /// DDP targets for the enabled mirrors, each at its own matrix size.
  /// Mirrors whose size is unknown are probed; unreachable ones are left out.
  Future<List<DdpTarget>> mirrorTargets() async {
    final hosts = mirrorHosts.where((h) => _saved.any((d) => d.host == h)).toList();
    final missing = hosts.where((h) => !_peerInfo.containsKey(h));
    if (missing.isNotEmpty) await probeSaved(hosts: missing);
    return [
      for (final h in hosts)
        if (_peerInfo[h] case final info?)
          DdpTarget(h,
              layout: _saved.firstWhere((d) => d.host == h).layout,
              width: info.hasMatrix ? info.matrixWidth : info.ledCount,
              height: info.hasMatrix ? info.matrixHeight : 1),
    ];
  }

  /// Clears a leftover realtime override on each mirror (see
  /// WledClient.prepareStream). Best effort.
  Future<void> prepareMirrors() => Future.wait([
        for (final h in mirrorHosts)
          _peer(h).prepareStream().catchError((Object _) {}),
      ]);

  /// Ends live mode on each mirror so it returns to its own effect at once.
  Future<void> exitLiveMirrors() => Future.wait([
        for (final h in mirrorHosts)
          _peer(h).exitLive().catchError((Object _) {}),
      ]);

  /// Ends live mode on one saved device, e.g. a mirror just removed.
  Future<void> exitLiveOn(String host) => _peer(host).exitLive();

  @override
  void dispose() {
    _briTimer?.cancel();
    for (final c in _peerClients.values) {
      c.close();
    }
    super.dispose();
  }
}

/// File name Glyph uses when it keeps [title] on a matrix ("Spooky Swirl"
/// → "spooky-swirl.gif"). LittleFS paths on WLED are short, so it's capped.
String keptFileName(String title) {
  var slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 24) slug = slug.substring(0, 24);
  return '$slug.gif';
}
