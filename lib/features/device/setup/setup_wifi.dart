import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of asking the phone to join a device's setup network.
sealed class SetupWifiResult {
  const SetupWifiResult();
}

final class SetupWifiConnected extends SetupWifiResult {
  const SetupWifiConnected(this.ssid);
  final String ssid;
}

/// The user dismissed the system dialog (Android may report this as [unavailable]).
final class SetupWifiCancelled extends SetupWifiResult {
  const SetupWifiCancelled();
}

/// Network not found, refused, or timed out (60 s).
final class SetupWifiUnavailable extends SetupWifiResult {
  const SetupWifiUnavailable();
}

/// Wi-Fi permission denied.
final class SetupWifiDenied extends SetupWifiResult {
  const SetupWifiDenied();
}

final class SetupWifiUnsupported extends SetupWifiResult {
  const SetupWifiUnsupported();
}

final class SetupWifiFailed extends SetupWifiResult {
  const SetupWifiFailed(this.code);
  final String code;
}

/// Joins a WLED setup access point. When not [assisted] the UI shows the
/// guided "open Wi-Fi settings" path instead.
abstract class SetupWifi {
  bool get assisted;
  Future<SetupWifiResult> connect({
    String? ssid,
    String prefix = 'WLED',
    String password = 'wled1234',
  });
  Future<void> release();
  Future<void> openSettings();

  /// Guided path: routes the app's traffic through the Wi-Fi network the
  /// person joined in Settings, which Android otherwise skips because it has
  /// no internet. [release] undoes it. False when there's nothing to bind.
  Future<bool> bindCurrentWifi() async => false;
}

typedef NearbyPermission = Future<bool> Function();

class PlatformSetupWifi extends SetupWifi {
  PlatformSetupWifi({int? sdk, NearbyPermission? requestNearby,
    NearbyPermission? requestLocation,
  }) : _requestNearby = requestNearby ?? _defaultRequest,
        _requestLocation = requestLocation ?? _defaultLocation {
    _sdk = sdk;
  }

  static const _channel = MethodChannel('glyph/setup_wifi');
  static const _platform = MethodChannel('glyph/platform');

  int? _sdk;
  final NearbyPermission _requestNearby, _requestLocation;

  static Future<bool> _defaultLocation() async =>
      (await Permission.locationWhenInUse.request()).isGranted;

  static Future<bool> _defaultRequest() async =>
      (await Permission.nearbyWifiDevices.request()).isGranted;

  /// Reads the Android API level; [assisted] is false until this has run.
  static Future<PlatformSetupWifi> detect() async {
    final w = PlatformSetupWifi();
    await w.probe();
    return w;
  }

  Future<void> probe() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final info = await _platform.invokeMapMethod<String, Object?>('phone');
      _sdk = info?['sdk'] as int?;
    } on PlatformException {
      _sdk = null;
    } on MissingPluginException {
      _sdk = null;
    }
  }

  @override
  bool get assisted => (_sdk ?? 0) >= 29;

  @override
  Future<SetupWifiResult> connect({
    String? ssid,
    String prefix = 'WLED',
    String password = 'wled1234',
  }) async {
    if (!assisted) return const SetupWifiUnsupported();
    if (!await (_sdk! >= 33 ? _requestNearby() : _requestLocation())) return const SetupWifiDenied();
    try {
      final got = await _channel.invokeMethod<String>('connect', {
        'ssid': ssid,
        'prefix': prefix,
        'password': password,
      });
      return SetupWifiConnected(got ?? ssid ?? prefix);
    } on PlatformException catch (e) {
      return switch (e.code) {
        'unavailable' => const SetupWifiUnavailable(),
        'cancelled' => const SetupWifiCancelled(),
        'denied' => const SetupWifiDenied(),
        'unsupported' => const SetupWifiUnsupported(),
        _ => SetupWifiFailed(e.code),
      };
    } on MissingPluginException {
      return const SetupWifiUnsupported();
    }
  }

  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } on PlatformException {
      // Nothing to release.
    } on MissingPluginException {
      // Not Android.
    }
  }

  @override
  Future<bool> bindCurrentWifi() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('bindWifi') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // The guided steps still tell the user where to go.
    } on MissingPluginException {
      // Not Android.
    }
  }
}
