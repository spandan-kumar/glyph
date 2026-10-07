import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'notification_logo.dart';

class NotificationApp {
  const NotificationApp(this.package, this.name);
  final String package, name;
}

class LogoAlert {
  const LogoAlert(this.package, this.key, this.created, this.logo);
  final String package, key;
  final DateTime created;
  final NotificationLogo logo;
}

/// Android sends only package identity, arrival/removal and installed icon RGB.
class NotificationService extends ChangeNotifier {
  NotificationService({
    bool? supported,
    Stream<Object?> Function()? events,
    Future<Object?> Function(String, Object?)? invoke,
  }) : supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       _eventsOf = events ?? _events.receiveBroadcastStream,
       _invoke =
           invoke ??
           ((method, args) => _methods.invokeMethod<Object?>(method, args));

  static const _methods = MethodChannel('glyph/notifications');
  static const _events = EventChannel('glyph/notifications/events');
  final bool supported;
  final Stream<Object?> Function() _eventsOf;
  final Future<Object?> Function(String, Object?) _invoke;
  StreamSubscription<Object?>? _sub;
  final _alerts = StreamController<LogoAlert>.broadcast(sync: true);
  final _removed = StreamController<String>.broadcast(sync: true);
  Stream<LogoAlert> get alerts => _alerts.stream;
  Stream<String> get removed => _removed.stream;
  bool access = false, connected = false, stopRequested = false;
  bool _disposed = false;

  Future<List<NotificationApp>> apps() async {
    if (!supported) return [];
    final raw = await _invoke('apps', null);
    if (raw is! List) return [];
    return [
      for (final m in raw.whereType<Map>())
        if (m['package'] is String && m['name'] is String)
          NotificationApp(m['package'] as String, m['name'] as String),
    ];
  }

  Future<NotificationLogo> icon(String package) async {
    final raw = supported ? await _invoke('icon', package) : null;
    return _logo(raw);
  }

  static NotificationLogo _logo(Object? raw) =>
      raw is Uint8List && raw.length == 3072
      ? NotificationLogo(raw)
      : NotificationLogo.fallback;

  Future<void> refresh() async {
    if (!supported) return;
    try {
      final raw = await _invoke('status', null);
      if (!_disposed && raw is Map) _status(raw);
    } on PlatformException catch (_) {
      _status({'access': false, 'connected': false});
    } on MissingPluginException catch (_) {
      _status({'access': false, 'connected': false});
    }
  }

  Future<void> configure(Set<String> packages) async {
    if (!supported || _disposed) return;
    if (packages.isNotEmpty) {
      _sub ??= _eventsOf().listen(
        _event,
        onError: (_) => _status({'connected': false}),
      );
    }
    if (packages.isNotEmpty) stopRequested = false;
    final raw = await _invoke('configure', packages.toList());
    if (!_disposed && raw is Map) _status(raw);
    if (packages.isEmpty) {
      await _sub?.cancel();
      _sub = null;
    }
  }

  Future<void> openSettings() async {
    if (supported) await _invoke('openSettings', null);
  }

  void _event(Object? event) {
    if (_disposed || event is! Map) return;
    if (event.containsKey('access') ||
        event.containsKey('connected') ||
        event.containsKey('stopped')) {
      _status(event);
    }
    if (!access || !connected) return;
    if (event['removed'] case final String key) {
      _removed.add(key);
    } else if (event['package'] is String &&
        event['key'] is String &&
        event['time'] is int) {
      _alerts.add(
        LogoAlert(
          event['package'] as String,
          event['key'] as String,
          DateTime.fromMillisecondsSinceEpoch(event['time'] as int),
          _logo(event['icon']),
        ),
      );
    }
  }

  void _status(Map raw) {
    if (_disposed) return;
    if (raw['access'] case final bool value) access = value;
    if (raw['connected'] case final bool value) connected = value;
    if (raw['stopped'] == true) stopRequested = true;
    if (!access) connected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    if (supported) _invoke('configure', <String>[]).catchError((_) => null);
    _alerts.close();
    _removed.close();
    super.dispose();
  }
}
