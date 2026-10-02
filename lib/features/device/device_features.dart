import 'dart:async';

import '../../app/devices.dart';
import '../../app/playback.dart';
import 'home_widget_bridge.dart';

/// App-wide wiring for matrix management. Call once from main() after the
/// stores exist: `DeviceFeatures.attach(devices: devices, playback: playback);`
///
/// * keeps the home-screen widget pointed at the selected matrix;
/// * keeps PlaybackController.mirrors in step with the mirror group, so every
///   startStreaming() also feeds the mirrored matrices.
abstract final class DeviceFeatures {
  static final _attached = Expando<_MirrorSync>();

  static void attach({required DeviceStore devices, required PlaybackController playback}) {
    HomeWidgetBridge.attach(devices);
    if (_attached[devices] != null) return;
    final sync = _attached[devices] = _MirrorSync(devices, playback);
    devices.addListener(sync.update);
    sync.update();
  }

  /// Recomputes the mirror targets now (e.g. right after toggling one).
  static Future<void> syncMirrors({
    required DeviceStore devices,
    required PlaybackController playback,
  }) => (_attached[devices] ?? _MirrorSync(devices, playback)).apply();
}

class _MirrorSync {
  _MirrorSync(this.devices, this.playback);

  final DeviceStore devices;
  final PlaybackController playback;
  String _key = '';

  /// Cheap check on every store notification; only resolves targets when the
  /// group, the primary or a mirror's layout changed.
  void update() {
    final layouts = {for (final d in devices.saved) d.host: d.layout};
    final hosts = devices.mirrorHosts.toList()..sort();
    final key = [
      devices.selected?.host,
      for (final h in hosts) '$h:${layouts[h]?.hashCode}:${devices.peerInfo(h)?.ledCount}',
    ].join('|');
    if (key == _key) return;
    _key = key;
    unawaited(apply());
  }

  Future<void> apply() async {
    try {
      final targets = await devices.mirrorTargets();
      if (targets.isNotEmpty) await devices.prepareMirrors();
      await playback.setMirrors(targets);
    } catch (_) {
      // Mirrors are best effort; the primary keeps streaming.
    }
  }
}
