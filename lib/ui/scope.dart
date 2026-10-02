import 'package:flutter/widgets.dart';

import '../app/devices.dart';
import '../app/playback.dart';
import '../library/catalog.dart';

/// Hands the app-wide controllers to the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.playback,
    required this.devices,
    required this.catalog,
    required super.child,
  });

  final PlaybackController playback;
  final DeviceStore devices;
  final Catalog catalog;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) =>
      playback != old.playback || devices != old.devices || catalog != old.catalog;
}
