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
import '../../ui/theme.dart';
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
      title: 'Glyph is streaming to ${devices.info?.name ?? 'your matrix'}',
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
    return Scaffold(
      appBar: AppBar(title: const Text('Music visualiser')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_engine, playback, devices, BackgroundStreaming.running]),
        builder: (context, _) {
          final live = _playingSelected(playback);
          final playing = _isOurs(playback) && playback.isPlaying;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
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
                          borderRadius: 20,
                        )
                      : _VisualPreview(
                          key: ValueKey('big-${_selected.id}'),
                          generator: _selected,
                          palette: _palette,
                          width: playback.frame.width,
                          height: playback.frame.height,
                          glow: true,
                          borderRadius: 20,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              _InputMeter(engine: _engine),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: live && playback.isStreaming ? null : _play,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        live
                            ? (playback.isStreaming ? 'Playing on matrix' : 'Playing (preview)')
                            : devices.isConnected
                            ? 'Play on matrix'
                            : 'Play',
                      ),
                    ),
                  ),
                  if (playing) ...[
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: 'Stop',
                      onPressed: _stop,
                      icon: const Icon(Icons.stop_rounded),
                    ),
                  ],
                ],
              ),
              if (!devices.isConnected)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'No matrix connected · previewing on the phone',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: GlyphColors.textMuted),
                  ),
                ),
              const SizedBox(height: 16),
              _Section(
                title: 'Visualiser',
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
              _Section(
                title: 'Colours',
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
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
              _Section(
                title: 'Sound',
                child: Column(
                  children: [
                    _SliderRow(
                      label: 'Sensitivity',
                      value: _engine.sensitivity,
                      onChanged: (v) => _engine.sensitivity = v,
                    ),
                    _SliderRow(
                      label: 'Smoothing',
                      value: _engine.smoothing,
                      onChanged: (v) => _engine.smoothing = v,
                    ),
                    _SliderRow(
                      label: 'Range',
                      value: _engine.range,
                      onChanged: (v) => _engine.range = v,
                      ends: ('Bass', 'Full'),
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'While playing',
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Keep screen on'),
                      value: _keepAwake,
                      onChanged: _toggleAwake,
                    ),
                    if (BackgroundStreaming.supported)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Keep running in background'),
                        subtitle: Text(
                          BackgroundStreaming.isRunning
                              ? 'Running · stop it from the notification'
                              : devices.isConnected
                              ? 'Keeps the matrix reacting with the screen off'
                              : 'Connect a matrix to use this',
                          style: const TextStyle(fontSize: 12),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GlyphColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GlyphColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic_none_rounded, color: GlyphColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: GlyphColors.textMuted, height: 1.35)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }
}

class _InputMeter extends StatelessWidget {
  const _InputMeter({required this.engine});

  final AudioEngine engine;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioFeatures>(
      valueListenable: engine.features,
      builder: (context, f, _) {
        final on = engine.isListening;
        final fill = on ? ((f.inputDb + 66) / 60).clamp(0.0, 1.0) : 0.0;
        final label = !on
            ? 'Mic off'
            : f.silent
            ? 'Quiet · play some music'
            : f.bpm > 0
            ? '${f.bpm.round()} BPM'
            : 'Listening';
        return Row(
          children: [
            const Icon(Icons.mic_none_rounded, size: 18, color: GlyphColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    Container(height: 8, color: GlyphColors.outline),
                    FractionallySizedBox(
                      widthFactor: fill,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              GlyphColors.success,
                              fill > 0.85 ? GlyphColors.danger : GlyphColors.accent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Restarts on every beat, so it flashes in time.
            TweenAnimationBuilder<double>(
              key: ValueKey(f.beatCount),
              tween: Tween(begin: f.beatCount > 0 ? 1 : 0, end: 0),
              duration: const Duration(milliseconds: 260),
              builder: (context, v, _) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(GlyphColors.outline, GlyphColors.primary, v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 128,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: GlyphColors.textMuted),
              ),
            ),
          ],
        );
      },
    );
  }
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
    this.borderRadius = 12,
  });

  final Generator generator;
  final Palette palette;
  final int width, height;
  final bool glow;
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
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? GlyphColors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Center(
                child: _VisualPreview(
                  generator: visual,
                  palette: paletteById(visual.defaultPalette),
                  borderRadius: 10,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            visual.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? GlyphColors.text : GlyphColors.textMuted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.onChanged, this.ends});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final (String, String)? ends;

  @override
  Widget build(BuildContext context) {
    final e = ends;
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(label, style: const TextStyle(color: GlyphColors.textMuted)),
        ),
        if (e != null)
          Text(e.$1, style: const TextStyle(fontSize: 11, color: GlyphColors.textMuted)),
        Expanded(
          child: Slider(value: value, onChanged: onChanged),
        ),
        if (e != null)
          Text(e.$2, style: const TextStyle(fontSize: 11, color: GlyphColors.textMuted)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    // A Material (not a coloured box) so switch tiles keep their ink.
    child: Material(
      color: GlyphColors.surfaceHigh,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: GlyphColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
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
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [for (final c in palette.swatch) Color(0xFF000000 | c)],
            ),
            border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 3),
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
