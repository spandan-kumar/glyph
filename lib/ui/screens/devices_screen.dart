import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/devices.dart';
import '../../app/test_pattern.dart';
import '../../wled/discovery.dart';
import '../../wled/layout.dart';
import '../actions.dart';
import '../scope.dart';
import '../theme.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _discovery = WledDiscovery();
  final _found = <String, DiscoveredDevice>{};
  StreamSubscription<DiscoveredDevice>? _sub;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _sub = _discovery.devices.listen(_onFound);
    _discovery.start().catchError((_) {});
  }

  void _onFound(DiscoveredDevice d) {
    if (mounted) setState(() => _found[d.host] = d);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _discovery.stop();
    super.dispose();
  }

  /// Fallback for networks where mDNS is blocked: probe the local /24.
  Future<void> _scan() async {
    final ip = await _ownIp();
    if (ip == null) return;
    setState(() => _scanning = true);
    await for (final d in scanSubnet(ip)) {
      _onFound(d);
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<String?> _ownIp() async {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final i in ifaces) {
      for (final a in i.addresses) {
        if (!a.isLoopback) return a.address;
      }
    }
    return null;
  }

  Future<void> _addByIp() async {
    final controller = TextEditingController();
    final host = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add by IP address'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: '192.168.1.50'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Connect')),
        ],
      ),
    );
    if (host == null || host.isEmpty || !mounted) return;
    final d = await probeHost(host);
    if (!mounted) return;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No WLED device answered at $host')));
      return;
    }
    await AppScope.of(context).devices.addAndSelect(d.host, d.name);
  }

  @override
  Widget build(BuildContext context) {
    final devices = AppScope.of(context).devices;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: devices,
        builder: (context, _) {
          final savedHosts = devices.saved.map((d) => d.host).toSet();
          final nearby = _found.values.where((d) => !savedHosts.contains(d.host));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              const Text('Matrix',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              if (devices.selected != null) _ActiveDeviceCard(store: devices),
              if (devices.saved.any((d) => d.host != devices.selected?.host)) ...[
                const _Header('Saved'),
                for (final d in devices.saved)
                  if (d.host != devices.selected?.host)
                    _DeviceTile(
                      title: d.name,
                      subtitle: d.host,
                      onTap: () => devices.select(d),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => devices.remove(d),
                      ),
                    ),
              ],
              _Header('Nearby', trailing: _scanning
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : null),
              if (nearby.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Looking for WLED devices on your Wi-Fi…',
                      style: TextStyle(color: GlyphColors.textMuted)),
                ),
              for (final d in nearby)
                _DeviceTile(
                  title: d.name,
                  subtitle: d.host,
                  onTap: () => devices.addAndSelect(d.host, d.name),
                  trailing: const Icon(Icons.add_circle_outline),
                ),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                OutlinedButton.icon(
                    onPressed: _addByIp,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Add by IP')),
                OutlinedButton.icon(
                    onPressed: _scanning ? null : _scan,
                    icon: const Icon(Icons.radar),
                    label: const Text('Scan network')),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _ActiveDeviceCard extends StatelessWidget {
  const _ActiveDeviceCard({required this.store});

  final DeviceStore store;

  @override
  Widget build(BuildContext context) {
    final info = store.info;
    final caps = store.caps;
    final d = store.selected!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: info != null ? GlyphColors.success : GlyphColors.danger),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(info?.name ?? d.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  onPressed: store.isLoading ? null : store.refresh,
                  icon: const Icon(Icons.refresh)),
            ]),
            if (info == null)
              Text(store.error ?? 'Connecting to ${d.host}…',
                  style: const TextStyle(color: GlyphColors.textMuted))
            else ...[
              const SizedBox(height: 8),
              _kv('Address', d.host),
              _kv('Firmware', 'WLED ${info.version} · ${info.arch.toUpperCase()}'),
              _kv('Size', info.matrixWidth != null
                  ? '${info.matrixWidth} × ${info.matrixHeight} (${info.ledCount} LEDs)'
                  : '${info.ledCount} LEDs (1D strip)'),
              if (info.signal != null)
                _kv('Wi-Fi', '${info.signal}% (${info.rssi} dBm)',
                    warn: info.signal! < 40),
              if ((info.signal ?? 100) < 40)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Weak signal: live streaming may stutter. Saved animations are unaffected.',
                    style: TextStyle(fontSize: 12, color: GlyphColors.warning),
                  ),
                ),
              if (info.fsTotalKb != null && info.fsUsedKb != null && info.fsTotalKb! > 0) ...[
                _kv('Storage', '${info.fsUsedKb} / ${info.fsTotalKb} KB used'),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: LinearProgressIndicator(
                    value: info.fsUsedKb! / info.fsTotalKb!,
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 6,
                  ),
                ),
              ],
              _kv('Saving to matrix', caps!.canPlayGifs ? 'Supported' : 'Not supported',
                  warn: !caps.canPlayGifs),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    AppScope.of(context).playback.playGenerator(TestPattern());
                    await GlyphActions.ensureStreaming(context);
                  },
                  icon: const Icon(Icons.screen_rotation_alt_outlined),
                  label: const Text('Orientation test'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _editLayout(context),
                  icon: const Icon(Icons.tune),
                  label: const Text('Layout'),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool warn = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
              width: 130,
              child: Text(k, style: const TextStyle(color: GlyphColors.textMuted))),
          Expanded(
              child: Text(v,
                  style: TextStyle(color: warn ? GlyphColors.warning : null))),
        ]),
      );

  void _editLayout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _LayoutEditor(store: store),
    );
  }
}

class _LayoutEditor extends StatefulWidget {
  const _LayoutEditor({required this.store});

  final DeviceStore store;

  @override
  State<_LayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends State<_LayoutEditor> {
  late MatrixLayout _l = widget.store.selected!.layout;

  Future<void> _apply(MatrixLayout l) async {
    setState(() => _l = l);
    final playback = AppScope.of(context).playback;
    await widget.store.updateLayout(l);
    if (playback.isStreaming) {
      await playback.startStreaming(widget.store.selected!.host, l);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Layout',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Text(
            'Only needed if the orientation test looks wrong. WLED\'s own 2D settings usually handle this.',
            style: TextStyle(color: GlyphColors.textMuted),
          ),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('0°')),
              ButtonSegment(value: 1, label: Text('90°')),
              ButtonSegment(value: 2, label: Text('180°')),
              ButtonSegment(value: 3, label: Text('270°')),
            ],
            selected: {_l.rotation},
            onSelectionChanged: (s) => _apply(MatrixLayout(
                rotation: s.first,
                flipX: _l.flipX,
                flipY: _l.flipY,
                serpentine: _l.serpentine)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mirror horizontally'),
            value: _l.flipX,
            onChanged: (v) => _apply(MatrixLayout(
                rotation: _l.rotation, flipX: v, flipY: _l.flipY, serpentine: _l.serpentine)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mirror vertically'),
            value: _l.flipY,
            onChanged: (v) => _apply(MatrixLayout(
                rotation: _l.rotation, flipX: _l.flipX, flipY: v, serpentine: _l.serpentine)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Zig-zag rows'),
            subtitle: const Text('Turn on if every other row looks reversed'),
            value: _l.serpentine,
            onChanged: (v) => _apply(MatrixLayout(
                rotation: _l.rotation, flipX: _l.flipX, flipY: _l.flipY, serpentine: v)),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Row(children: [
          Text(text.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: GlyphColors.textMuted)),
          const Spacer(),
          ?trailing,
        ]),
      );
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile(
      {required this.title, required this.subtitle, required this.onTap, this.trailing});

  final String title, subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: GlyphColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.grid_4x4, color: GlyphColors.primary),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: trailing,
            onTap: onTap,
          ),
        ),
      );
}
