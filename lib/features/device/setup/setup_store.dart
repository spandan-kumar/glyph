import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/devices.dart';
import '../../../wled/panel_setup.dart';
import '../../../wled/wled_client.dart';

/// What [SetupStore.restore] can put back.
enum SetupField { realtimeMaps, layout, ledCount, currentLimit, appLayout }

/// Outcome of an undo: what was put back, what could not be, and what was
/// already as it was.
class SetupRestoreResult {
  const SetupRestoreResult({
    this.restored = const {},
    this.failed = const {},
    this.unchanged = const {},
    this.hadSnapshot = true,
    this.verificationFailed = false,
    this.deviceMismatch = false,
    this.playbackFailed = false,
  });

  final Set<SetupField> restored;

  /// Field to a short reason (never contains credentials).
  final Map<SetupField, String> failed;
  final Set<SetupField> unchanged;

  /// False when there was nothing saved to restore.
  final bool hadSnapshot;

  final bool verificationFailed, deviceMismatch, playbackFailed;

  bool get ok => hadSnapshot && failed.isEmpty &&
      !verificationFailed && !deviceMismatch && !playbackFailed;

  @override
  String toString() =>
      'SetupRestoreResult(restored: $restored, failed: $failed, unchanged: $unchanged)';
}

/// Keeps the state of a device as it was before the wizard changed it, so
/// the change can be undone. One snapshot per device (by MAC) in
/// SharedPreferences; a new setup replaces the old snapshot.
class SetupStore {
  SetupStore({Future<void> Function(Duration)? delay})
      : _delay = delay ?? Future<void>.delayed;

  /// WLED rebuilds its LED outputs in its main loop after a count change.
  static const busSettle = Duration(milliseconds: 1500);

  final Future<void> Function(Duration) _delay;

  static String keyFor(String mac) => 'setup.snapshot.${mac.toLowerCase()}';

  Future<void> save(SetupSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyFor(snapshot.mac), snapshot.encode());
  }

  Future<SetupSnapshot?> load(String mac) async {
    if (mac.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyFor(mac));
    if (raw == null) return null;
    try {
      return SetupSnapshot.decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool> has(String mac) async => await load(mac) != null;

  Future<void> clear(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyFor(mac));
  }

  /// Puts the device back the way [snapshot] (default: the saved one for
  /// [mac]) found it, changing only what differs from the device's current
  /// state, in this order: streamed-pixel map, panel layout (or plain strip),
  /// LED count (the complete saved output entry), brightness limit; then the
  /// app's own layout for the device. Each write is checked by reading the
  /// device again. The saved snapshot is removed when everything worked.
  Future<SetupRestoreResult> restore(
    WledClient client,
    DeviceStore devices, {
    String? mac,
    SetupSnapshot? snapshot,
    bool clearOnSuccess = true,
  }) async {
    final snap = snapshot ?? await load(mac ?? '');
    if (snap == null) return const SetupRestoreResult(hadSnapshot: false);

    final restored = <SetupField>{}, unchanged = <SetupField>{};
    final failed = <SetupField, String>{};
    final wrote = <SetupField>{};

    Future<void> step(SetupField f, bool differs, Future<void> Function() write) async {
      if (!differs) {
        unchanged.add(f);
        return;
      }
      try {
        await write();
        wrote.add(f);
      } on WledException catch (e) {
        failed[f] = e.message;
      } catch (_) {
        failed[f] = 'Could not write to the device';
      }
    }

    DeviceSetupState now;
    try {
      now = await client.setupState();
    } on WledException catch (e) {
      return SetupRestoreResult(
        failed: {for (final f in SetupField.values) f: e.message},
      );
    }
    if (snap.mac.isEmpty || _mac(snap.mac) != _mac(now.mac)) {
      return const SetupRestoreResult(deviceMismatch: true);
    }
    if (now.pinLocked) {
      return SetupRestoreResult(failed: {
        for (final f in SetupField.values) f: 'The device settings are locked',
      });
    }

    await step(SetupField.realtimeMaps, now.realtimeMaps != snap.realtimeMaps,
        () => client.setRealtimeMaps(snap.realtimeMaps));

    final display = snap.display;
    final layoutDiffers = snap.isMatrix
        ? display != null && !_sameLayout(now, display)
        : now.isMatrix;
    await step(SetupField.layout, layoutDiffers,
        () => client.setPanelLayout(snap.isMatrix ? display : null));

    final countDiffers =
        snap.outputEntry.isNotEmpty && snap.ledCount != now.ledCount;
    await step(SetupField.ledCount, countDiffers, () async {
      await client.setLedCount(snap.ledCount, snap.outputEntry);
      await _delay(busSettle);
    });

    await step(
        SetupField.currentLimit,
        snap.currentLimitMa != null && snap.currentLimitMa != now.currentLimitMa,
        () => client.setCurrentLimit(snap.currentLimitMa!));

    var verificationFailed = false;

    if (wrote.isNotEmpty) {
      try {
        final after = await client.setupState();
        void verify(SetupField f, bool ok, String why) {
          if (wrote.contains(f) && !ok) {
            wrote.remove(f);
            failed[f] = why;
          }
        }

        verify(SetupField.realtimeMaps, after.realtimeMaps == snap.realtimeMaps,
            'The device kept its old setting');
        verify(
            SetupField.layout,
            snap.isMatrix
                ? display != null && _sameLayout(after, display)
                : !after.isMatrix,
            'The device kept its old layout');
        verify(SetupField.ledCount, after.ledCount == snap.ledCount,
            'The device kept its old LED count');
        verify(SetupField.currentLimit, after.currentLimitMa == snap.currentLimitMa,
            'The device kept its old limit');
      } catch (_) {
        verificationFailed = true;
        for (final f in wrote) {
          failed[f] = 'Could not verify the restored setting';
        }
        wrote.clear();
      }
    }
    restored.addAll(wrote);

    // Restore playback on retries too, even if the geometry already went back.
    var playbackFailed = false;
    final play = snap.playback;
    if (play != null) {
      try {
        await client.restoreSetupState(play);
      } catch (_) {
        playbackFailed = true;
      }
    }

    // The app's own layout (rotation/flip) for the device.
    final saved = devices.saved
        .where((d) => d.host == snap.host || (snap.mac.isNotEmpty && d.mac == snap.mac))
        .firstOrNull;
    if (saved != null && saved.layout != snap.appLayout) {
      try {
        await devices.updateSaved(saved.copyWith(layout: snap.appLayout));
        restored.add(SetupField.appLayout);
      } catch (_) {
        failed[SetupField.appLayout] = 'Could not update the app';
      }
    } else {
      unchanged.add(SetupField.appLayout);
    }

    final result = SetupRestoreResult(
        restored: restored, failed: failed, unchanged: unchanged,
        verificationFailed: verificationFailed, playbackFailed: playbackFailed);
    if (result.ok && clearOnSuccess) await clear(snap.mac);
    return result;
  }

  static bool _sameLayout(DeviceSetupState s, DisplaySetup d) =>
      s.isMatrix &&
      s.panelCount == 1 &&
      s.width == d.width &&
      s.height == d.height &&
      s.wiring == d.wiring;
}

String _mac(String m) => m.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
