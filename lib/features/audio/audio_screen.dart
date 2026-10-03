import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/background.dart';
import '../../app/playback.dart';
import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../../ui/actions.dart';
import '../../ui/scope.dart';
import '../../ui/design/parts.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/studio_kit.dart';
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

class _AudioScreenState extends State<AudioScreen> with WidgetsBindingObserver {
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

  bool _isOurs(PlaybackController p) {
    final g = p.generator;
    return g is AudioVisualizer && identical(g.feed, _engine);
  }

  bool _playingSelected(PlaybackController p) =>
      _isOurs(p) && p.isPlaying && p.generator!.id == _selected.id;

  void _select(AudioVisualizer v) {
    final playback = AppScope.of(context).playback;
    final wasPlaying = _isOurs(playback) && playback.isPlaying;
    setState(() {
      _selected = v;
      _palette = paletteById(v.defaultPalette);
    });
    if (wasPlaying) {
      playback.playGenerator(v);
      playback.setPalette(_palette);
    }
  }

  void _setPalette(Palette p) {
    setState(() => _palette = p);
    final playback = AppScope.of(context).playback;
    if (_isOurs(playback)) playback.setPalette(p);
  }

  Future<void> _play() async {
    final s = AppScope.of(context);
    s.playback.playGenerator(_selected);
    s.playback.setPalette(_palette);
    _MicFollower.bind(_engine, s.playback);
    await GlyphActions.ensureStreaming(context);
    _engine.bandCount = s.playback.frame.width.clamp(8, 64);
    if (_wantBackground && s.playback.isStreaming && mounted) await _startBackground();
  }

  Future<void> _stop() async {
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
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t keep running in the background.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
                      : _VisualPreview(
                          key: ValueKey('big-${_selected.id}'),
                          generator: _selected,
                          palette: _palette,
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
                      onPressed: live && playback.isStreaming ? null : _play,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        live
                            ? (playback.isStreaming ? 'Playing on device' : 'Playing (preview)')
                            : devices.isConnected
                            ? 'Play on device'
                            : 'Play',
                      ),
                    ),
                  ),
                  if (playing) ...[
                    const SizedBox(width: 10),
                    IconButton.outlined(
                      tooltip: 'Stop',
                      style: IconButton.styleFrom(
                          side: Lb.hairline, minimumSize: const Size(48, 48), shape: studioShape),
                      onPressed: _stop,
                      icon: const Icon(Icons.stop_rounded),
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
                        _Swatch(
                          palette: p,
                          selected: p.id == _palette.id,
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Keep screen on', style: LbType.body),
                      value: _keepAwake,
                      onChanged: _toggleAwake,
                    ),
                    if (BackgroundStreaming.supported)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Keep running in background', style: LbType.body),
                        subtitle: Text(
                          BackgroundStreaming.isRunning
                              ? 'Running · stop it from the notification'
                              : devices.isConnected
                              ? 'Keeps the device dancing with the screen off'
                              : 'Connect a device to use this',
                          style: LbType.small,
                        ),
                        value: BackgroundStreaming.isRunning || _wantBackground,
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
    if (ours && playback.isPlaying) {
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
                Icon(Icons.mic_none_rounded, color: readAccent(context)),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: LbType.heading)),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: LbType.small),
            const SizedBox(height: 14),
            FilledButton(onPressed: onPressed, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

/// "Listening…" with a ring that fills with the input level and flashes on
/// each beat.
class _Listening extends StatelessWidget {
  const _Listening({required this.engine});

  final AudioEngine engine;

  @override
  Widget build(BuildContext context) {
    final accent = readAccent(context);
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
            // Restarts on every beat, so it flashes in time.
            TweenAnimationBuilder<double>(
              key: ValueKey(f.beatCount),
              tween: Tween(begin: f.beatCount > 0 ? 1 : 0, end: 0),
              duration: const Duration(milliseconds: 260),
              builder: (context, beat, _) => CustomPaint(
                size: const Size.square(22),
                painter: _LevelRing(level, beat, on ? accent : Lb.text3),
              ),
            ),
            const SizedBox(width: 10),
            Text(label.toUpperCase(), style: LbType.label.copyWith(color: on ? Lb.text2 : Lb.text3)),
          ],
        );
      },
    );
  }
}

class _LevelRing extends CustomPainter {
  _LevelRing(this.level, this.beat, this.color);

  final double level, beat;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, stroke..color = Lb.line);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi / 2, 2 * pi * level, false,
        stroke..color = color);
    canvas.drawCircle(c, 2.5 + 2 * beat, Paint()..color = Color.lerp(Lb.line, color, 0.3 + 0.7 * beat)!);
  }

  @override
  bool shouldRepaint(_LevelRing old) => old.level != level || old.beat != beat || old.color != color;
}

/// Runs a visualiser locally for the picker and the big preview.
class _VisualPreview extends StatefulWidget {
  const _VisualPreview({
    super.key,
    required this.generator,
    required this.palette,
    this.width = 16,
    this.height = 16,
    this.glow = false,
    this.bezel = false,
    this.borderRadius = Lb.rTile,
  });

  final Generator generator;
  final Palette palette;
  final int width, height;
  final bool glow, bezel;
  final double borderRadius;

  @override
  State<_VisualPreview> createState() => _VisualPreviewState();
}

class _VisualPreviewState extends State<_VisualPreview> with SingleTickerProviderStateMixin {
  late Frame _frame;
  late EffectInstance _fx;
  late Params _params;
  late final Ticker _ticker;
  final _tick = ValueNotifier(0);
  Duration _last = Duration.zero;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _setup();
    _ticker = createTicker(_onTick)..start();
  }

  void _setup() {
    final w = widget.width.clamp(1, 128), h = widget.height.clamp(1, 128);
    _frame = Frame(w, h);
    _fx = widget.generator.create(w, h, widget.generator.id.hashCode);
    _params = Params.defaultsFor(widget.generator);
  }

  @override
  void didUpdateWidget(_VisualPreview old) {
    super.didUpdateWidget(old);
    if (old.generator.id != widget.generator.id ||
        old.width != widget.width ||
        old.height != widget.height) {
      _setup();
    }
  }

  void _onTick(Duration elapsed) {
    if ((elapsed - _last).inMilliseconds < 33) return;
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _t += dt;
    _fx.render(_frame, _t, dt, _params, widget.palette);
    _tick.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LedMatrixView(
    frame: _frame,
    repaint: _tick,
    glow: widget.glow,
    bezel: widget.bezel,
    borderRadius: widget.borderRadius,
  );
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
                  color: selected ? readAccent(context) : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: _VisualPreview(
                  generator: visual,
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

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.selected, required this.onTap});

  final Palette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Tooltip(
      message: palette.name,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Lb.fast,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Lb.rTile),
            gradient: LinearGradient(
              colors: [for (final c in palette.swatch) Color(0xFF000000 | c)],
            ),
            border: Border.all(color: selected ? Lb.text : Lb.line, width: selected ? 2.5 : 1),
          ),
        ),
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
