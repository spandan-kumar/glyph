import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/generators/sprite_library.dart';
import 'catalog.dart';
import 'remote_catalog.dart';

/// Bundled first paint, an offline overlay, then opt-in foreground checks.
/// It never owns playback or personal-library IDs.
class CatalogStore extends ChangeNotifier with WidgetsBindingObserver {
  CatalogStore({required this.bundled, this.remote, DateTime Function()? now})
    : catalog = bundled,
      _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
  }

  static CatalogStore forApp(Catalog bundled) {
    const override = String.fromEnvironment('GLYPH_CATALOG_URL');
    final endpoint = override.isEmpty ? RemoteCatalog.defaultUrl : override;
    final uri = endpoint == null ? null : Uri.tryParse(endpoint);
    return CatalogStore(
      bundled: bundled,
      remote:
          uri != null &&
              uri.scheme == 'https' &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty &&
              !uri.hasQuery &&
              !uri.hasFragment &&
              endpoint!.length <= 1024
          ? RemoteCatalog(url: uri, cacheDir: getApplicationSupportDirectory)
          : null,
    );
  }

  static const cadence = Duration(days: 1);
  static const automaticKey = 'catalog.automatic.v1';
  final Catalog bundled;
  final RemoteCatalog? remote;
  final DateTime Function() _now;
  Catalog catalog;
  int revision = 0;
  List<String> dropped = const [];
  bool automatic = false, ready = false, checking = false, failed = false;
  DateTime? lastAttempt;
  String? message;
  bool _disposed = false, _foreground = true;
  Timer? _timer;
  Future<void>? _loading, _checking;
  SharedPreferences? _prefs;
  String get _attemptKey => 'catalog.attempt.v1.${remote?.url}';
  bool get enabled => remote != null;
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
    catalog = bundled.merge(result.catalog);
    revision = result.revision;
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
    if (_disposed || remote == null) return;
    _timer?.cancel();
    checking = true;
    failed = false;
    message = null;
    lastAttempt = _now();
    notifyListeners();
    try {
      await _prefs?.setInt(_attemptKey, lastAttempt!.millisecondsSinceEpoch);
    } catch (_) {}
    final result = await remote!.fetch(bundled: catalog);
    if (_disposed) return;
    checking = false;
    if (result == null) {
      failed = true;
      message =
          'Couldn’t check for animations. Your library is still available.';
    } else {
      final previous = revision;
      _apply(result);
      message = previous == revision
          ? 'Your library is up to date.'
          : 'Your library has been updated.';
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
