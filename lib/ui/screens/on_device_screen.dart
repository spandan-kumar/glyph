import 'package:flutter/material.dart';

import '../actions.dart';
import '../scope.dart';
import '../theme.dart';

/// What's stored on the controller: presets that keep playing without the
/// phone.
class OnDeviceScreen extends StatefulWidget {
  const OnDeviceScreen({super.key});

  @override
  State<OnDeviceScreen> createState() => _OnDeviceScreenState();
}

class _OnDeviceScreenState extends State<OnDeviceScreen> {
  Future<Map<int, String>>? _presets;
  String? _host;

  void _load() {
    final client = AppScope.of(context).devices.client;
    _presets = client?.presets();
  }

  @override
  Widget build(BuildContext context) {
    final devices = AppScope.of(context).devices;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: devices,
        builder: (context, _) {
          if (!devices.isConnected) {
            return const _Empty(
              icon: Icons.memory,
              text: 'Connect a matrix to see what\'s saved on it.',
            );
          }
          // Reload when the device changes or after a save refreshes info.
          if (_host != devices.selected!.host || _presets == null) {
            _host = devices.selected!.host;
            _load();
          }
          final info = devices.info!;
          return RefreshIndicator(
            onRefresh: () async {
              setState(_load);
              await _presets;
            },
            child: FutureBuilder<Map<int, String>>(
              future: _presets,
              builder: (context, snap) {
                final presets = snap.data?.entries.toList() ?? [];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    const Text('On Device',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      info.fsTotalKb != null && info.fsUsedKb != null
                          ? '${info.fsTotalKb! - info.fsUsedKb!} KB free · plays without your phone'
                          : 'Plays without your phone',
                      style: const TextStyle(color: GlyphColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    if (snap.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snap.hasError)
                      Text('Couldn\'t load presets: ${snap.error}',
                          style: const TextStyle(color: GlyphColors.danger))
                    else if (presets.isEmpty)
                      const Text('No presets yet. Open an animation and tap "Save to matrix".',
                          style: TextStyle(color: GlyphColors.textMuted))
                    else
                      for (final p in presets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: GlyphColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              leading: CircleAvatar(
                                backgroundColor: GlyphColors.surfaceHigh,
                                child: Text('${p.key}',
                                    style: const TextStyle(fontSize: 13)),
                              ),
                              title: Text(p.value.isEmpty ? 'Preset ${p.key}' : p.value),
                              trailing: const Icon(Icons.play_arrow_rounded),
                              onTap: () async {
                                await GlyphActions.stopStreaming(context);
                                await devices.client!.applyPreset(p.key);
                              },
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: GlyphColors.textMuted),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: GlyphColors.textMuted)),
          ]),
        ),
      );
}
