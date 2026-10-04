import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'now_playing.dart';

enum NowPlayingAccess { unknown, granted, denied, unsupported }

/// The phone's media sessions, via the Android bridge (NowPlayingBridge.kt).
///
/// Listens only while someone holds it ([acquire]/[release]): the Now
/// Playing screen, and whoever keeps the cover on the device after it
/// closes. Covers live in memory only — the current one, nothing else — so
/// following songs never stores anything on the phone or the device.
class NowPlayingService extends ChangeNotifier implements NowPlayingFeed {
  NowPlayingService({bool? supported, Stream<Object?> Function()? events})
      : supported = supported ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
        _eventsOf = events ?? _events.receiveBroadcastStream;

  static final shared = NowPlayingService();

  static const _methods = MethodChannel('glyph/now_playing');
  static const _events = EventChannel('glyph/now_playing/events');

  /// Android only for now: iOS doesn't share other apps' playback.
  final bool supported;

  /// Where bridge events come from; tests pass their own stream.
  final Stream<Object?> Function() _eventsOf;

  NowPlayingAccess _access = NowPlayingAccess.unknown;
  NowPlaying? _current;
  StreamSubscription<Object?>? _sub;
  final _owners = <Object>{};

  NowPlayingAccess get access => supported ? _access : NowPlayingAccess.unsupported;

  @override
  NowPlaying? get current => _current;

  bool get isListening => _sub != null;

  void acquire(Object owner) {
    _owners.add(owner);
    if (_sub == null) _listen();
  }

  void release(Object owner) {
    _owners.remove(owner);
    if (_owners.isEmpty) _stop();
  }

  /// Starts over, e.g. after coming back from the settings page.
  Future<void> refresh() async {
    if (_owners.isEmpty) return;
    _stop(notify: false);
    _listen();
  }

  Future<void> openSettings() async {
    if (!supported) return;
    try {
      await _methods.invokeMethod<void>('openSettings');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  void _listen() {
    if (!supported) return;
    _sub = _eventsOf().listen(
          (e) => _onEvent(e is Map ? e : const {}),
          onError: (_) => _set(NowPlayingAccess.denied, null),
        );
  }

  void _stop({bool notify = true}) {
    _sub?.cancel();
    _sub = null;
    _current = null;
    if (notify) notifyListeners();
  }

  void _onEvent(Map<Object?, Object?> m) {
    if (m['access'] == false) return _set(NowPlayingAccess.denied, null);
    _set(NowPlayingAccess.granted, NowPlaying.fromMap(m));
  }

  void _set(NowPlayingAccess a, NowPlaying? np) {
    _access = a;
    _current = np;
    notifyListeners();
  }

}
