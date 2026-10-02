import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/playback.dart';
import '../../ui/actions.dart';
import '../../ui/scope.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/led_matrix_view.dart';
import 'core/game.dart';
import 'core/game_generator.dart';
import 'high_scores.dart';
import 'widgets/controls.dart';

/// Full-screen controller: live mirror of the matrix on top, controls below.
class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.def});

  final GameDef def;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  PlaybackController? _playback;
  late GameGenerator _gen;
  int _best = 0;
  bool _newBest = false;

  // Snapshot of the game for the HUD; refreshed only when it changes.
  int _score = 0;
  bool _over = false, _paused = false;
  String? _status;

  Game? get _game => _gen.view?.game;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_playback == null) _start();
  }

  void _start() {
    final scope = AppScope.of(context);
    final pb = _playback = scope.playback;
    final cur = pb.generator;
    if (cur is GameGenerator && cur.def.id == widget.def.id && cur.view != null &&
        !cur.view!.game.isOver) {
      // Coming back to a paused game.
      _gen = cur;
      if (!pb.isPlaying) pb.resume();
    } else {
      _gen = GameGenerator(widget.def, liveFrame: () => pb.frame);
      final caps = scope.devices.caps;
      if (caps != null) pb.resize(caps.width, caps.height);
      pb.playGenerator(_gen);
      _gen.newGame(pb.frame.width, pb.frame.height);
    }
    _gen
      ..liveFrame = (() => pb.frame)
      ..onEvent = _onEvent;
    pb.frameTick.addListener(_sync);
    WidgetsBinding.instance.addObserver(this);
    _wakelock(true);
    _loadBest();
    final g = _game!;
    _score = g.score;
    _paused = g.paused;
    _status = g.status;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) GlyphActions.ensureStreaming(context);
    });
  }

  String get _bestKey => HighScores.key(widget.def.id, _gen.options);

  Future<void> _loadBest() async {
    final b = await HighScores.get(_bestKey);
    if (!mounted) return;
    _gen.best = b;
    _gen.view?.best = b;
    setState(() => _best = b);
  }

  void _wakelock(bool on) {
    // No plugin in tests and some platforms; keeping the screen on is optional.
    try {
      unawaited((on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {}));
    } catch (_) {}
  }

  void _sync() {
    final g = _game;
    if (g == null || !mounted) return;
    if (g.score == _score && g.isOver == _over && g.paused == _paused && g.status == _status) {
      return;
    }
    setState(() {
      _score = g.score;
      _over = g.isOver;
      _paused = g.paused;
      _status = g.status;
    });
  }

  void _onEvent(GameEvent e) {
    switch (e) {
      case GameEvent.move || GameEvent.bounce || GameEvent.flap:
        HapticFeedback.selectionClick();
      case GameEvent.score:
        HapticFeedback.lightImpact();
      case GameEvent.hit || GameEvent.clear:
        HapticFeedback.mediumImpact();
      case GameEvent.level:
        HapticFeedback.heavyImpact();
      case GameEvent.over:
        HapticFeedback.heavyImpact();
        _submit();
    }
  }

  Future<void> _submit() async {
    final s = _game?.score ?? 0;
    final record = await HighScores.submit(_bestKey, s);
    if (!record || !mounted) return;
    setState(() {
      _newBest = true;
      _best = s;
    });
  }

  void _restart() {
    final pb = _playback!;
    _gen.best = _best;
    _gen.newGame(pb.frame.width, pb.frame.height);
    if (!pb.isPlaying) pb.resume();
    _newBest = false;
    _sync();
  }

  void _setPaused(bool p) {
    final g = _game;
    if (g == null || g.isOver) return;
    g.paused = p;
    // Let go of any held keys so nothing auto-repeats on resume.
    for (final k in GameKey.values) {
      g.release(k);
    }
    _sync();
  }

  void _toggleOption(String key) {
    final o = {..._gen.options};
    if (!o.remove(key)) o.add(key);
    _gen.options = o;
    _restart();
    _loadBest();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _setPaused(true);
  }

  @override
  void dispose() {
    _playback?.frameTick.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    final g = _game;
    if (g != null && !g.isOver) g.paused = true;
    _gen.onEvent = null;
    _wakelock(false);
    super.dispose();
  }

  void _press(GameKey k) => _game?.press(k);
  void _release(GameKey k) => _game?.release(k);

  @override
  Widget build(BuildContext context) {
    final pb = _playback!;
    final def = widget.def;
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(def.name),
        actions: [
          if (def.options.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.tune),
              onSelected: _toggleOption,
              itemBuilder: (_) => [
                for (final (key, label) in def.options)
                  CheckedPopupMenuItem(
                      value: key, checked: _gen.options.contains(key), child: Text(label)),
              ],
            ),
          IconButton(
            tooltip: _paused ? 'Resume' : 'Pause',
            onPressed: _over ? null : () => _setPaused(!_paused),
            icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(children: [
            _Hud(score: _score, best: max(_best, _newBest ? _score : 0), status: _status),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height * 0.34),
              child: ListenableBuilder(
                listenable: pb,
                builder: (context, _) => Center(
                  child: LedMatrixView(
                      frame: pb.frame, repaint: pb.frameTick, glow: true, borderRadius: 20),
                ),
              ),
            ),
            const SizedBox(height: 6),
            ListenableBuilder(
              listenable: pb,
              builder: (context, _) => Text(
                pb.isStreaming ? 'Live on your matrix' : 'Preview · connect a matrix to play big',
                style: TextStyle(
                    fontSize: 12,
                    color: pb.isStreaming ? GlyphColors.accent : GlyphColors.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _over
                  ? _Panel(
                      title: 'Game over',
                      lines: [
                        'Score $_score',
                        if (_newBest) 'New best!',
                      ],
                      highlight: _newBest,
                      primary: ('Play again', _restart),
                      secondary: ('Back to games', () => Navigator.of(context).maybePop()),
                    )
                  : _paused
                      ? _Panel(
                          title: 'Paused',
                          lines: [def.hint],
                          primary: ('Resume', () => _setPaused(false)),
                          secondary: ('Restart', _restart),
                        )
                      : _controls(),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _controls() {
    final def = widget.def;
    return LayoutBuilder(builder: (context, c) {
      final unit = min(72.0, min(c.maxHeight / 3, c.maxWidth / 4.6));
      switch (def.controls) {
        case Controls.dpad:
          return SwipeArea(
            onSwipe: _press,
            child: Container(
              decoration: BoxDecoration(
                color: GlyphColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: GlyphColors.outline),
              ),
              child: Center(child: DPad(onDown: _press, size: unit)),
            ),
          );
        case Controls.blocks:
          return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            DPad(
                onDown: _press,
                onUp: _release,
                size: unit,
                upIcon: Icons.rotate_right_rounded),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              PadButton(
                width: unit * 1.1,
                height: unit * 1.1,
                label: 'drop',
                color: GlyphColors.surface,
                onDown: () => _press(GameKey.b),
                child: const Icon(Icons.vertical_align_bottom_rounded),
              ),
              SizedBox(height: unit * 0.3),
              PadButton(
                width: unit * 1.3,
                height: unit * 1.3,
                label: 'rotate',
                color: GlyphColors.primary.withValues(alpha: 0.35),
                onDown: () => _press(GameKey.a),
                child: const Icon(Icons.rotate_right_rounded),
              ),
            ]),
          ]);
        case Controls.paddle:
          return DragPad(
            vertical: _game?.pointerVertical ?? false,
            label: def.hint,
            onDown: () => _press(GameKey.a),
            onPosition: (v) => _game?.pointer(v),
          );
        case Controls.tap:
          return TapPad(onTap: () => _press(GameKey.a));
        case Controls.steer:
          final rotated = _gen.view?.rotated ?? false;
          Widget side(GameKey k, IconData icon) => Expanded(
                child: PadButton(
                  width: double.infinity,
                  height: double.infinity,
                  radius: 24,
                  label: k.name,
                  onDown: () => _press(k),
                  child: Icon(icon, size: 48),
                ),
              );
          return Row(children: [
            side(GameKey.left,
                rotated ? Icons.arrow_upward_rounded : Icons.arrow_back_rounded),
            const SizedBox(width: 12),
            side(GameKey.right,
                rotated ? Icons.arrow_downward_rounded : Icons.arrow_forward_rounded),
          ]);
        case Controls.shooter:
          Widget hold(GameKey k, IconData icon) => PadButton(
                width: unit * 1.2,
                height: unit * 1.2,
                radius: unit * 0.36,
                label: k.name,
                onDown: () => _press(k),
                onUp: () => _release(k),
                child: Icon(icon),
              );
          return Row(children: [
            hold(GameKey.left, Icons.keyboard_arrow_left_rounded),
            SizedBox(width: unit * 0.25),
            hold(GameKey.right, Icons.keyboard_arrow_right_rounded),
            const Spacer(),
            PadButton(
              width: unit * 1.6,
              height: unit * 1.6,
              label: 'fire',
              color: GlyphColors.danger.withValues(alpha: 0.35),
              onDown: () => _press(GameKey.a),
              child: const Text('FIRE'),
            ),
          ]);
      }
    });
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.score, required this.best, this.status});

  final int score, best;
  final String? status;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(
        fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: GlyphColors.textMuted);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('SCORE', style: label),
        Text('$score',
            style: const TextStyle(
                fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
      ]),
      const SizedBox(width: 16),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(status ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: GlyphColors.textMuted)),
        ),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Text('BEST', style: label),
        Text('$best',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: GlyphColors.warning)),
      ]),
    ]);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.lines,
    required this.primary,
    required this.secondary,
    this.highlight = false,
  });

  final String title;
  final List<String> lines;
  final (String, VoidCallback) primary, secondary;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: GlyphColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: highlight ? GlyphColors.warning : GlyphColors.outline),
        ),
        child: SingleChildScrollView(
          child: Column(children: [
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final l in lines)
              Text(l,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: l == 'New best!' ? GlyphColors.warning : GlyphColors.textMuted,
                      fontWeight: l == 'New best!' ? FontWeight.w700 : FontWeight.w400)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(onPressed: primary.$2, child: Text(primary.$1)),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: secondary.$2, child: Text(secondary.$1)),
          ]),
        ),
      );
}
