import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/devices.dart';
import '../../app/playback.dart';
import '../../engine/frame.dart';
import '../../features/device/boot_intro.dart';
import '../../features/device/device_features.dart';
import '../../features/device/device_manager.dart';
import '../../features/device/widgets/common.dart';
import '../../features/device/widgets/controls.dart';
import '../../features/device/widgets/device_settings.dart';
import '../../features/device/widgets/kept.dart';
import '../../features/device/widgets/routines.dart';
import '../../features/device/widgets/shows.dart';
import '../../features/device/widgets/storage.dart';
import '../../wled/device.dart';
import '../actions.dart';
import '../community/glyph_menu.dart';
import '../design/parts.dart';
import '../design/stage.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../onboarding/onboarding_flow.dart';
import '../onboarding/setup_clips.dart';
import '../scope.dart';
import '../widgets/led_matrix_view.dart';
import 'your_matrices.dart';

/// The Device hub (UX.md J4): the panel, its controls, and what lives on it —
/// Saved, Shows, Routines, Storage — plus switching and setting up devices.
class MatrixScreen extends StatefulWidget {
  const MatrixScreen({
    super.key,
    @visibleForTesting this.services = const SetupServices(),
    @visibleForTesting this.settingsView,
  });

  /// Discovery used by "Add a device" / "Connect your device".
  final SetupServices services;

  /// Stands in for the "WLED firmware settings" web view in tests.
  final SettingsViewBuilder? settingsView;

  @override
  State<MatrixScreen> createState() => _MatrixScreenState();
}

class _MatrixScreenState extends State<MatrixScreen> {
  DeviceManager? _manager;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    final store = scope.devices;
    if (_manager?.store != store) {
      _manager?.dispose();
      _manager = DeviceManager(store);
      // Idempotent; main() normally does this already.
      DeviceFeatures.attach(devices: store, playback: scope.playback);
      unawaited(store.probeSaved());
    }
  }

  @override
  void dispose() {
    _manager?.dispose();
    super.dispose();
  }

  /// Plays something saved on the device (live streaming would override it).
  Future<void> _play(int id) async {
    if (AppScope.of(context).playback.isStreaming) await GlyphActions.stopStreaming(context);
    await _manager!.apply(id);
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
          if (devices.selected == null) {
            return _EmptyState(onConnect: () => MatrixSetupPage.open(context, services: widget.services));
          }
          final connected = devices.isConnected;
          if (connected) manager.syncHost();
          return RefreshIndicator(
            onRefresh: () async {
              await devices.refresh();
              if (devices.isConnected) await manager.load();
            },
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 128),
              children: [
                _Header(store: devices),
                if (!connected)
                  _Unreachable(store: devices)
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Lb.gutter, 24, Lb.gutter, 0),
                    child: _NowShowing(store: devices, manager: manager, playback: scope.playback),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Lb.gutter, 24, Lb.gutter, 0),
                    child: HardwareControls(store: devices),
                  ),
                  PanelSection(
                    label: 'Saved',
                    padding: const EdgeInsets.fromLTRB(Lb.gutter, 32, Lb.gutter, 0),
                    trailing: manager.isLoading && manager.isLoaded
                        ? const _BusyLed()
                        : null,
                    child: KeptSection(manager: manager, store: devices, onPlay: _play),
                  ),
                  PanelSection(
                    label: 'Shows',
                    padding: const EdgeInsets.fromLTRB(Lb.gutter, 32, Lb.gutter, 0),
                    child: ShowsSection(manager: manager, store: devices, onPlay: _play),
                  ),
                  PanelSection(
                    label: 'Routines',
                    padding: const EdgeInsets.fromLTRB(Lb.gutter, 32, Lb.gutter, 0),
                    child: RoutinesSection(manager: manager),
                  ),
                  PanelSection(
                    label: 'Storage',
                    padding: const EdgeInsets.fromLTRB(Lb.gutter, 32, Lb.gutter, 0),
                    child: StorageSection(manager: manager, store: devices),
                  ),
                ],
                PanelSection(
                  label: 'Your devices',
                  padding: const EdgeInsets.fromLTRB(Lb.gutter, 32, Lb.gutter, 0),
                  child: YourMatrices(
                    store: devices,
                    services: widget.services,
                    settingsView: widget.settingsView,
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

/// Name, status and a mono line of facts.
class _Header extends StatelessWidget {
  const _Header({required this.store});

  final DeviceStore store;

  @override
  Widget build(BuildContext context) {
    final info = store.info;
    final name = info?.name ?? store.selected!.name;
    final connected = store.isConnected;
    final weak = (info?.signal ?? 100) < 40;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Lb.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: MonoLabel('Device')),
              StatusDot(on: connected, size: 7),
              const SizedBox(width: 8),
              MonoLabel(connected ? 'Connected' : (store.isLoading ? 'Connecting…' : 'Not reachable')),
            ],
          ),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: LbType.display)),
            const SizedBox(width: 12),
            const GlyphMenuKey(),
          ]),
          if (info != null) ...[
            const SizedBox(height: 10),
            Text(factsLine(info), style: LbType.mono),
            if (weak)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Weak Wi-Fi here — live animations may stutter. Saved ones play fine.',
                  style: LbType.small.copyWith(color: Lb.phosphor),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "16×16 · WLED 16.0.1 · Wi-Fi 18%".
String factsLine(WledInfo info) => [
  sizeLabel(info),
  'WLED ${info.version}',
  if (info.signal != null) 'Wi-Fi ${info.signal}%',
].join(' · ');

/// The Stage: a mirror of what the device is showing right now.
class _NowShowing extends StatelessWidget {
  const _NowShowing({required this.store, required this.manager, required this.playback});

  final DeviceStore store;
  final DeviceManager manager;
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final caps = store.caps;
    final w = caps?.width ?? fallbackSize, h = caps?.height ?? fallbackSize;
    final on = store.isOn != false;
    final kept = store.presetId == null ? null : manager.preset(store.presetId!);
    final String kind, title;
    Widget stage;
    if (playback.isStreaming) {
      kind = 'Live from your phone';
      title = playback.item?.title ?? playback.generator?.name ?? 'Live';
      stage = Stage(frame: playback.frame, repaint: playback.frameTick, maxWidth: 300);
    } else if (!on) {
      kind = 'Resting';
      title = 'Off';
      stage = Opacity(opacity: 0.5, child: Stage(frame: Frame(w, h), maxWidth: 300));
    } else {
      final intro = manager.bootIntro;
      final startingUp = (store.playlistRunning && store.playlistId != null && intro.isSystem(store.playlistId!)) ||
          (!store.playlistRunning && kept != null && kept.id == intro.intro?.id);
      kind = startingUp
          ? 'Starting up'
          : store.playlistRunning
          ? 'Playing a show'
          : (kept != null ? 'Saved on your device' : 'On its own');
      title = startingUp
          ? BootIntro.presetName
          : store.playlistRunning && store.playlistId != null
          ? manager.presetName(store.playlistId!)
          : kept?.name ?? (store.playlistRunning ? 'A show' : 'Its own light');
      final gif = kept?.gifName;
      stage = gif != null && manager.hasFile(gif)
          ? _GifStage(key: ValueKey(gif.toLowerCase()), manager: manager, gif: gif, aspect: w / h)
          : Stage(frame: _glowFrame(w, h, kept?.primaryColor), maxWidth: 300);
    }
    return Column(
      children: [
        stage,
        const SizedBox(height: 14),
        MonoLabel(kind),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.title),
            ),
            if (store.playlistRunning && !playback.isStreaming)
              IconButton(
                tooltip: 'Next in the show',
                icon: const Icon(Icons.skip_next_sharp, color: Lb.text2),
                onPressed: () => guarded(context, () async {
                  await store.client?.nextInPlaylist();
                  await Future<void>.delayed(const Duration(milliseconds: 400));
                  await store.refreshState();
                }),
              ),
          ],
        ),
      ],
    );
  }

  /// A soft glow in the saved item's colour when we have no picture of it.
  static Frame _glowFrame(int w, int h, int? color) {
    final f = Frame(w, h);
    final c = color == null || color == 0 ? 0xFFB547 : color;
    final cx = (w - 1) / 2, cy = (h - 1) / 2;
    final r2 = (w * w + h * h) / 10;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final d = ((x - cx) * (x - cx) + (y - cy) * (y - cy)) / r2;
        final k = (1 - d).clamp(0.0, 1.0) * 0.55;
        if (k > 0.04) f.set(x, y, scaleColorInt(c, k));
      }
    }
    return f;
  }
}

class _GifStage extends StatelessWidget {
  const _GifStage({super.key, required this.manager, required this.gif, required this.aspect});

  final DeviceManager manager;
  final String gif;
  final double aspect;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: AspectRatio(
        aspectRatio: aspect,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Lb.bezel,
            borderRadius: BorderRadius.circular(Lb.rControl),
            border: Border.all(color: Lb.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Lb.rTile),
              child: GifThumb(manager: manager, name: gif),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.store});

  final DeviceStore store;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Lb.gutter, 24, Lb.gutter, 0),
    child: LbPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            store.isLoading ? 'Saying hello…' : 'Can\'t reach it right now',
            style: LbType.heading,
          ),
          const SizedBox(height: 6),
          Text(
            'Check it\'s plugged in and on the same Wi-Fi as your phone.',
            style: LbType.small,
          ),
          if (!store.isLoading) ...[
            const SizedBox(height: 14),
            FilledButton(onPressed: store.refresh, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}

/// No device yet: a dim panel waiting to be lit.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onConnect});

  final VoidCallback onConnect;

  static final _dim = () {
    final f = helloClip(16, 16).frames.first.copy();
    for (var i = 0; i < f.rgb.length; i++) {
      f.rgb[i] = (f.rgb[i] * 0.16).round();
    }
    return f;
  }();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(Lb.gutter, 32, Lb.gutter, 128),
    children: [
      const Row(children: [Expanded(child: MonoLabel('Device')), GlyphMenuKey()]),
      const SizedBox(height: 20),
      Center(
        child: SizedBox(
          width: 220,
          child: LedMatrixView(frame: _dim, bezel: true, borderRadius: Lb.rControl),
        ),
      ),
      const SizedBox(height: 36),
      // A notch under display size so the headline holds one line on a phone.
      Text('Connect your device', textAlign: TextAlign.center, style: LbType.display.copyWith(fontSize: 34)),
      const SizedBox(height: 12),
      Text(
        'Plug in your WLED panel and we\'ll find it on your Wi-Fi. It takes a few seconds.',
        textAlign: TextAlign.center,
        style: LbType.body.copyWith(color: Lb.text2),
      ),
      const SizedBox(height: 28),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        onPressed: onConnect,
        child: const Text('Connect your device'),
      ),
      const SizedBox(height: 20),
      Center(
        child: TextButton(
          onPressed: () => requestDisplaySupport(context),
          child: const Text('Not WLED? Ask for your display'),
        ),
      ),
    ],
  );
}

/// A small LED blinking while the device is being read (instead of a
/// round Material spinner).
class _BusyLed extends StatefulWidget {
  const _BusyLed();

  @override
  State<_BusyLed> createState() => _BusyLedState();
}

class _BusyLedState extends State<_BusyLed> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    child: StatusDot(on: true, color: accentOf(context)),
  );
}
