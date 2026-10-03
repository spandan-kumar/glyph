import 'package:flutter/material.dart';

import '../../app/storage_alerts.dart';
import '../design/ambient.dart';
import '../design/dock.dart';
import '../design/tokens.dart';
import '../make/make_screen.dart';
import '../matrix/matrix_screen.dart';
import '../scope.dart';
import '../tune/tune_screen.dart';

/// The app: one room lit by the matrix, three places, a floating dock.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});

  final int initialTab;

  /// Lets any screen jump to another destination (e.g. "Connect a matrix").
  static void go(BuildContext context, int tab) =>
      context.findAncestorStateOfType<_HomeShellState>()?._select(tab);

  /// Panels that need the full height (e.g. Display's Tweak) hide the dock.
  static final dockHidden = ValueNotifier<bool>(false);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _tab = widget.initialTab;

  static const _items = [
    DockItem(Icons.grid_view_sharp, 'Display'),
    DockItem(Icons.draw_outlined, 'Make'),
    DockItem(Icons.developer_board_outlined, 'Device'),
  ];

  void _select(int i) => setState(() => _tab = i);

  StorageAlerts? _storage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _storage ??= StorageAlerts(AppScope.of(context).devices, onAlert: _storageAlert);
  }

  @override
  void dispose() {
    _storage?.dispose();
    super.dispose();
  }

  void _storageAlert(StorageLevel level, int percent) {
    if (!mounted) return;
    final msg = level == StorageLevel.nearlyFull
        ? 'Your device is $percent% full. Clear old animations in Device → Storage to keep sending new ones.'
        : 'Your device is half full. You can free up space anytime in the Device tab.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: Duration(seconds: level == StorageLevel.nearlyFull ? 8 : 5),
        action: SnackBarAction(label: 'Open', onPressed: () => _select(2)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final ambient = AmbientScope.of(context);
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
          child: IndexedStack(
            index: _tab,
            children: [
              for (var i = 0; i < 3; i++)
                // Hidden destinations stop their tickers.
                TickerMode(
                  enabled: i == _tab,
                  child: const [TuneScreen(), MakeScreen(), MatrixScreen()][i],
                ),
            ],
          ),
        ),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: HomeShell.dockHidden,
          builder: (context, hidden, dock) => AnimatedSlide(
            offset: Offset(0, hidden ? 1.5 : 0),
            duration: Lb.medium,
            curve: Lb.ease,
            child: IgnorePointer(ignoring: hidden, child: dock),
          ),
          child: Dock(
            items: _items,
            index: _tab,
            onSelect: _select,
            accent: ambient.accent,
          ),
        ),
      ),
    );
  }
}
