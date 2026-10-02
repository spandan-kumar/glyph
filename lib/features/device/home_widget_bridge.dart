import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../app/devices.dart';

/// Keeps the Android home-screen widget (GlyphWidgetProvider.kt) pointed at
/// the selected matrix. The widget's buttons talk to WLED directly from
/// Kotlin, so they work while the app is closed; this only hands over the
/// host and name and refreshes the widget when they or the power state change.
class HomeWidgetBridge {
  HomeWidgetBridge._(this._store);

  static const androidName = 'GlyphWidgetProvider';

  // Keys shared with GlyphWidgetProvider.kt.
  static const keyHost = 'glyph_host';
  static const keyName = 'glyph_name';
  static const keyOn = 'glyph_on';

  /// Last result of a widget button; cleared so fresh app state shows.
  static const keyStatus = 'glyph_widget_status';

  final DeviceStore _store;
  String? _host, _name;
  bool? _on;

  static final _attached = Expando<HomeWidgetBridge>();

  /// Starts syncing; safe to call more than once. No-op off Android.
  static void attach(DeviceStore store) {
    if (kIsWeb || !Platform.isAndroid || _attached[store] != null) return;
    final b = _attached[store] = HomeWidgetBridge._(store);
    store.addListener(b._sync);
    b._sync();
  }

  void _sync() {
    final d = _store.selected;
    final host = d?.host;
    final name = _store.info?.name ?? d?.name;
    final on = _store.isOn;
    if (host == _host && name == _name && on == _on) return;
    _host = host;
    _name = name;
    _on = on;
    unawaited(_push(host, name, on));
  }

  static Future<void> _push(String? host, String? name, bool? on) async {
    try {
      await HomeWidget.saveWidgetData<String>(keyHost, host);
      await HomeWidget.saveWidgetData<String>(keyName, name);
      await HomeWidget.saveWidgetData<bool>(keyOn, on);
      await HomeWidget.saveWidgetData<String>(keyStatus, null);
      await HomeWidget.updateWidget(androidName: androidName);
    } catch (_) {
      // No widget placed yet, or the plugin is unavailable (tests).
    }
  }
}
