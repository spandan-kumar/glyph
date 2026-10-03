import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'devices.dart';

/// A storage milestone worth telling the user about.
enum StorageLevel { ok, half, nearlyFull }

/// Watches the selected device's storage and reports each time it crosses
/// 50 % or 90 % full — once per crossing, remembered per device, so the user
/// isn't nagged on every refresh. Dropping back below a level (after a
/// clean-up) re-arms it.
class StorageAlerts {
  StorageAlerts(this._devices, {required this.onAlert}) {
    _devices.addListener(_check);
    _check();
  }

  final DeviceStore _devices;
  final void Function(StorageLevel level, int percent) onAlert;
  bool _checking = false;

  static String _key(String host) => 'storage.alerted.$host';

  static StorageLevel levelFor(double used) => used >= 0.9
      ? StorageLevel.nearlyFull
      : used >= 0.5
          ? StorageLevel.half
          : StorageLevel.ok;

  Future<void> _check() async {
    final info = _devices.info, host = _devices.selected?.host;
    final used = info?.fsUsedKb, total = info?.fsTotalKb;
    if (_checking || host == null || used == null || total == null || total <= 0) return;
    _checking = true;
    try {
      final ratio = used / total;
      final level = levelFor(ratio);
      final prefs = await SharedPreferences.getInstance();
      final last = StorageLevel.values[(prefs.getInt(_key(host)) ?? 0).clamp(0, 2)];
      if (level.index > last.index) onAlert(level, (ratio * 100).round());
      if (level != last) await prefs.setInt(_key(host), level.index);
    } finally {
      _checking = false;
    }
  }

  @mustCallSuper
  void dispose() => _devices.removeListener(_check);
}
