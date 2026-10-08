import 'package:flutter/material.dart';

import '../../app/community.dart';
import '../../app/storage_alerts.dart';
import '../../app/whats_new.dart';
import '../community/whats_new_sheet.dart';
import '../design/ambient.dart';
import '../design/dock.dart';
import '../design/tokens.dart';
import '../make/make_screen.dart';
import '../matrix/matrix_screen.dart';
import '../scope.dart';
import '../tune/tune_screen.dart';

/// The app: one room lit by the matrix, three places, a dock strip.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0, this.whatsNew = false, this.firstRun = false});

  final int initialTab;

  /// Offer release notes once after an update (off in tests).
  final bool whatsNew;

  /// The person was onboarded this launch, so it's a fresh install.
  final bool firstRun;

  /// Lets any screen jump to another destination (e.g. "Connect a matrix").
  static void go(BuildContext context, int tab) => context.findAncestorStateOfType<_HomeShellState>()?._select(tab);

  /// Panels that need the full height (e.g. Display's Tweak) hide the dock.
  static final dockHidden = ValueNotifier<bool>(false);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _tab = widget.initialTab;

  static const _items = [
    DockItem('Display', DockGlyph.display),
    DockItem('Make', DockGlyph.make),
    DockItem('Device', DockGlyph.device),
  ];

  void _select(int i) {
    _showDock();
    setState(() => _tab = i);
  }

  /// The dock tucks away while the page scrolls down and comes back as soon
  /// as it scrolls up (or reaches the top), like a browser's toolbar.
  final _scrolledAway = ValueNotifier(false);
  double _drift = 0;

  void _showDock() {
    _drift = 0;
    _scrolledAway.value = false;
  }

  bool _onScroll(ScrollNotification n) {
    if (n is! ScrollUpdateNotification || n.metrics.axis != Axis.vertical) return false;
    final d = n.scrollDelta ?? 0;
    if (n.metrics.pixels <= n.metrics.minScrollExtent + 8) {
      _showDock();
      return false;
    }
    // Only a deliberate run of scrolling one way flips it, not jitter.
    if (d == 0) return false;
    if (d.sign != _drift.sign) _drift = 0;
    _drift += d;
    if (_drift > 24) {
      _scrolledAway.value = true;
    } else if (_drift < -12) {
      _scrolledAway.value = false;
    }
    return false;
  }

  StorageAlerts? _storage;

  @override
  void initState() {
    super.initState();
    if (widget.whatsNew) WidgetsBinding.instance.addPostFrameCallback((_) => _whatsNew());
  }

  Future<void> _whatsNew() async {
    try {
      final env = await Community.env();
      final notes = await WhatsNew.due(env.version, firstRun: widget.firstRun);
      if (notes == null || !mounted) return;
      await showWhatsNewSheet(context, env.version, notes);
    } catch (_) {
      // Notes are a nicety; never let them get in the way.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _storage ??= StorageAlerts(AppScope.of(context).devices, onAlert: _storageAlert);
  }

  @override
  void dispose() {
    _scrolledAway.dispose();
    _storage?.dispose();
    super.dispose();
  }

  void _storageAlert(StorageLevel level, int percent) {
    if (!mounted) return;
    final msg = level == StorageLevel.nearlyFull
        ? 'Your device is $percent% full. Free up space in Device → Storage to keep sending new ones.'
        : 'Your device is half full. You can free up space anytime in the Device tab.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: Duration(seconds: level == StorageLevel.nearlyFull ? 8 : 5),
          action: SnackBarAction(label: 'Open', onPressed: () => _select(2)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ambient = AmbientScope.read(context);
    return PopScope(
      // Back from Make or Device returns to Display; only Display leaves the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != 0) _select(0);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: AmbientBackdrop(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: IndexedStack(
              index: _tab,
              children: [
                for (var i = 0; i < 3; i++)
                  // Hidden destinations stop their tickers.
                  TickerMode(enabled: i == _tab, child: const [TuneScreen(), MakeScreen(), MatrixScreen()][i]),
              ],
            ),
          ),
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: Listenable.merge([
            HomeShell.dockHidden,
            _scrolledAway,
            ambient,
          ]),
          builder: (context, dock) {
            final hidden = HomeShell.dockHidden.value || _scrolledAway.value;
            return AnimatedSlide(
              offset: Offset(0, hidden ? 1.6 : 0),
              duration: Lb.dock,
              curve: Lb.easeInOut,
              child: AnimatedOpacity(
                opacity: hidden ? 0 : 1,
                duration: Lb.medium,
                curve: Lb.ease,
                child: IgnorePointer(
                  ignoring: hidden,
                  child: Dock(
                    items: _items,
                    index: _tab,
                    onSelect: _select,
                    accent: ambient.accent,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
