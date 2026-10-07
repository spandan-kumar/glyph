import 'package:flutter/widgets.dart';

import '../app/creations.dart';
import '../app/devices.dart';
import '../app/playback.dart';
import '../features/notifications/notification_controller.dart';
import '../features/glance/glance_session.dart';
import '../library/catalog.dart';
import '../library/catalog_store.dart';

/// Hands the app-wide controllers to the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.playback,
    required this.devices,
    required this.catalog,
    required this.creations,
    this.notifications,
    this.glance,
    this.catalogStore,
    required super.child,
  });

  final PlaybackController playback;
  final DeviceStore devices;
  final Catalog catalog;
  final CatalogStore? catalogStore;
  final CreationsStore creations;
  final NotificationController? notifications;
  final GlanceSession? glance;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) =>
      playback != old.playback ||
      devices != old.devices ||
      catalog != old.catalog ||
      creations != old.creations || notifications != old.notifications || glance != old.glance ||
      catalogStore != old.catalogStore;
}
