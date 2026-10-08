import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/background.dart';
import '../../app/devices.dart';
import '../../app/playback.dart';
import '../../wled/ddp_group.dart';
import '../../wled/wled_client.dart';
import 'notification_logo.dart';
import 'notification_service.dart';
import 'notification_settings.dart';

/// Session-only monitoring. Preferences survive restart, listening never does.
class NotificationController extends ChangeNotifier {
  NotificationController({
    required this.devices,
    required this.playback,
    NotificationService? service,
    NotificationSettings? settings,
    Future<bool> Function(Object, VoidCallback)? retain,
    Future<void> Function(Object)? release,
    DateTime Function()? now,
    this.alertDuration = const Duration(seconds: 4),
  }) : service = service ?? NotificationService(),
       settings = settings ?? NotificationSettings(),
       _retain = retain ?? BackgroundStreaming.retain,
       _release = release ?? BackgroundStreaming.release,
       _now = now ?? DateTime.now {
    _observed = _state;
    devices.addListener(_changed);
    playback.addListener(_changed);
    this.service.addListener(_serviceChanged);
    _incoming = this.service.alerts.listen(_receive);
    _removed = this.service.removed.listen(
      (key) => _queue.removeWhere((a) => a.key == key),
    );
    BackgroundStreaming.watch(playback);
  }

  final DeviceStore devices;
  final PlaybackController playback;
  final NotificationService service;
  final NotificationSettings settings;
  final Future<bool> Function(Object, VoidCallback) _retain;
  final Future<void> Function(Object) _release;
  final DateTime Function() _now;
  final Duration alertDuration;
  late final StreamSubscription<LogoAlert> _incoming;
  late final StreamSubscription<String> _removed;
  final _queue = <LogoAlert>[];
  Timer? _timer;
  _AlertContext? _context;
  int _generation = 0;
  (int, int, int, int, int)? _observed;
  (int, int, int, int, int) get _state => (
    devices.selectionGeneration,
    devices.controlGeneration,
    playback.revision,
    playback.streamGeneration,
    playback.alertGeneration,
  );
  bool _busy = false, _disposed = false;
  bool monitoring = false, starting = false, loaded = false;
  Object? _monitorOwner;
  String? error;
  Future<void> _configuration = Future.value();
  Future<void> _handoff = Future.value();

  int get queued => _queue.length;
  bool get canShow =>
      devices.isConnected &&
      devices.isOn != false &&
      (devices.caps?.canStream ?? false) &&
      !playback.streamHeld &&
      !playback.alertsBlocked &&
      !playback.streamThrottled;

  Future<void> load() async {
    await settings.load();
    await service.refresh();
    if (_disposed) return;
    loaded = true;
    notifyListeners();
  }

  Future<void> setApp(String package, bool enabled) async {
    if (enabled) {
      settings.packages.add(package);
    } else {
      settings.packages.remove(package);
    }
    if (!enabled && _context?.package == package) _cancel();
    _queue.removeWhere((a) => !settings.packages.contains(a.package));
    notifyListeners();
    await settings.save();
    if (monitoring) {
      if (settings.packages.isEmpty) {
        await setMonitoring(false);
      } else {
        await _configure();
      }
    }
  }

  Future<void> setQuiet(bool enabled, {int? start, int? end}) async {
    settings.quiet = enabled;
    if (start != null) settings.quietStart = start.clamp(0, 1439);
    if (end != null) settings.quietEnd = end.clamp(0, 1439);
    if (settings.isQuiet(_now())) _cancel();
    notifyListeners();
    await settings.save();
  }

  Future<void> _configure() {
    // Serialize native allowlist changes so rapid toggles cannot re-enable an old choice.
    final packages = monitoring
        ? Set<String>.of(settings.packages)
        : <String>{};
    _configuration = _configuration.catchError((_) {}).then((_) async {
      if (!_disposed) await service.configure(packages);
    });
    return _configuration;
  }

  Future<void> setMonitoring(bool on) async {
    if (_disposed) return;
    if (!on) {
      final owner = _monitorOwner;
      _monitorOwner = null;
      _generation++;
      monitoring = starting = false;
      _cancel();
      notifyListeners();
      try {
        await _configure();
      } catch (_) {
        if (!_disposed) error = 'Couldn’t update Android notification access.';
      } finally {
        if (owner != null) await _release(owner);
      }
      return;
    }
    if (monitoring || starting) return;
    if (!loaded || settings.packages.isEmpty) {
      error = 'Choose at least one app first.';
      notifyListeners();
      return;
    }
    if (!service.supported ||
        !devices.isConnected ||
        !(devices.caps?.canStream ?? false)) {
      error = 'Connect a device that supports live playback.';
      notifyListeners();
      return;
    }
    starting = true;
    error = null;
    final generation = ++_generation;
    final owner = Object();
    _monitorOwner = owner;
    notifyListeners();
    try {
      await service.refresh();
      if (!service.access) {
        throw StateError(
          'Allow notification access in Android settings first.',
        );
      }
      if (_disposed || generation != _generation) return;
      final ok = await _retain(owner, () {
        if (identical(_monitorOwner, owner)) unawaited(setMonitoring(false));
      });
      if (_disposed || generation != _generation) {
        await _release(owner);
        return;
      }
      if (!ok) {
        throw StateError(
          'Couldn’t keep notification alerts running in the background.',
        );
      }
      monitoring = true;
      await _configure();
    } catch (e) {
      if (!_disposed && generation == _generation) {
        error = e is StateError
            ? e.message.toString()
            : 'Couldn’t start notification alerts.';
        monitoring = false;
        if (identical(_monitorOwner, owner)) _monitorOwner = null;
        await _configure().catchError((_) {});
        await _release(owner);
      }
    } finally {
      if (!_disposed && generation == _generation) {
        starting = false;
        notifyListeners();
      }
    }
  }

  void _serviceChanged() {
    if (_disposed) return;
    if (!service.connected) _cancel();
    if (monitoring && !service.access) {
      error = 'Notification access was turned off.';
      unawaited(setMonitoring(false));
    }
    notifyListeners();
  }

  void _changed() {
    if (_disposed) return;
    final changed = _observed != _state;
    _observed = _state;
    final c = _context;
    if (changed ||
        !canShow ||
        (c != null &&
            (!c.current(devices, playback) || !playback.isAlerting))) {
      _cancel();
    }
    notifyListeners();
  }

  bool _fresh(LogoAlert a) {
    final age = _now().difference(a.created);
    return !age.isNegative && age < const Duration(seconds: 30);
  }

  void _receive(LogoAlert a) {
    if (!monitoring ||
        !service.access ||
        !service.connected ||
        !canShow ||
        settings.isQuiet(_now()) ||
        !settings.packages.contains(a.package) ||
        !_fresh(a)) {
      return;
    }
    if (_context?.key == a.key || _context?.package == a.package) return;
    _queue.removeWhere(
      (old) => old.key == a.key || old.package == a.package || !_fresh(old),
    );
    if (_queue.length == 3) _queue.removeAt(0);
    _queue.add(a);
    unawaited(_drain());
  }

  /// "Test on device": plays [package]'s installed logo now for [alertDuration].
  /// Uses the normal alert path (device power/live-source checks, playback
  /// suppression, lor restore and `live:false` afterwards) but works without
  /// monitoring, never reads notifications and ignores quiet hours. Failures
  /// set [error]; a new user command cancels it like any alert.
  Future<void> preview(String package) async {
    if (!canShow) {
      error = 'Connect and turn on your device to preview.';
      notifyListeners();
      return;
    }
    final generation = _generation;
    final NotificationLogo logo;
    try {
      logo = await service.icon(package);
    } catch (_) {
      return;
    }
    if (_disposed || generation != _generation || !canShow) return;
    _cancel();
    _queue.add(LogoAlert(package, 'preview', _now(), logo));
    await _drain(preview: true);
  }

  Future<void> _drain({bool preview = false}) async {
    if (_busy || _context != null || _disposed || !canShow) return;
    if (!preview &&
        (!monitoring || settings.isQuiet(_now()) || !service.connected)) {
      return;
    }
    _queue.removeWhere(
      (a) => !_fresh(a) || (!preview && !settings.packages.contains(a.package)),
    );
    if (_queue.isEmpty) return;
    _busy = true;
    final a = _queue.removeAt(0), generation = _generation;
    final client = devices.client!;
    final info = devices.caps!;
    final c = _AlertContext(a, client, devices, playback);
    var prepared = false, began = false, shown = false;
    try {
      await _handoff;
      if (_disposed ||
          generation != _generation ||
          !c.current(devices, playback) ||
          !canShow) {
        return;
      }
      bool stale() =>
          _disposed ||
          generation != _generation ||
          !c.current(devices, playback) ||
          !canShow;
      // Leave native effects/preset/playlist state intact; only unlock realtime input.
      if (!playback.streamingHosts.contains(client.host)) {
        final state = await client.state();
        if (stale()) return;
        // Frames sent to an off device make WLED light up, and a live source
        // we don't own (e.g. Home Assistant) must not be hijacked.
        if (state['on'] == false) {
          if (preview) error = 'Turn your device on to preview.';
          return;
        }
        if (state['live'] == true) {
          if (preview) error = 'Something else is controlling your device.';
          return;
        }
        c.liveOverride = (state['lor'] as num?)?.toInt() ?? 0;
        prepared = true;
        await client.prepareStream();
        if (stale()) return;
      }
      final ok = await playback.beginAlert(
        NotificationLogoGenerator(a.logo),
        DdpTarget(client.host, layout: devices.selected!.layout),
        width: info.width,
        height: info.height,
      );
      began = ok;
      if (stale()) {
        playback.endAlert();
        return;
      }
      if (!ok) return;
      shown = true;
      _context = c;
      _timer = Timer(alertDuration, () {
        unawaited(_finish());
      });
      error = null;
      notifyListeners();
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = 'Couldn’t show the logo on your device.';
        notifyListeners();
      }
    } finally {
      if (prepared && !shown) {
        // prepareStream changed lor; put it back when no alert took over.
        await (began && _shouldRestore(c) ? c.restore() : c.restoreOverride())
            .catchError((_) {});
      }
      _busy = false;
      if (!_disposed && _context == null && _queue.isNotEmpty) {
        unawaited(_drain(preview: _queue.first.key == 'preview'));
      }
    }
  }

  Future<void> _finish() async {
    final c = _context;
    if (c == null) return;
    _context = null;
    _timer?.cancel();
    _timer = null;
    _busy = true;
    playback.endAlert();
    try {
      if (_shouldRestore(c)) await c.restore();
    } catch (_) {
      if (!_disposed) {
        error = 'Couldn’t confirm your device left the logo; it clears itself when live playback times out.';
      }
    } finally {
      _busy = false;
      if (!_disposed) {
        notifyListeners();
        if (_queue.isNotEmpty) {
          unawaited(_drain(preview: _queue.first.key == 'preview'));
        }
      }
    }
  }

  void _cancel() {
    if (_context != null || _busy || _queue.isNotEmpty) _generation++;
    _queue.clear();
    _timer?.cancel();
    _timer = null;
    final c = _context;
    _context = null;
    if (c != null) {
      playback.endAlert();
      if (_shouldRestore(c)) _handoff = c.restore().catchError((_) {});
    }
  }

  /// Leave live mode on the alert's device unless another stream owns it now.
  /// A user's own preset/Show command on the same device doesn't end realtime
  /// by itself, so it must not suppress this (else the logo lingers until the
  /// realtime timeout); a different device is left to WLED's own timeout.
  bool _shouldRestore(_AlertContext c) =>
      devices.client?.host == c.client.host &&
      devices.isOn != false &&
      !playback.streamHeld &&
      !playback.streamingHosts.contains(c.client.host);

  @override
  void dispose() {
    _disposed = true;
    devices.removeListener(_changed);
    playback.removeListener(_changed);
    service.removeListener(_serviceChanged);
    _cancel();
    _incoming.cancel();
    _removed.cancel();
    final owner = _monitorOwner;
    _monitorOwner = null;
    if (owner != null) unawaited(_release(owner));
    service.dispose();
    super.dispose();
  }
}

class _AlertContext {
  _AlertContext(
    LogoAlert alert,
    this.client,
    DeviceStore devices,
    PlaybackController playback,
  ) : key = alert.key,
      package = alert.package,
      selection = devices.selectionGeneration,
      control = devices.controlGeneration,
      revision = playback.revision,
      stream = playback.streamGeneration,
      alerts = playback.alertGeneration;
  final String key, package;
  final WledClient client;
  final int selection, control, revision, stream, alerts;
  int liveOverride = 0;
  // WLED clears lor 1 itself when realtime ends; only 2 (until reboot) needs restoring.
  Future<void> restore() =>
      client.setState({'live': false, if (liveOverride == 2) 'lor': 2});
  Future<void> restoreOverride() =>
      liveOverride == 2 ? client.setState({'lor': 2}) : Future.value();
  bool current(DeviceStore devices, PlaybackController playback) =>
      devices.isCurrent(client, selection) &&
      devices.controlGeneration == control &&
      playback.revision == revision &&
      playback.streamGeneration == stream &&
      playback.alertGeneration == alerts;
}
