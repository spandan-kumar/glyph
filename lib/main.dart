import 'package:flutter/material.dart';

import 'app/creations.dart';
import 'app/devices.dart';
import 'app/playback.dart';
import 'features/device/device_features.dart';
import 'features/glance/glance_session.dart';
import 'features/notifications/notification_controller.dart';
import 'library/bundled_catalog.dart';
import 'library/catalog.dart';
import 'library/catalog_store.dart';
import 'ui/design/ambient.dart';
import 'ui/design/tokens.dart';
import 'ui/intro_splash.dart';
import 'ui/onboarding/onboarding_flow.dart';
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
  final onboarded = await OnboardingFlow.isDone();
  runApp(GlyphApp(
    catalog: catalog,
    devices: devices,
    playback: playback,
    creations: creations,
    showOnboarding: !onboarded,
    showSplash: true,
    whatsNew: true,
  ));
}

class GlyphApp extends StatefulWidget {
  const GlyphApp({
    super.key,
    required this.catalog,
    required this.devices,
    required this.playback,
    required this.creations,
    this.showOnboarding = false,
    this.showSplash = false,
    this.whatsNew = false,
    this.catalogStore,
  });

  final Catalog catalog;
  final CatalogStore? catalogStore;
  final DeviceStore devices;
  final PlaybackController playback;
  final CreationsStore creations;

  /// First run: show the setup flow before the app.
  final bool showOnboarding;

  /// Play the Glyph intro before anything else (off in tests).
  final bool showSplash;

  /// Offer release notes after an update (off in tests).
  final bool whatsNew;

  @override
  State<GlyphApp> createState() => _GlyphAppState();
}

class _GlyphAppState extends State<GlyphApp> {
  late final _catalog = widget.catalogStore ?? CatalogStore.forApp(widget.catalog);
  late final _ambient = AmbientController(widget.playback);
  late final _notifications = NotificationController(devices: widget.devices, playback: widget.playback);

  @override
  void initState() {
    super.initState();
    _notifications.load();
    _glance.load();
    _catalog.addListener(_catalogChanged);
    _catalog.load();
  }
  void _catalogChanged() {
    if (!mounted) return;
    _glance.catalog = _catalog.catalog;
    setState(() {});
  }
  late final _glance = GlanceSession(devices: widget.devices, playback: widget.playback, catalog: widget.catalog, creations: widget.creations);
  late bool _onboarding = widget.showOnboarding;
  late bool _splash = widget.showSplash;

  @override
  void dispose() {
    _catalog.removeListener(_catalogChanged);
    if (widget.catalogStore == null) _catalog.dispose();
    _glance.dispose();
    _notifications.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      playback: widget.playback,
      devices: widget.devices,
      catalog: _catalog.catalog,
      catalogStore: _catalog,
      creations: widget.creations,
      notifications: _notifications,
      glance: _glance,
      child: AmbientScope(
        controller: _ambient,
        child: MaterialApp(
          title: 'Glyph',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: AnimatedSwitcher(
            duration: Lb.slow,
            switchInCurve: Lb.ease,
            switchOutCurve: Lb.ease,
            child: _splash
                ? IntroSplash(
                    key: const ValueKey('splash'),
                    // The whole show on first run; a quick flourish after.
                    full: widget.showOnboarding,
                    onDone: () => setState(() => _splash = false),
                  )
                : _onboarding
                    ? OnboardingFlow(onDone: () => setState(() => _onboarding = false))
                    : HomeShell(whatsNew: widget.whatsNew, firstRun: widget.showOnboarding),
          ),
        ),
      ),
    );
  }
}
