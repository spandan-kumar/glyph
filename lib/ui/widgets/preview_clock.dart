import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Preview updates share a frame, without keeping Flutter at display refresh.
class PreviewTicker {
  PreviewTicker(this.onTick);

  final void Function(Duration) onTick;
  ValueListenable<TickerModeData>? _mode;
  Duration? _start;
  bool _enabled = true;

  void bind(BuildContext context, {bool enabled = true}) {
    _enabled = enabled;
    _start ??= _PreviewClock.instance.elapsed;
    final mode = TickerMode.getValuesNotifier(context);
    if (!identical(mode, _mode)) {
      _mode?.removeListener(_sync);
      _mode = mode..addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    final clock = _PreviewClock.instance;
    if (_enabled && _mode!.value.enabled) {
      clock.add(this);
    } else {
      clock.remove(this);
    }
  }

  void dispose() {
    _mode?.removeListener(_sync);
    _PreviewClock.instance.remove(this);
  }
}

class _PreviewClock with WidgetsBindingObserver {
  _PreviewClock() {
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  static final instance = _PreviewClock();
  Duration _elapsed = Duration.zero;
  final _tickers = <PreviewTicker>{};
  Timer? _timer;
  bool _foreground = true;
  int? _frameCallback;

  Duration get elapsed => _elapsed;

  void add(PreviewTicker ticker) {
    _tickers.add(ticker);
    _sync();
  }

  void remove(PreviewTicker ticker) {
    _tickers.remove(ticker);
    _sync();
  }

  void _sync() {
    if (_foreground && _tickers.isNotEmpty) {
      _timer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (_frameCallback != null) return;
        _frameCallback = SchedulerBinding.instance.scheduleFrameCallback((stamp) {
          _frameCallback = null;
          if (!_foreground) return;
          if (stamp < _elapsed) {
            final shift = _elapsed - stamp;
            for (final ticker in _tickers) {
              ticker._start = ticker._start! - shift;
            }
          }
          _elapsed = stamp;
          final now = elapsed;
          for (final ticker in _tickers.toList()) {
            if (_tickers.contains(ticker)) ticker.onTick(now - ticker._start!);
          }
        });
      });
    } else {
      _timer?.cancel();
      _timer = null;
      if (_frameCallback case final id?) {
        SchedulerBinding.instance.cancelFrameCallbackWithId(id);
        _frameCallback = null;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }
}
