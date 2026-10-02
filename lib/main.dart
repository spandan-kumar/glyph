import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/creations.dart';
import 'app/devices.dart';
import 'app/playback.dart';
import 'library/catalog.dart';
import 'ui/scope.dart';
import 'ui/screens/home_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = Catalog.parse(await rootBundle.loadString('assets/catalog/starter.json'));
  final devices = DeviceStore();
  final playback = PlaybackController();
  final creations = CreationsStore();
  // Don't block first paint on the network; the store notifies when ready.
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
