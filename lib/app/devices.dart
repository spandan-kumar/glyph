import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../wled/device.dart';
import '../wled/layout.dart';
import '../wled/wled_client.dart';

/// Saved devices plus the live connection to the selected one.
class DeviceStore extends ChangeNotifier {
  static const _prefsKey = 'devices.v1';
  static const _selectedKey = 'devices.selected';

  List<SavedDevice> _saved = [];
  SavedDevice? _selected;
  WledClient? _client;
  WledInfo? _info;
  DeviceCapabilities? _caps;
  String? _error;
  bool _loading = false;

  List<SavedDevice> get saved => List.unmodifiable(_saved);
  SavedDevice? get selected => _selected;
  WledClient? get client => _client;
  WledInfo? get info => _info;
  DeviceCapabilities? get caps => _caps;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isConnected => _info != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      _saved = (jsonDecode(raw) as List)
          .map((e) => SavedDevice.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
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
    _selected = d;
    _client = WledClient(d.host);
    await _persist();
    await refresh();
  }

  Future<void> remove(SavedDevice d) async {
    _saved = _saved.where((x) => x.host != d.host).toList();
    if (_selected?.host == d.host) {
      _selected = null;
      _client = null;
      _info = null;
      _caps = null;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> updateLayout(MatrixLayout layout) async {
    final d = _selected;
    if (d == null) return;
    final updated =
        SavedDevice(host: d.host, name: d.name, layout: layout, mac: d.mac);
    _saved = [for (final x in _saved) x.host == d.host ? updated : x];
    _selected = updated;
    await _persist();
    notifyListeners();
  }

  /// Re-reads /json/info and the effect list, then re-detects capabilities.
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
    } catch (e) {
      _info = null;
      _caps = null;
      _error = 'Can\'t reach ${_selected?.host}: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
