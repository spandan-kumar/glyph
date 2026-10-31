import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../library/catalog_manifest.dart';
import '../wled/capped_client.dart';
import 'community.dart';

/// Checks GitHub Releases for a newer app version, without sending app or
/// device details with the request.
class AppUpdates extends ChangeNotifier {
  AppUpdates({
    http.Client? client,
    DateTime Function()? now,
    Future<String> Function()? version,
  }) : _innerClient = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _readVersion = version ?? (() async => (await Community.env()).version) {
    _client = CappedClient(_innerClient, maxResponseBytes);
    _loading = _load();
  }

  static const buildEnabled = bool.fromEnvironment(
    'GLYPH_UPDATE_CHECK',
    defaultValue: true,
  );
  static const maxResponseBytes = 256 * 1024;
  static const cadence = Duration(days: 1);
  static const endpoint =
      'https://api.github.com/repos/spandan-kumar/glyph/releases/latest';
  static const enabledKey = 'updates.check';
  static const attemptKey = 'updates.lastAttempt';
  static const latestKey = 'updates.latest';
  static const latestUrlKey = 'updates.latestUrl';
  static const notifiedKey = 'updates.notified';
  static final _tag = RegExp(r'^v(\d+\.\d+\.\d+)$');

  final http.Client _innerClient;
  late final http.Client _client;
  final DateTime Function() _now;
  final Future<String> Function() _readVersion;
  late final Future<void> _loading;
  SharedPreferences? _prefs;
  Future<void>? _checking;
  bool _disposed = false;
  bool enabled = buildEnabled;
  String currentVersion = '';
  String? latestVersion;
  Uri? latestUrl;
  String? _notifiedVersion;

  bool get hasUpdate => latestVersion != null && latestUrl != null;

  Future<void> load() => _loading;

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      enabled = buildEnabled && (_prefs!.getBool(enabledKey) ?? true);
      _notifiedVersion = _prefs!.getString(notifiedKey);
      currentVersion = await _readVersion();
      if (_disposed) return;
      final cached = _prefs!.getString(latestKey);
      final cachedUrl = Uri.tryParse(_prefs!.getString(latestUrlKey) ?? '');
      if (cached != null && cachedUrl != null && _isNewer(cached)) {
        latestVersion = cached;
        latestUrl = cachedUrl;
      } else {
        await _clearNotice();
      }
      notifyListeners();
    } catch (_) {
      // Update checks are optional; storage and package info failures are quiet.
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_disposed || !buildEnabled) return;
    // The switch answers at once; storage catches up behind it.
    enabled = value;
    if (!value) {
      latestVersion = null;
      latestUrl = null;
    }
    notifyListeners();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      if (!value) await _clearNotice();
      await _prefs!.setBool(enabledKey, value);
    } catch (_) {}
    if (value && !_disposed) unawaited(check());
  }

  Future<void> check() =>
      _checking ??= _check().whenComplete(() => _checking = null);

  Future<void> _check() async {
    await load();
    if (_disposed || !buildEnabled || !enabled) return;
    final last = _prefs?.getInt(attemptKey);
    if (last != null &&
        _now().millisecondsSinceEpoch - last < cadence.inMilliseconds) {
      return;
    }
    final attemptedAt = _now();
    try {
      await _prefs?.setInt(attemptKey, attemptedAt.millisecondsSinceEpoch);
    } catch (_) {}
    final revision = latestVersion;
    try {
      final response = await _client
          .get(
            Uri.parse(endpoint),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Glyph',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (_disposed || !enabled || response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['draft'] == true ||
          decoded['prerelease'] == true) {
        await _clearNotice();
        if (!_disposed) notifyListeners();
        return;
      }
      final match = _tag.firstMatch(
        decoded['tag_name'] is String ? decoded['tag_name'] as String : '',
      );
      if (match == null) {
        await _clearNotice();
        if (!_disposed) notifyListeners();
        return;
      }
      final version = match.group(1)!;
      final parsedUrl = Uri.tryParse(
        decoded['html_url'] is String ? decoded['html_url'] as String : '',
      );
      final url =
          parsedUrl != null &&
              parsedUrl.toString().startsWith(
                'https://github.com/spandan-kumar/glyph/releases/',
              )
          ? parsedUrl
          : Community.latestRelease;
      if (_disposed || revision != latestVersion) return;
      if (_isNewer(version)) {
        latestVersion = version;
        latestUrl = url;
        try {
          await _prefs?.setString(latestKey, version);
          await _prefs?.setString(latestUrlKey, url.toString());
        } catch (_) {}
      } else {
        await _clearNotice();
      }
      if (!_disposed) notifyListeners();
    } catch (_) {
      // Network, timeout, capped-body and malformed JSON failures are silent.
    }
  }

  bool _isNewer(String version) =>
      currentVersion.isNotEmpty &&
      CatalogManifest.compareVersions(version, currentVersion) > 0;

  Future<void> _clearNotice() async {
    latestVersion = null;
    latestUrl = null;
    try {
      await _prefs?.remove(latestKey);
      await _prefs?.remove(latestUrlKey);
    } catch (_) {}
  }

  /// Returns true once for each newly discovered version.
  bool takeAnnouncement() {
    final version = latestVersion;
    if (_disposed || version == null || _notifiedVersion == version) {
      return false;
    }
    _notifiedVersion = version;
    unawaited(_prefs?.setString(notifiedKey, version));
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _innerClient.close();
    super.dispose();
  }
}
