import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/background.dart';
import '../../app/playback.dart';
import '../../engine/palette.dart';
import '../../ui/actions.dart';
import '../../ui/scope.dart';
import '../../ui/design/parts.dart';
import '../../ui/design/toggle.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/led_loop.dart';
import '../../ui/make/studio_kit.dart';
import '../../ui/make/tool_session.dart';
import '../../ui/widgets/led_matrix_view.dart';
import 'audio_engine.dart';
import 'visualizers.dart';

// Remembered for the session so revisiting the screen keeps the choices.
bool _keepAwake = false;
bool _wantBackground = false;

/// Music visualiser: pick a look, tune how it reacts, play it on the matrix.
class AudioScreen extends StatefulWidget {
  const AudioScreen({super.key, this.engine});

  /// Defaults to [AudioEngine.shared]; tests pass one with a fake mic.
  final AudioEngine? engine;

  @override
  State<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen>
    with WidgetsBindingObserver, ToolSession<AudioScreen> {
  late final AudioEngine _engine = widget.engine ?? AudioEngine.shared;
  late final List<AudioVisualizer> _visuals = audioVisualizers(_engine);
  late AudioVisualizer _selected = _visuals.first;
  late Palette _palette = paletteById(_selected.defaultPalette);
  bool _inited = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine.acquire(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final playback = AppScope.of(context).playback;
    _engine.bandCount = playback.frame.width.clamp(8, 64);
    final g = playback.generator;
    if (_isOurs(playback) && g != null) {
      _selected = _visuals.firstWhere((v) => v.id == g.id, orElse: () => _selected);
      _palette = playback.palette;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.release(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The screen's own hold is only for previews; a streaming visualiser
    // keeps its own hold via _MicFollower.
    if (state == AppLifecycleState.resumed) {
      _engine.refreshPermission();
      _engine.acquire(this);
    } else if (state == AppLifecycleState.paused) {
      _engine.release(this);
    }
  }

  // Background on: the visualiser keeps dancing after the screen closes,
  // until it's stopped from the notification or something else plays.
  @override
  bool get keepAfterLeaving => _wantBackground && BackgroundStreaming.isRunning;

  bool _isOurs(PlaybackController p) {
    final g = p.generator;
    return g is AudioVisualizer && identical(g.feed, _engine);
  }

  bool _playingSelected(PlaybackController p) =>
      _isOurs(p) && p.isPlaying && p.generator!.id == _selected.id;

  void _select(AudioVisualizer v) {
    HapticFeedback.selectionClick();
    final playback = AppScope.of(context).playback;
    final wasPlaying = _isOurs(playback) && playback.isPlaying;
    setState(() {
      _selected = v;
      _palette = paletteById(v.defaultPalette);
    });
    if (wasPlaying) {
      playback.playGenerator(v);
      toolOwns(v);
      playback.setPalette(_palette);
    }
  }

  void _setPalette(Palette p) {
    // The swatch clicks itself.
    setState(() => _palette = p);
    final playback = AppScope.of(context).playback;
    if (_isOurs(playback)) playback.setPalette(p);
  }

  Future<void> _play() async {
    final s = AppScope.of(context);
    // Starting to stream changes the device; a local preview is just a commit.
    s.devices.isConnected ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    s.playback.playGenerator(_selected);
    toolPlays(_selected);
    s.playback.setPalette(_palette);
    _MicFollower.bind(_engine, s.playback);
    await GlyphActions.ensureStreaming(context);
    _engine.bandCount = s.playback.frame.width.clamp(8, 64);
    if (_wantBackground && s.playback.isStreaming && mounted) await _startBackground();
  }

  Future<void> _stop() async {
    HapticFeedback.selectionClick();
    AppScope.of(context).playback.pause();
    await GlyphActions.stopStreaming(context);
  }

  Future<void> _startBackground() async {
    final s = AppScope.of(context);
    final playback = s.playback, devices = s.devices;
    final ok = await BackgroundStreaming.start(
      title: 'Glyph is streaming to ${devices.info?.name ?? 'your device'}',
      text: '${_selected.name} · reacting to sound',
      microphone: _engine.access == MicAccess.granted,
      onStop: () {
        playback.pause();
        playback.stopStreaming();
        devices.client?.exitLive().catchError((_) {});
      },
    );
    BackgroundStreaming.watch(playback);
    if (!ok && mounted) studioToast(context, 'Couldn\'t keep running in the background.');
  }

  Future<void> _toggleBackground(bool on) async {
    _wantBackground = on;
    setState(() {});
    final playback = AppScope.of(context).playback;
    if (!on) {
      await BackgroundStreaming.stop();
    } else if (_isOurs(playback) && playback.isPlaying && playback.isStreaming) {
      await _startBackground();
    }
  }

  Future<void> _toggleAwake(bool on) async {
    setState(() => _keepAwake = on);
    await _setWakelock(on);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback, devices = scope.devices;
    return StudioScaffold(
      title: 'Music',
      body: ListenableBuilder(
        listenable: Listenable.merge([_engine, playback, devices, BackgroundStreaming.running]),
        builder: (context, _) {
          final live = _playingSelected(playback);
          final playing = _isOurs(playback) && playback.isPlaying;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 32),
            children: [
              if (_engine.status
                  case AudioStatus.needsPermission || AudioStatus.blocked || AudioStatus.failed)
                _PermissionCard(engine: _engine, owner: this),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: live
                      ? LedMatrixView(
                          frame: playback.frame,
                          repaint: playback.frameTick,
                          glow: true,
                          bezel: true,
                          borderRadius: Lb.rControl,
                        )
                      : LedLoop(
                          key: ValueKey('big-${_selected.id}'),
                          generator: _selected,
                          palette: _palette,
                          seed: _selected.id.hashCode,
                          width: playback.frame.width,
                          height: playback.frame.height,
                          glow: true,
                          bezel: true,
                          borderRadius: Lb.rControl,
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Center(child: _Listening(engine: _engine)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: studioCtaStyle,
                      onPressed: live && playback.isStreaming ? null : _play,
                      icon: const Icon(Icons.play_arrow_sharp),
                      label: Text(
                        live
                            ? (playback.isStreaming ? 'Showing on device' : 'Showing here')
                            : devices.isConnected
                            ? 'Show on device'
                            : 'Show here',
                      ),
                    ),
                  ),
                  if (playing) ...[
                    const SizedBox(width: 10),
                    IconButton.outlined(
                      tooltip: 'Stop',
                      style: IconButton.styleFrom(
                          side: Lb.hairline,
                          minimumSize: const Size(Lb.cta, Lb.cta),
                          shape: studioShape),
                      onPressed: _stop,
                      icon: const Icon(Icons.stop_sharp),
                    ),
                  ],
                ],
              ),
              if (!devices.isConnected)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No device connected · showing it here on your phone',
                    textAlign: TextAlign.center,
                    style: LbType.small.copyWith(color: Lb.text3),
                  ),
                ),
              const SizedBox(height: 22),
              StudioGroup(
                label: 'Look',
                padding: const EdgeInsets.all(12),
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.8,
                  children: [
                    for (final v in _visuals)
                      _VisualTile(
                        visual: v,
                        selected: v.id == _selected.id,
                        onTap: () => _select(v),
                      ),
                  ],
                ),
              ),
              StudioGroup(
                label: 'Colours',
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final p in palettes)
                        StudioSwatch(
                          label: p.name,
                          gradient: LinearGradient(colors: [for (final c in p.swatch) Color(0xFF000000 | c)]),
                          selected: p.id == _palette.id,
                          size: 40,
                          onTap: () => _setPalette(p),
                        ),
                    ],
                  ),
                ),
              ),
              StudioGroup(
                label: 'Sound',
                child: StudioKnobRow(
                  knobs: [
                    StudioKnob(
                      label: 'Sensitivity',
                      value: _engine.sensitivity,
                      valueText: '${(_engine.sensitivity * 100).round()}%',
                      onChanged: (v) => _engine.sensitivity = v,
                    ),
                    StudioKnob(
                      label: 'Smoothing',
                      value: _engine.smoothing,
                      valueText: '${(_engine.smoothing * 100).round()}%',
                      onChanged: (v) => _engine.smoothing = v,
                    ),
                    StudioKnob(
                      label: 'Range',
                      value: _engine.range,
                      valueText: _engine.range < 0.34
                          ? 'Bass'
                          : _engine.range > 0.66
                          ? 'Full'
                          : 'Mid',
                      onChanged: (v) => _engine.range = v,
                    ),
                  ],
                ),
              ),
              StudioGroup(
                label: 'While playing',
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Column(
                  children: [
                    LbToggleTile(
                      title: 'Keep screen on',
                      value: _keepAwake,
                      onChanged: _toggleAwake,
                    ),
                    if (BackgroundStreaming.supported)
                      LbToggleTile(
                        title: 'Keep running in background',
                        subtitle: _wantBackground && BackgroundStreaming.isRunning
                            ? 'Running · stop it from the notification'
                            : devices.isConnected
                            ? 'Keeps the device dancing with the screen off'
                            : 'Connect a device to use this',
                        value: _wantBackground,
                        onChanged: devices.isConnected ? _toggleBackground : null,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _setWakelock(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } catch (_) {
    // No platform implementation (tests, unsupported OS): nothing to hold.
  }
}

/// Holds the mic for as long as playback runs one of our visualisers, so the
/// matrix keeps reacting after this screen is closed, and lets go (mic,
/// wake lock) once something else plays.
class _MicFollower {
  _MicFollower(this.engine, this.playback) {
    playback.addListener(_onChange);
    _onChange();
  }

  static _MicFollower? _current;

  final AudioEngine engine;
  final PlaybackController playback;

  static void bind(AudioEngine engine, PlaybackController playback) {
    final c = _current;
    if (c != null && identical(c.engine, engine) && identical(c.playback, playback)) return;
    c?._detach();
    _current = _MicFollower(engine, playback);
  }

  void _onChange() {
    final g = playback.generator;
    final ours = g is AudioVisualizer && identical(g.feed, engine);
    if (ours && playback.isRendering) {
      engine.acquire(this);
    } else {
      engine.release(this);
    }
    if (!ours) {
      _detach();
      if (_keepAwake) _setWakelock(false);
    }
  }

  void _detach() {
    playback.removeListener(_onChange);
    engine.release(this);
    if (identical(_current, this)) _current = null;
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.engine, required this.owner});

  final AudioEngine engine;
  final Object owner;

  @override
  Widget build(BuildContext context) {
    final (title, body, action, onPressed) = switch (engine.status) {
      AudioStatus.blocked => (
        'Microphone is off for Glyph',
        'Turn on the microphone permission in Settings, then come back here.',
        'Open settings',
        engine.openSettings,
      ),
      AudioStatus.failed => (
        'Couldn\'t start the microphone',
        engine.error ?? 'Another app may be using it.',
        'Try again',
        () async {
          await engine.release(owner);
          await engine.acquire(owner);
        },
      ),
      _ => (
        'Let Glyph hear the music',
        'The visualiser listens through your microphone and reacts to what it hears. '
            'Sound is analysed live on your phone; nothing is recorded, saved or sent anywhere.',
        'Allow microphone',
        engine.requestPermission,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: LbPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mic_none_sharp, color: Lb.text),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: LbType.heading)),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: LbType.small),
            const SizedBox(height: 14),
            FilledButton(style: studioCtaStyle, onPressed: onPressed, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

/// "Listening…" with a little LED meter: a beat LED that flashes in time and
/// a row of LEDs that light with the input level.
class _Listening extends StatelessWidget {
  const _Listening({required this.engine});

  final AudioEngine engine;

  @override
  Widget build(BuildContext context) {
    final accent = readAccent(context);
    final still = Lb.reduceMotion(context);
    return ValueListenableBuilder<AudioFeatures>(
      valueListenable: engine.features,
      builder: (context, f, _) {
        final on = engine.isListening;
        final level = on ? ((f.inputDb + 66) / 60).clamp(0.0, 1.0) : 0.0;
        final label = !on
            ? 'Mic off'
            : f.silent
            ? 'Quiet · play some music'
            : f.bpm > 0
            ? 'Listening · ${f.bpm.round()} BPM'
            : 'Listening…';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Restarts on every beat, so it flashes in time; still under
            // reduced motion.
            TweenAnimationBuilder<double>(
              key: ValueKey(f.beatCount),
              tween: Tween(begin: f.beatCount > 0 && !still ? 1 : 0, end: 0),
              duration: const Duration(milliseconds: 260),
              builder: (context, beat, _) => CustomPaint(
                // The painter draws the beat LED, a gap, then _meter LEDs.
                size: const Size(_LevelLeds.cells * 10.0, 10),
                painter: _LevelLeds(level, beat, on ? accent : Lb.text3),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LbType.label.copyWith(color: on ? Lb.text2 : Lb.text3)),
            ),
          ],
        );
      },
    );
  }
}

class _LevelLeds extends CustomPainter {
  _LevelLeds(this.level, this.beat, this.color);

  final double level, beat;
  final Color color;

  static const _meter = 5;

  /// Beat LED, a gap and the meter, in cells.
  static const cells = _meter + 2;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.height, r = cell * 0.36, y = size.height / 2;
    // Beat LED, a gap, then the level meter.
    canvas.drawCircle(Offset(cell / 2, y), r, Paint()..color = Color.lerp(Lb.ledOff, color, 0.25 + 0.75 * beat)!);
    final lit = (level * _meter).round();
    for (var i = 0; i < _meter; i++) {
      canvas.drawCircle(Offset(cell * (i + 2) + cell / 2, y), r,
          Paint()..color = i < lit ? color : Lb.ledOff);
    }
  }

  @override
  bool shouldRepaint(_LevelLeds old) => old.level != level || old.beat != beat || old.color != color;
}

class _VisualTile extends StatelessWidget {
  const _VisualTile({required this.visual, required this.selected, required this.onTap});

  final AudioVisualizer visual;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${visual.name}: ${visual.blurb}',
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: Lb.fast,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Lb.rControl),
                border: Border.all(
                  color: selected ? Lb.text : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: LedLoop(
                  generator: visual,
                  seed: visual.id.hashCode,
                  palette: paletteById(visual.defaultPalette),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            visual.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LbType.small.copyWith(color: selected ? Lb.text : Lb.text2),
          ),
        ],
      ),
    ),
  );
}

@visibleForTesting
void debugResetAudioScreen() {
  _MicFollower._current?._detach();
  _keepAwake = false;
  _wantBackground = false;
}
