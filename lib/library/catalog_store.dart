import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/generators/sprite_library.dart';
import 'catalog.dart';
import 'catalog_key.dart';
import 'remote_catalog.dart';

/// Bundled first paint, an offline overlay, then opt-in foreground checks.
/// It never owns playback or personal-library IDs.
class CatalogStore extends ChangeNotifier with WidgetsBindingObserver {
  CatalogStore({required this.bundled, this.remote, DateTime Function()? now})
    : catalog = bundled,
      _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
  }

  /// `GLYPH_CATALOG_URL` (a directory URL) and `GLYPH_CATALOG_PUBLIC_KEY`
  /// let a staging build point at a test deployment signed with a test key.
  static CatalogStore forApp(Catalog bundled) {
    const override = String.fromEnvironment('GLYPH_CATALOG_URL');
    const keyOverride = String.fromEnvironment('GLYPH_CATALOG_PUBLIC_KEY');
    final endpoint = override.isEmpty ? RemoteCatalog.defaultUrl : override;
    final uri = Uri.tryParse(endpoint);
    final key = keyOverride.isEmpty ? catalogPublicKey : keyOverride;
    return CatalogStore(
      bundled: bundled,
      remote:
          decodeCatalogKey(key) != null &&
              uri != null &&
              uri.scheme == 'https' &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty &&
              !uri.hasQuery &&
              !uri.hasFragment &&
              endpoint.length <= 1024
          ? RemoteCatalog(
              url: uri,
              cacheDir: getApplicationSupportDirectory,
              publicKey: key,
              appVersion: () async => (await PackageInfo.fromPlatform()).version,
            )
          : null,
    );
  }

  static const cadence = Duration(days: 1);
  static const automaticKey = 'catalog.automatic.v1';
  final Catalog bundled;
  final RemoteCatalog? remote;
  final DateTime Function() _now;
  Catalog catalog;
  int revision = 0, epoch = 0;
  Set<String> revoked = const {};
  bool needsNewerApp = false;
  List<String> dropped = const [];
  bool automatic = false, ready = false, checking = false, failed = false;
  DateTime? lastAttempt;
  String? message;
  bool _disposed = false, _foreground = true;
  Timer? _timer;
  Future<void>? _loading, _checking;
  SharedPreferences? _prefs;
  String get _attemptKey => 'catalog.attempt.v1.${remote?.url}';
  bool get enabled => remote?.usable ?? false;
  int get downloaded =>
      catalog.items.where((i) => bundled.byId(i.id) == null).length;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final cached = remote?.loadCached(bundled: bundled);
    try {
      _prefs = await SharedPreferences.getInstance();
      automatic = enabled && (_prefs!.getBool(automaticKey) ?? false);
      final stamp = _prefs!.getInt(_attemptKey);
      if (stamp != null) {
        lastAttempt = DateTime.fromMillisecondsSinceEpoch(stamp);
      }
    } catch (_) {}
    final result = await cached;
    if (_disposed) return;
    if (result != null) _apply(result);
    ready = true;
    notifyListeners();
    _schedule();
  }

  void _apply(RemoteCatalogResult result) {
    SpriteLibrary.replaceRemote(result.sprites);
    // Bundled items win; only the signed manifest can retire them.
    catalog = bundled.merge(result.catalog, revoked: result.revoked);
    revision = result.revision;
    epoch = result.epoch;
    revoked = result.revoked;
    dropped = result.dropped;
  }

  Future<void> setAutomatic(bool value) async {
    await load();
    if (_disposed || !enabled) return;
    automatic = value;
    notifyListeners();
    try {
      await _prefs?.setBool(automaticKey, value);
    } catch (_) {}
    if (!_disposed) _schedule();
  }

  Future<void> check() =>
      _checking ??= _check().whenComplete(() => _checking = null);
  Future<void> _check() async {
    await load();
    if (_disposed || !enabled) return;
    _timer?.cancel();
    checking = true;
    failed = false;
    message = null;
    lastAttempt = _now();
    notifyListeners();
    try {
      await _prefs?.setInt(_attemptKey, lastAttempt!.millisecondsSinceEpoch);
    } catch (_) {}
    // One baseline everywhere: the bundled catalog, as on a cold start.
    final result = await remote!.fetch(bundled: bundled);
    if (_disposed) return;
    checking = false;
    if (result == null) {
      failed = true;
      needsNewerApp = remote!.needsNewerApp;
      message = needsNewerApp
          ? 'New animations need a newer version of Glyph. Your library is still available.'
          : 'Couldn’t check for animations. Your library is still available.';
    } else if (result.changed) {
      needsNewerApp = false;
      _apply(result);
      message = 'Your library has been updated.';
    } else {
      needsNewerApp = false;
      message = 'Your library is up to date.';
    }
    notifyListeners();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed ||
        !ready ||
        !automatic ||
        !enabled ||
        !_foreground ||
        checking) {
      return;
    }
    final elapsed = lastAttempt == null
        ? cadence
        : _now().difference(lastAttempt!);
    if (elapsed >= cadence || elapsed.isNegative) {
      // Defer beyond load/check completion, avoiding a recursive load await.
      _timer = Timer(Duration.zero, () => unawaited(check()));
    } else {
      _timer = Timer(cadence - elapsed, () => unawaited(check()));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    remote?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
