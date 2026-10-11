import 'dart:async';

import '../../app/devices.dart';
import '../../app/playback.dart';
import 'boot_intro.dart';
import 'home_widget_bridge.dart';

/// App-wide wiring for matrix management. Call once from main() after the
/// stores exist: `DeviceFeatures.attach(devices: devices, playback: playback);`
///
/// * keeps the home-screen widget pointed at the selected matrix;
/// * keeps PlaybackController.mirrors in step with the mirror group, so every
///   startStreaming() also feeds the mirrored matrices;
/// * installs the Glyph intro as the boot screen of each device it connects
///   to (see [BootIntro]), quietly in the background.
abstract final class DeviceFeatures {
  static final _attached = Expando<_MirrorSync>();

  static void attach({required DeviceStore devices, required PlaybackController playback}) {
    HomeWidgetBridge.attach(devices);
    if (_attached[devices] != null) return;
    final sync = _attached[devices] = _MirrorSync(devices, playback);
    devices.addListener(sync.update);
    sync.update();
    final intro = _BootIntroSync(devices);
    devices.addListener(intro.update);
    intro.update();
    final power = _PowerSync(devices, playback);
    devices.addListener(power.update);
    power.update();
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

/// Holds the live stream while the device is switched off (from the app, the
/// widget or a refresh that finds it off) and lets it flow again when it's
/// back on. Without this a running look — Now Playing, a visualiser — keeps
/// streaming, and WLED turns itself back on the next time live frames resume.
class _PowerSync {
  _PowerSync(this.devices, this.playback);

  final DeviceStore devices;
  final PlaybackController playback;

  void update() {
    final off = devices.isConnected && devices.isOn == false;
    if (off == playback.streamHeld) return;
    playback.streamHeld = off;
    // Leave live mode now rather than after WLED's timeout.
    if (off && playback.isStreaming) unawaited(devices.client?.exitLive().catchError((Object _) {}));
  }
}

/// Runs [BootIntro.ensure] once per device and size each session, when the
/// store is connected. A failure is retried a minute later at the earliest.
class _BootIntroSync {
  _BootIntroSync(this.devices);

  final DeviceStore devices;
  final _done = <String>{};
  final _failedAt = <String, DateTime>{};
  bool _busy = false;

  void update() {
    if (!BootIntro.autoInstall || _busy || !devices.isConnected) return;
    final host = devices.selected?.host, caps = devices.caps, client = devices.client;
    if (host == null || caps == null || client == null || !caps.canPlayGifs) return;
    final key = '$host ${caps.width}x${caps.height}';
    if (_done.contains(key)) return;
    final failed = _failedAt[key];
    if (failed != null && DateTime.now().difference(failed) < const Duration(minutes: 1)) return;
    _busy = true;
    unawaited(() async {
      try {
        if (await BootIntro.ensure(client, caps)) BootIntro.revision.value++;
        _done.add(key);
        _failedAt.remove(key);
      } catch (_) {
        _failedAt[key] = DateTime.now();
      } finally {
        _busy = false;
      }
    }());
  }
}
