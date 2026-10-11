import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../app/community.dart';
import '../../wled/timezone.dart';
import '../../wled/wled_client.dart';

/// The phone's timezone: IANA id (Android only) and current UTC offset.
typedef PhoneZone = ({String? iana, Duration offset});

const _platform = MethodChannel('glyph/platform');

Future<PhoneZone> _readPhoneZone() async {
  String? iana;
  // Only Android reports the IANA id; elsewhere the offset alone is used.
  if (Platform.isAndroid) {
    try {
      final m = await _platform.invokeMapMethod<String, Object?>('phone');
      final tz = m?['tz'];
      if (tz is String && tz.isNotEmpty) iana = tz;
    } catch (_) {}
  }
  return (iana: iana, offset: DateTime.now().timeZoneOffset);
}

/// Replaced in tests.
Future<PhoneZone> Function() phoneZoneReader = _readPhoneZone;

/// Makes the device know the time without anyone opening firmware settings:
/// turns on internet time with the phone's timezone (unless it was already on,
/// which keeps the owner's own choice) and always sets the clock from the phone
/// so it is right before the first sync and with no internet. Newly enabled
/// NTP takes over after the device next restarts or reconnects. Never throws;
/// returns false when something failed.
Future<bool> ensureDeviceTime(
  WledClient client, {
  PhoneZone? phone,
  DateTime? now,
}) async {
  var ok = true;
  try {
    final cfg = await client.config();
    final ntp = ((cfg['if'] as Map?)?['ntp']) as Map?;
    if (ntp?['en'] != true) {
      final z = phone ?? await phoneZoneReader();
      final m = wledTimezoneFor(z.iana, z.offset);
      // The config API opens no NTP socket until the next restart/reconnect.
      await client.setInternetTime(tz: m.tz, offsetSeconds: m.offsetSeconds);
    }
  } catch (e) {
    ok = false;
    LastError.record('Setting the device time zone failed: $e');
  }
  try {
    await client.setClock((now ?? DateTime.now()).toUtc());
  } catch (e) {
    ok = false;
    LastError.record('Setting the device clock failed: $e');
  }
  return ok;
}
