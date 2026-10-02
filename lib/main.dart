import 'package:flutter/material.dart';

import 'app/creations.dart';
import 'app/devices.dart';
import 'app/playback.dart';
import 'features/device/device_features.dart';
import 'library/bundled_catalog.dart';
import 'library/catalog.dart';
import 'ui/scope.dart';
import 'ui/screens/home_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = await loadBundledCatalog();
  final devices = DeviceStore();
  final playback = PlaybackController();
  final creations = CreationsStore();
  // Don't block first paint on the network; the store notifies when ready.
  // Keeps the home-screen widget and mirror group in sync with the store.
  DeviceFeatures.attach(devices: devices, playback: playback);
  devices.load();
  creations.load();
  runApp(GlyphApp(
      catalog: catalog, devices: devices, playback: playback, creations: creations));
}

class GlyphApp extends StatelessWidget {
  const GlyphApp({
    super.key,
    required this.catalog,
    required this.devices,
    required this.playback,
    required this.creations,
  });

  final Catalog catalog;
  final DeviceStore devices;
  final PlaybackController playback;
  final CreationsStore creations;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      playback: playback,
      devices: devices,
      catalog: catalog,
      creations: creations,
      child: MaterialApp(
        title: 'Glyph',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
