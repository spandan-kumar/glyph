import 'package:flutter/material.dart';

import '../design/ambient.dart';
import '../design/dock.dart';
import '../design/tokens.dart';
import '../make/make_screen.dart';
import '../matrix/matrix_screen.dart';
import '../tune/tune_screen.dart';

/// The app: one room lit by the matrix, three places, a floating dock.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});

  final int initialTab;

  /// Lets any screen jump to another destination (e.g. "Connect a matrix").
  static void go(BuildContext context, int tab) =>
      context.findAncestorStateOfType<_HomeShellState>()?._select(tab);

  /// Panels that need the full height (e.g. Tune's Tweak) hide the dock.
  static final dockHidden = ValueNotifier<bool>(false);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _tab = widget.initialTab;

  static const _items = [
    DockItem(Icons.radio_outlined, 'Tune'),
    DockItem(Icons.draw_outlined, 'Make'),
    DockItem(Icons.grid_on_outlined, 'Matrix'),
  ];

  void _select(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final ambient = AmbientScope.of(context);
    return PopScope(
      // Back from Make or Matrix returns to Tune; only Tune leaves the app.
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
