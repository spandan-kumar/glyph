import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/devices.dart';
import '../../app/test_pattern.dart';
import '../../features/device/device_features.dart';
import '../../features/device/widgets/common.dart';
import '../../features/device/widgets/device_settings.dart';
import '../../wled/device.dart';
import '../../wled/layout.dart';
import '../actions.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../onboarding/onboarding_flow.dart';
import '../onboarding/orientation_fix.dart';
import '../scope.dart';

String sizeLabel(WledInfo info) =>
    info.hasMatrix ? '${info.matrixWidth}×${info.matrixHeight}' : '${info.ledCount} lights';

/// Switching between devices, adding one, playing on several together,
/// fixing orientation, renaming, WLED's own settings and the advanced details.
class YourMatrices extends StatelessWidget {
  const YourMatrices({
    super.key,
    required this.store,
    this.services = const SetupServices(),
    this.settingsView,
  });

  final DeviceStore store;
  final SetupServices services;

  /// Stands in for the settings web view in tests.
  final SettingsViewBuilder? settingsView;

  Future<void> _switchTo(BuildContext context, SavedDevice d) async {
    if (d.host == store.selected?.host) return;
    if (AppScope.of(context).playback.isStreaming) await GlyphActions.stopStreaming(context);
    await store.select(d);
  }

  @override
  Widget build(BuildContext context) {
    final selected = store.selected;
    final others = [for (final d in store.saved) if (d.host != selected?.host) d];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (final d in store.saved)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _MatrixChip(
                    name: d.name,
                    detail: d.host == selected?.host
                        ? (store.info != null ? sizeLabel(store.info!) : d.host)
                        : (store.peerInfo(d.host) != null ? sizeLabel(store.peerInfo(d.host)!) : d.host),
                    online: store.isOnline(d.host),
                    selected: d.host == selected?.host,
                    onTap: () => _switchTo(context, d),
                  ),
                ),
              _MatrixChip(
                name: 'Add a device',
                detail: 'Find another',
                add: true,
                onTap: () => MatrixSetupPage.open(context, services: services),
              ),
            ],
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 14),
          RowGroup(
            children: [
              if (store.isConnected)
                Row1(
                  leading: const Icon(Icons.screen_rotation_alt_rounded, color: Lb.text2, size: 20),
                  title: 'Fix orientation',
                  subtitle: 'If things look sideways or backwards',
                  trailing: const Icon(Icons.chevron_right_rounded, color: Lb.text3),
                  onTap: () => OrientationFixPage.open(context),
                ),
              if (store.isConnected)
                Row1(
                  leading: const Icon(Icons.edit_outlined, color: Lb.text2, size: 20),
                  title: 'Rename',
                  subtitle: store.info?.name ?? selected.name,
                  trailing: const Icon(Icons.chevron_right_rounded, color: Lb.text3),
                  onTap: () => _rename(context),
                ),
              if (store.isConnected)
                Row1(
                  leading: const Icon(Icons.settings_outlined, color: Lb.text2, size: 20),
                  title: 'Device settings',
                  subtitle: 'The full WLED setup, inside Glyph',
                  trailing: const Icon(Icons.chevron_right_rounded, color: Lb.text3),
                  onTap: () => DeviceSettingsPage.open(context, store, viewBuilder: settingsView),
                ),
              _Advanced(store: store),
            ],
          ),
        ],
        if (others.isNotEmpty && selected != null) ...[
          const SizedBox(height: 20),
          const MonoLabel('Play together'),
          const SizedBox(height: 6),
          Text(
            'Live animations also play on these, sized to fit each one.',
            style: LbType.small,
          ),
          const SizedBox(height: 10),
          _MirrorGroup(store: store, others: others),
        ],
      ],
    );
  }

  Future<void> _rename(BuildContext context) async {
    final current = store.info?.name ?? store.selected?.name ?? '';
    final name = await promptText(context, title: 'Name your device', initial: current, hint: 'Living room');
    if (name == null || name.isEmpty || name == current || !context.mounted) return;
    await guarded(context, () => store.renameOnDevice(name), done: 'Renamed to “$name”');
  }
}

class _MatrixChip extends StatelessWidget {
  const _MatrixChip({
    required this.name,
    required this.detail,
    required this.onTap,
    this.online,
    this.selected = false,
    this.add = false,
  });

  final String name, detail;
  final VoidCallback onTap;
  final bool? online;
  final bool selected, add;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Lb.raised : Lb.panel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Lb.rPanel),
      side: BorderSide(color: selected ? Lb.text2 : Lb.line),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Lb.rPanel),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (add)
                  const Icon(Icons.add_rounded, size: 18, color: Lb.text)
                else
                  StatusDot(on: online == true, color: Lb.ok),
                const Spacer(),
                if (selected) const MonoLabel('Now'),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.bodyStrong),
                Text(
                  online == false ? 'Offline' : detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LbType.mono.copyWith(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Other saved devices that mirror the live stream.
class _MirrorGroup extends StatelessWidget {
  const _MirrorGroup({required this.store, required this.others});

  final DeviceStore store;
  final List<SavedDevice> others;

  @override
  Widget build(BuildContext context) {
    final playback = AppScope.of(context).playback;
    final mirrors = store.mirrorHosts;
    final failed = playback.failedHosts;
    return RowGroup(
      children: [
        for (final d in others)
          Row1(
            leading: StatusDot(on: store.isOnline(d.host) == true),
            title: d.name,
            subtitle: failed.contains(d.host)
                ? 'Couldn\'t reach it'
                : store.peerInfo(d.host) != null
                ? sizeLabel(store.peerInfo(d.host)!)
                : store.isOnline(d.host) == false
                ? 'Offline'
                : d.host,
            trailing: Switch(
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
      ],
    );
  }
}

/// Layout switches, firmware, address and forgetting the device.
class _Advanced extends StatefulWidget {
  const _Advanced({required this.store});

  final DeviceStore store;

  @override
  State<_Advanced> createState() => _AdvancedState();
}

class _AdvancedState extends State<_Advanced> {
  bool _open = false;

  DeviceStore get store => widget.store;

  Future<void> _layout(MatrixLayout l) => applyLayout(context, l);

  @override
  Widget build(BuildContext context) {
    final d = store.selected!;
    final info = store.info;
    final caps = store.caps;
    final l = d.layout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row1(
          leading: const Icon(Icons.tune_rounded, color: Lb.text2, size: 20),
          title: 'Advanced',
          subtitle: 'Address, firmware, layout',
          trailing: AnimatedRotation(
            turns: _open ? 0.25 : 0,
            duration: Lb.fast,
            child: const Icon(Icons.chevron_right_rounded, color: Lb.text3),
          ),
          onTap: () => setState(() => _open = !_open),
        ),
        AnimatedSize(
          duration: Lb.medium,
          curve: Lb.ease,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _kv('Address', d.host),
                      if (info != null) ...[
                        _kv('Firmware', 'WLED ${info.version} · ${info.arch.toUpperCase()}'),
                        _kv('Size', info.hasMatrix
                            ? '${info.matrixWidth} × ${info.matrixHeight} · ${info.ledCount} lights'
                            : '${info.ledCount} lights in a line'),
                        if (info.signal != null) _kv('Wi-Fi', '${info.signal}% (${info.rssi} dBm)'),
                        _kv('Saving', caps?.canPlayGifs == true ? 'Works on this device' : 'Not on this device'),
                        if (!info.versionAtLeast(16))
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Note(
                              color: Lb.phosphor,
                              lit: true,
                              text: 'WLED 16 lets your device save animations and run routines. Update '
                                  'in Device settings → Security & Updates, or at install.wled.me.',
                            ),
                          ),
                      ],
                      const SizedBox(height: 14),
                      const MonoLabel('Layout'),
                      const SizedBox(height: 8),
                      Text(
                        'Only needed if things still look wrong after “Fix orientation”.',
                        style: LbType.small,
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<int>(
                        style: squareSegments,
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 0, label: Text('0°')),
                          ButtonSegment(value: 1, label: Text('90°')),
                          ButtonSegment(value: 2, label: Text('180°')),
                          ButtonSegment(value: 3, label: Text('270°')),
                        ],
                        selected: {l.rotation % 4},
                        onSelectionChanged: (s) => _layout(l.copyWith(rotation: s.first)),
                      ),
                      _switch('Mirror left–right', l.flipX, (v) => _layout(l.copyWith(flipX: v))),
                      _switch('Mirror top–bottom', l.flipY, (v) => _layout(l.copyWith(flipY: v))),
                      _switch('Zig-zag rows', l.serpentine, (v) => _layout(l.copyWith(serpentine: v)),
                          hint: 'Turn on if every other row looks reversed'),
                      if (store.isConnected) ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () async {
                            AppScope.of(context).playback.playGenerator(TestPattern());
                            await GlyphActions.ensureStreaming(context);
                          },
                          child: const Text('Show test pattern'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Lb.danger),
                        onPressed: () => _forget(context, d),
                        child: const Text('Forget this device'),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 92, child: MonoLabel(k)),
        Expanded(child: Text(v, style: LbType.mono.copyWith(color: Lb.text))),
      ],
    ),
  );

  Widget _switch(String label, bool v, ValueChanged<bool> on, {String? hint}) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: LbType.body),
              if (hint != null) Text(hint, style: LbType.small),
            ],
          ),
        ),
        Switch(value: v, onChanged: on),
      ],
    ),
  );

  Future<void> _forget(BuildContext context, SavedDevice d) async {
    final ok = await confirm(
      context,
      title: 'Forget ${d.name}?',
      message: 'It\'s removed from Glyph only. Everything saved on the device stays.',
      action: 'Forget',
    );
    if (!ok || !context.mounted) return;
    if (AppScope.of(context).playback.isStreaming) await GlyphActions.stopStreaming(context);
    unawaited(store.remove(d));
  }
}
