import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'devices.dart';

/// Links to Glyph's community (sharing, feedback, ideas, roadmap) and the
/// diagnostics a bug report carries. Building the links is pure; opening
/// them and reading the phone go through swappable hooks for tests.
abstract final class Community {
  static const repo = 'https://github.com/spandan-kumar/glyph';

  /// The Glyph Discord (a permanent invite).
  static final discord = Uri.parse('https://discord.gg/9EeCFZAFvk');

  static final showAndTell = discord;

  /// The public board (Ideas → Planned → Building → Shipped).
  static final roadmap = Uri.parse('https://github.com/users/spandan-kumar/projects/4');

  /// Invite after the first fresh Send, then after ten more and a week.
  /// Stored on the phone so restarting the app doesn't reset the cooldown.
  static Future<bool> inviteAfterSend({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt('community.sendsSinceInvite') ?? 0) + 1;
    final last = prefs.getInt('community.lastShareInvite');
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final invite = last == null ||
        (count >= 10 && at - last >= const Duration(days: 7).inMilliseconds);
    await prefs.setInt('community.sendsSinceInvite', invite ? 0 : count);
    if (invite) await prefs.setInt('community.lastShareInvite', at);
    return invite;
  }

  /// GitHub (and some browsers) choke on very long prefilled URLs.
  static const maxUrlLength = 6000;

  /// A bug report prefilled with what we know. The query keys are the field
  /// ids in .github/ISSUE_TEMPLATE/bug.yml — keep them in step.
  static Uri feedback(Diagnostics d) => _issue('bug.yml', 'bug,community', {
    'app_version': d.appLine,
    'phone': d.phoneLine,
    'wled_version': ?d.wledVersion,
    'panel': ?d.panel,
    'diagnostics': d.text,
  });

  static Uri idea(Diagnostics d) =>
      _issue('feedback.yml', 'feedback,community', {'app_version': d.appLine});

  /// [idea] pre-fills what to draw (e.g. a search that found nothing).
  static Uri animationRequest(Diagnostics d, {String? idea}) =>
      _issue('animation_request.yml', 'animation-request,community', {'idea': ?idea, 'panel': ?d.panel});

  static Uri displayRequest() => _issue('display_request.yml', null, const {});

  /// Builds an issue-form link. The last field gives way (is truncated)
  /// when the whole URL would exceed [maxUrlLength]; put the long one last.
  static Uri _issue(String template, String? labels, Map<String, String> fields) {
    final head = '$repo/issues/new?template=$template${labels == null ? '' : '&labels=${_enc(labels)}'}';
    final buf = StringBuffer(head);
    final entries = fields.entries.toList();
    for (final (i, e) in entries.indexed) {
      final prefix = '&${e.key}=';
      if (i < entries.length - 1) {
        buf.write('$prefix${_enc(e.value)}');
      } else {
        final room = maxUrlLength - buf.length - prefix.length;
        buf.write('$prefix${_enc(fitEncoded(e.value, room))}');
      }
    }
    return Uri.parse(buf.toString());
  }

  // Percent-encodes everything but unreserved characters, so spaces are %20
  // rather than '+' and commas stay unambiguous.
  static String _enc(String s) => Uri.encodeComponent(s);

  static const _cut = '\n… (cut to fit)';

  /// [text] shortened (on a character boundary) so its encoded form fits
  /// in [room] characters.
  static String fitEncoded(String text, int room) {
    if (_enc(text).length <= room) return text;
    final budget = room - _enc(_cut).length;
    if (budget <= 0) return '';
    var lo = 0, hi = text.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_enc(text.substring(0, mid)).length <= budget) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    // Don't split a surrogate pair.
    if (lo > 0 && (text.codeUnitAt(lo - 1) & 0xFC00) == 0xD800) lo--;
    return '${text.substring(0, lo)}$_cut';
  }

  /// Opens [uri] outside the app. Swappable in tests.
  static Future<bool> Function(Uri uri) launcher = _launch;

  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// App version and phone, read once. Swappable in tests.
  static Future<AppEnv> Function() environment = _readEnv;

  static Future<AppEnv>? _env;

  static Future<AppEnv> env() => _env ??= environment();

  static void resetForTest() {
    launcher = _launch;
    environment = _readEnv;
    _env = null;
  }

  static const _platform = MethodChannel('glyph/platform');

  static Future<AppEnv> _readEnv() async {
    var version = '', build = '';
    String? phone, android;
    try {
      final p = await PackageInfo.fromPlatform();
      version = p.version;
      build = p.buildNumber;
    } catch (_) {}
    try {
      final m = await _platform.invokeMapMethod<String, Object?>('phone');
      phone = m?['model'] as String?;
      final sdk = m?['sdk'];
      android = m?['android'] == null ? null : 'Android ${m!['android']}${sdk == null ? '' : ' (SDK $sdk)'}';
    } catch (_) {}
    return AppEnv(version: version, build: build, phone: phone, os: android);
  }
}

/// Facts about the app and phone, none of them personal.
class AppEnv {
  const AppEnv({required this.version, this.build = '', this.phone, this.os});

  final String version, build;
  final String? phone, os;
}

/// The most recent failure the person saw, kept in memory for feedback
/// reports. Addresses and URLs are scrubbed on the way in.
abstract final class LastError {
  static String? _message;
  static DateTime? _at;

  static String? get message => _message;
  static DateTime? get at => _at;

  static void record(String message, {DateTime? now}) {
    final m = scrubPersonal(message).trim();
    if (m.isEmpty) return;
    _message = m.length > 400 ? '${m.substring(0, 400)}…' : m;
    _at = now ?? DateTime.now();
  }

  static void clear() {
    _message = null;
    _at = null;
  }
}

final _url = RegExp(r'\b[a-z][a-z0-9+.-]*://\S+', caseSensitive: false);
final _ipv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b');
final _ipv6 = RegExp(r'\b(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b|\b[0-9a-f]{1,4}::(?:[0-9a-f]{1,4}:?)*', caseSensitive: false);
final _mac = RegExp(r'\b[0-9a-f]{2}(?:[:-][0-9a-f]{2}){5}\b|\b[0-9a-f]{12}\b', caseSensitive: false);
final _mdns = RegExp(r'\b[\w-]+\.(?:local|lan|home)\b', caseSensitive: false);

/// [s] without network addresses, URLs, MACs, mDNS hostnames or any of
/// [extra] (device names, saved hosts).
String scrubPersonal(String s, {Iterable<String> extra = const []}) {
  var out = s
      .replaceAll(_url, '<url>')
      .replaceAll(_mac, '<mac>')
      .replaceAll(_ipv4, '<ip>')
      .replaceAll(_ipv6, '<ip>')
      .replaceAll(_mdns, '<host>');
  for (final x in extra) {
    if (x.trim().length >= 3) out = out.replaceAll(x, '<device>');
  }
  return out;
}

/// What a bug report includes: app and phone versions, how many devices,
/// the connected device's firmware and size, whether streaming, and the
/// last error. Never IPs, device names or Wi-Fi details.
class Diagnostics {
  const Diagnostics({
    required this.env,
    this.deviceCount = 0,
    this.connected = false,
    this.wledVersion,
    this.arch,
    this.ledCount,
    this.width,
    this.height,
    this.freeKb,
    this.streaming = false,
    this.lastError,
    this.lastErrorAt,
    this.now,
  });

  /// Reads what's known now from [devices].
  factory Diagnostics.capture(AppEnv env, DeviceStore devices, {required bool streaming, DateTime? now}) {
    final info = devices.info, caps = devices.caps;
    final private = [
      for (final d in devices.saved) ...[d.host, d.name],
      ?info?.name,
      ?info?.ip,
      ?info?.mac,
    ];
    final err = LastError.message;
    return Diagnostics(
      env: env,
      deviceCount: devices.saved.length,
      connected: devices.isConnected,
      wledVersion: info?.version,
      arch: info?.arch,
      ledCount: info?.ledCount,
      width: info != null && info.hasMatrix ? info.matrixWidth : null,
      height: info != null && info.hasMatrix ? info.matrixHeight : null,
      freeKb: caps != null
          ? caps.freeFsBytes ~/ 1024
          : (info?.fsTotalKb != null && info?.fsUsedKb != null ? info!.fsTotalKb! - info.fsUsedKb! : null),
      streaming: streaming,
      lastError: err == null ? null : scrubPersonal(err, extra: private),
      lastErrorAt: LastError.at,
      now: now,
    );
  }

  final AppEnv env;
  final int deviceCount;
  final bool connected;
  final String? wledVersion, arch;
  final int? ledCount, width, height, freeKb;
  final bool streaming;
  final String? lastError;
  final DateTime? lastErrorAt, now;

  String get appLine => env.build.isEmpty ? env.version : '${env.version} (${env.build})';

  String get phoneLine => [?env.phone, ?env.os].join(', ');

  /// "16×16", or "300 LEDs" for a strip; null when nothing is connected.
  String? get panel => width != null && height != null
      ? '$width×$height'
      : ledCount != null
      ? '$ledCount LEDs'
      : null;

  String get text {
    final device = !connected
        ? 'not connected'
        : [
            if (wledVersion != null) 'WLED $wledVersion',
            ?arch,
            if (ledCount != null) '$ledCount LEDs',
            ?panel,
            if (freeKb != null) '$freeKb KB free',
          ].join(' · ');
    return [
      'Glyph ${appLine.isEmpty ? 'unknown' : appLine}',
      'Phone: ${phoneLine.isEmpty ? 'unknown' : phoneLine}',
      'Devices saved: $deviceCount',
      'Device: $device',
      'Streaming: ${streaming ? 'yes' : 'no'}',
      'Last error: ${lastError == null ? 'none' : '$lastError${_ago()}'}',
    ].join('\n');
  }

  String _ago() {
    if (lastErrorAt == null) return '';
    final mins = (now ?? DateTime.now()).difference(lastErrorAt!).inMinutes;
    return mins < 1 ? ' (just now)' : ' ($mins min ago)';
  }
}
