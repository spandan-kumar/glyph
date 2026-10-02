import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  // Don't block first paint on the network; the store notifies when ready.
  devices.load();
  runApp(GlyphApp(catalog: catalog, devices: devices, playback: playback));
}

class GlyphApp extends StatelessWidget {
  const GlyphApp({
    super.key,
    required this.catalog,
    required this.devices,
    required this.playback,
  });

  final Catalog catalog;
  final DeviceStore devices;
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      playback: playback,
      devices: devices,
      catalog: catalog,
      child: MaterialApp(
        title: 'Glyph',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
