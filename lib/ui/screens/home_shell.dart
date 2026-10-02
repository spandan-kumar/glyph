import 'package:flutter/material.dart';

import '../widgets/now_playing_bar.dart';
import 'create_screen.dart';
import 'devices_screen.dart';
import 'discover_screen.dart';
import 'on_device_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _pages = [
    DiscoverScreen(),
    CreateScreen(),
    OnDeviceScreen(),
    DevicesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NowPlayingBar(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome),
                  label: 'Discover'),
              NavigationDestination(
                  icon: Icon(Icons.brush_outlined),
                  selectedIcon: Icon(Icons.brush),
                  label: 'Create'),
              NavigationDestination(
                  icon: Icon(Icons.memory_outlined),
                  selectedIcon: Icon(Icons.memory),
                  label: 'On Device'),
              NavigationDestination(
                  icon: Icon(Icons.grid_4x4_outlined),
                  selectedIcon: Icon(Icons.grid_4x4),
                  label: 'Matrix'),
            ],
          ),
        ],
      ),
    );
  }
}
