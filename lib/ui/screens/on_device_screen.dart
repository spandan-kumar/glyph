import 'package:flutter/material.dart';

import '../../features/device/device_manager.dart';
import '../../features/device/widgets/files_tab.dart';
import '../../features/device/widgets/playlists_tab.dart';
import '../../features/device/widgets/presets_tab.dart';
import '../../features/device/widgets/quick_controls.dart';
import '../../features/device/widgets/schedules_tab.dart';
import '../actions.dart';
import '../scope.dart';
import '../theme.dart';

/// Everything stored on the matrix, which keeps running without the phone:
/// presets, playlists, schedules and files, plus power and brightness.
class OnDeviceScreen extends StatefulWidget {
  const OnDeviceScreen({super.key});

  @override
  State<OnDeviceScreen> createState() => _OnDeviceScreenState();
}

class _OnDeviceScreenState extends State<OnDeviceScreen> {
  DeviceManager? _manager;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = AppScope.of(context).devices;
    if (_manager?.store != store) {
      _manager?.dispose();
      _manager = DeviceManager(store);
    }
  }

  @override
  void dispose() {
    _manager?.dispose();
    super.dispose();
  }

  Future<void> _apply(int id) async {
    final devices = AppScope.of(context).devices;
    if (AppScope.of(context).playback.isStreaming) await GlyphActions.stopStreaming(context);
    await devices.applyPreset(id);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final devices = scope.devices;
    final manager = _manager!;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([devices, manager, scope.playback]),
        builder: (context, _) {
          if (!devices.isConnected) {
            return _Empty(
              icon: Icons.memory,
              text: devices.isLoading
                  ? 'Connecting to ${devices.selected?.name ?? 'the matrix'}…'
                  : devices.selected == null
                  ? 'Connect a matrix in the Matrix tab to see what\'s saved on it.'
                  : devices.error ?? 'Can\'t reach the matrix.',
              action: devices.selected != null && !devices.isLoading
                  ? OutlinedButton.icon(
                      onPressed: devices.refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    )
                  : null,
            );
          }
          // Loads lazily, and again whenever the selected matrix changes.
          manager.syncHost();
          return DefaultTabController(
            length: 4,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'On Device',
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (manager.isLoading)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            IconButton(
                              tooltip: 'Reload',
                              onPressed: () async {
                                await devices.refreshState();
                                await manager.load();
                              },
                              icon: const Icon(Icons.refresh),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      QuickControls(store: devices, manager: manager, playback: scope.playback),
                    ],
                  ),
                ),
                const TabBar(
                  isScrollable: false,
                  labelPadding: EdgeInsets.zero,
                  dividerColor: GlyphColors.outline,
                  tabs: [
                    Tab(text: 'Presets'),
                    Tab(text: 'Playlists'),
                    Tab(text: 'Schedule'),
                    Tab(text: 'Files'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      PresetsTab(manager: manager, store: devices, onApply: _apply),
                      PlaylistsTab(manager: manager, store: devices, onApply: _apply),
                      SchedulesTab(manager: manager),
                      FilesTab(manager: manager, store: devices),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: GlyphColors.textMuted),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: GlyphColors.textMuted),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}
