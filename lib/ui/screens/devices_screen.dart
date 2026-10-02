import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/devices.dart';
import '../../app/test_pattern.dart';
import '../../features/device/device_features.dart';
import '../../features/device/widgets/common.dart';
import '../../wled/device.dart';
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
  bool _wired = false;

  @override
  void initState() {
    super.initState();
    _sub = _discovery.devices.listen(_onFound);
    _discovery.start().catchError((_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final scope = AppScope.of(context);
    // Idempotent; main() normally does this already.
    DeviceFeatures.attach(devices: scope.devices, playback: scope.playback);
    unawaited(scope.devices.probeSaved());
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

  Future<void> _switchTo(DeviceStore devices, SavedDevice d) async {
    final playback = AppScope.of(context).playback;
    if (playback.isStreaming) await GlyphActions.stopStreaming(context);
    await devices.select(d);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final devices = scope.devices;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([devices, scope.playback]),
        builder: (context, _) {
          final savedHosts = devices.saved.map((d) => d.host).toSet();
          final nearby = _found.values.where((d) => !savedHosts.contains(d.host));
          final others = [for (final d in devices.saved) if (d.host != devices.selected?.host) d];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              const Text('Matrix',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              if (devices.saved.length > 1) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final d in devices.saved)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: _OnlineDot(online: devices.isOnline(d.host)),
                            label: Text(d.name),
                            selected: d.host == devices.selected?.host,
                            onSelected: (_) => d.host == devices.selected?.host
                                ? null
                                : _switchTo(devices, d),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (devices.selected != null) _ActiveDeviceCard(store: devices),
              if (others.isNotEmpty && devices.selected != null) _MirrorGroup(store: devices, others: others),
              if (others.isNotEmpty) ...[
                const _Header('Saved'),
                for (final d in others)
                  _DeviceTile(
                    title: d.name,
                    subtitle: _peerSubtitle(devices, d),
                    online: devices.isOnline(d.host),
                    onTap: () => _switchTo(devices, d),
                    trailing: IconButton(
                      tooltip: 'Forget',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirm(context,
                            title: 'Forget ${d.name}?',
                            message: 'It is removed from Glyph only; nothing on the matrix changes.',
                            action: 'Forget');
                        if (ok) await devices.remove(d);
                      },
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

  static String _peerSubtitle(DeviceStore devices, SavedDevice d) {
    final info = devices.peerInfo(d.host);
    if (info == null) {
      return devices.isOnline(d.host) == false ? '${d.host} · offline' : d.host;
    }
    return '${d.host} · ${_sizeLabel(info)}';
  }
}

String _sizeLabel(WledInfo info) => info.hasMatrix
    ? '${info.matrixWidth}×${info.matrixHeight}'
    : '${info.ledCount} LEDs';

class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.online});

  final bool? online;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: switch (online) {
            true => GlyphColors.success,
            false => GlyphColors.danger,
            null => GlyphColors.textMuted,
          },
        ),
      );
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
              _OnlineDot(online: info != null ? true : (store.isLoading ? null : false)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(info?.name ?? d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              if (info != null)
                IconButton(
                  tooltip: 'Rename on the matrix',
                  onPressed: () => _rename(context, info.name),
                  icon: const Icon(Icons.drive_file_rename_outline),
                ),
              IconButton(
                  tooltip: 'Refresh',
                  onPressed: store.isLoading ? null : store.refresh,
                  icon: const Icon(Icons.refresh)),
            ]),
            if (info == null)
              Text(store.error ?? 'Connecting to ${d.host}…',
                  style: const TextStyle(color: GlyphColors.textMuted))
            else ...[
              const SizedBox(height: 8),
              _kv('Address', d.host),
              _kv('Firmware', 'WLED ${info.version} · ${info.arch.toUpperCase()}',
                  warn: !info.versionAtLeast(16)),
              _kv('Size', info.matrixWidth != null
                  ? '${info.matrixWidth} × ${info.matrixHeight} (${info.ledCount} LEDs)'
                  : '${info.ledCount} LEDs (1D strip)'),
              if (info.signal != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    const SizedBox(
                        width: 130,
                        child: Text('Wi-Fi', style: TextStyle(color: GlyphColors.textMuted))),
                    _SignalBars(percent: info.signal!),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${info.signal}% (${info.rssi} dBm)',
                          style: TextStyle(
                              color: info.signal! < 40 ? GlyphColors.warning : null)),
                    ),
                  ]),
                ),
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
                    value: (info.fsUsedKb! / info.fsTotalKb!).clamp(0.0, 1.0),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 6,
                  ),
                ),
              ],
              _kv('Saving to matrix', caps!.canPlayGifs ? 'Supported' : 'Not supported',
                  warn: !caps.canPlayGifs),
              if (!info.versionAtLeast(16))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: InfoBanner(
                    icon: Icons.system_update_alt,
                    color: GlyphColors.warning,
                    text: 'WLED 16 adds GIF playback and schedule editing. Update from the WLED '
                        'web page (Settings → Security & Updates), or flash it from a computer at '
                        'install.wled.me.',
                  ),
                ),
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

  Future<void> _rename(BuildContext context, String current) async {
    final name = await promptText(context,
        title: 'Rename matrix', initial: current, hint: 'Living room');
    if (name == null || name.isEmpty || name == current || !context.mounted) return;
    await guarded(context, () => store.renameOnDevice(name), done: 'Renamed to "$name"');
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

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final bars = percent >= 75 ? 4 : percent >= 50 ? 3 : percent >= 25 ? 2 : 1;
    final color = bars <= 1 ? GlyphColors.danger : bars == 2 ? GlyphColors.warning : GlyphColors.success;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 4,
            height: 5.0 + i * 3,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i < bars ? color : GlyphColors.outline,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }
}

/// Other saved matrices that mirror the live stream, each scaled to its own
/// size and using its own layout.
class _MirrorGroup extends StatelessWidget {
  const _MirrorGroup({required this.store, required this.others});

  final DeviceStore store;
  final List<SavedDevice> others;

  @override
  Widget build(BuildContext context) {
    final playback = AppScope.of(context).playback;
    final mirrors = store.mirrorHosts;
    final failed = playback.failedHosts;
    final live = playback.streamingHosts.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Header('Mirror group',
          trailing: playback.isStreaming && live > 1
              ? Text('Streaming to $live matrices',
                  style: const TextStyle(fontSize: 12, color: GlyphColors.success))
              : null),
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text(
          'Live animations play on these too, scaled to each one\'s size.',
          style: TextStyle(fontSize: 13, color: GlyphColors.textMuted),
        ),
      ),
      for (final d in others)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: GlyphColors.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: _OnlineDot(online: store.isOnline(d.host)),
              title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                failed.contains(d.host)
                    ? 'Couldn\'t reach it'
                    : store.peerInfo(d.host) != null
                        ? _sizeLabel(store.peerInfo(d.host)!)
                        : store.isOnline(d.host) == false
                            ? 'Offline'
                            : d.host,
                style: TextStyle(
                    color: failed.contains(d.host) ? GlyphColors.warning : GlyphColors.textMuted),
              ),
              value: mirrors.contains(d.host),
              onChanged: (v) async {
                await store.setMirror(d.host, v);
                await DeviceFeatures.syncMirrors(devices: store, playback: playback);
                if (!v) {
                  try {
                    await store.exitLiveOn(d.host);
                  } catch (_) {}
                }
              },
            ),
          ),
        ),
    ]);
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
    // Restarts the whole group (mirrors included) with the new layout.
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
            onSelectionChanged: (s) => _apply(_l.copyWith(rotation: s.first)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mirror horizontally'),
            value: _l.flipX,
            onChanged: (v) => _apply(_l.copyWith(flipX: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mirror vertically'),
            value: _l.flipY,
            onChanged: (v) => _apply(_l.copyWith(flipY: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Zig-zag rows'),
            subtitle: const Text('Turn on if every other row looks reversed'),
            value: _l.serpentine,
            onChanged: (v) => _apply(_l.copyWith(serpentine: v)),
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
      {required this.title,
      required this.subtitle,
      required this.onTap,
      this.trailing,
      this.online});

  final String title, subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool? online;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: GlyphColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: Icon(Icons.grid_4x4,
                color: online == false ? GlyphColors.textMuted : GlyphColors.primary),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: trailing,
            onTap: onTap,
          ),
        ),
      );
}
