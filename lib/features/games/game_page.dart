import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/devices.dart';
import '../../app/playback.dart';
import '../../ui/actions.dart';
import '../../ui/scope.dart';
import '../../ui/tune/tune_screen.dart' show PowerKey;
import '../../ui/design/parts.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/studio_kit.dart';
import '../../ui/make/tool_session.dart';
import '../../ui/widgets/led_matrix_view.dart';
import 'core/game.dart';
import 'core/game_generator.dart';
import 'high_scores.dart';
import 'widgets/controls.dart';

/// Full-screen gamepad, with a phone-only thumbnail when no device streams.
class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.def});

  final GameDef def;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver, ToolSession<GamePage> {
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
    // Leaving ends the game and stops it on the device (see ToolSession).
    toolPlays(_gen);
    _gen
      ..liveFrame = (() => pb.frame)
      ..onEvent = _onEvent;
    pb.renderTick.addListener(_sync);
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
        HapticFeedback.mediumImpact();
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
    _playback?.renderTick.removeListener(_sync);
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
    final devices = AppScope.of(context).devices;
    final def = widget.def;
    return StudioScaffold(
      title: def.name,
      actions: [
          if (def.options.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.tune_sharp),
              shape: studioMenuShape,
              style: studioIconStyle,
              onSelected: (k) {
                HapticFeedback.selectionClick();
                _toggleOption(k);
              },
              itemBuilder: (_) => [
                for (final (key, label) in def.options)
                  CheckedPopupMenuItem(
                      value: key, checked: _gen.options.contains(key), child: Text(label)),
              ],
            ),
      ],
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 16),
          child: Column(children: [
            ListenableBuilder(
              listenable: Listenable.merge([pb, devices]),
              builder: (context, _) => _Hud(
                playback: pb,
                onDevice: _onDevice(pb, devices),
                score: _score,
                best: max(_best, _newBest ? _score : 0),
                status: _status,
                paused: _paused,
                over: _over,
                onPause: () {
                  HapticFeedback.selectionClick();
                  _setPaused(!_paused);
                },
              ),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([pb, devices]),
              builder: (context, _) => _onDevice(pb, devices)
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _PhoneOnlyStrip(off: devices.isConnected && devices.isOn == false),
                    ),
            ),
            const SizedBox(height: 16),
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
      final w = c.maxWidth, h = c.maxHeight;
      const g = 12.0;
      Widget key(GameKey k, IconData icon, double width, double height,
          String caption, String semantics, {bool held = false}) => PadButton(
            width: width,
            height: height,
            caption: caption,
            semanticsLabel: semantics,
            onDown: () => _press(k),
            onUp: held ? () => _release(k) : null,
            child: Icon(icon),
          );
      Widget cluster(Widget row) => Column(children: [
            Text(def.hint, style: LbType.small.copyWith(color: Lb.text3),
                textAlign: TextAlign.center),
            const Spacer(),
            row,
          ]);
      switch (def.controls) {
        case Controls.dpad:
          return SwipePad(onDirection: _press);
        case Controls.blocks:
          // Two thumb halves across the full width; movement left, actions right.
          final half = (w - 2 * g) / 2, quarter = (half - g) / 2;
          final tall = (h * 0.32).clamp(96.0, 180.0), short = (h * 0.13).clamp(64.0, 88.0);
          return cluster(Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(mainAxisSize: MainAxisSize.min, children: [
                key(GameKey.down, Icons.keyboard_double_arrow_down_sharp,
                    half, short, 'Soft drop', 'Soft drop', held: true),
                const SizedBox(height: g),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  key(GameKey.left, Icons.arrow_back_sharp,
                      quarter, tall, 'Left', 'Move left', held: true),
                  const SizedBox(width: g),
                  key(GameKey.right, Icons.arrow_forward_sharp,
                      quarter, tall, 'Right', 'Move right', held: true),
                ]),
              ]),
              Column(mainAxisSize: MainAxisSize.min, children: [
                key(GameKey.b, Icons.vertical_align_bottom_sharp,
                    half, short, 'Drop', 'Drop'),
                const SizedBox(height: g),
                key(GameKey.a, Icons.rotate_right_sharp,
                    half, tall, 'Rotate', 'Rotate'),
              ]),
            ],
          ));
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
          Widget side(GameKey k, IconData icon, String caption, String semantics) => Expanded(
                child: PadButton(
                  width: double.infinity,
                  height: h,
                  radius: Lb.rPanel,
                  caption: caption,
                  semanticsLabel: semantics,
                  onDown: () => _press(k),
                  child: Icon(icon, size: 56),
                ),
              );
          return Row(children: [
            side(GameKey.left,
                rotated ? Icons.arrow_upward_sharp : Icons.arrow_back_sharp,
                rotated ? 'Up' : 'Left lane', rotated ? 'Steer up' : 'Steer left'),
            const SizedBox(width: g),
            side(GameKey.right,
                rotated ? Icons.arrow_downward_sharp : Icons.arrow_forward_sharp,
                rotated ? 'Down' : 'Right lane', rotated ? 'Steer down' : 'Steer right'),
          ]);
        case Controls.shooter:
          final half = (w - 2 * g) / 2, quarter = (half - g) / 2;
          final tall = (h * 0.42).clamp(120.0, 240.0);
          return cluster(Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                key(GameKey.left, Icons.arrow_back_sharp,
                    quarter, tall, 'Left', 'Move left', held: true),
                const SizedBox(width: g),
                key(GameKey.right, Icons.arrow_forward_sharp,
                    quarter, tall, 'Right', 'Move right', held: true),
              ]),
              key(GameKey.a, Icons.gps_fixed_sharp, half, tall, 'Fire', 'Fire'),
            ],
          ));
      }
    });
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.playback,
    required this.onDevice,
    required this.score,
    required this.best,
    required this.paused,
    required this.over,
    required this.onPause,
    this.status,
  });

  final PlaybackController playback;
  final bool onDevice;
  final int score, best;
  final String? status;
  final bool paused, over;
  final VoidCallback onPause;

  static const _figures = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      double textWidth(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }
      final bestWidth = max(textWidth('BEST', LbType.label),
          textWidth('$best', LbType.title.copyWith(fontFeatures: _figures)));
      final scoreWidth = max(0.0, c.maxWidth - bestWidth - 68 -
          (onDevice ? 0 : 68));
      return SizedBox(
        height: 64,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (!onDevice) ...[
            SizedBox.square(
              dimension: 56,
              child: LedMatrixView(
                frame: playback.frame,
                repaint: playback.frameTick,
                glow: false,
                bezel: true,
                borderRadius: Lb.rControl,
              ),
            ),
            const SizedBox(width: 12),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: scoreWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MonoLabel('Score'),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$score', style: LbType.display.copyWith(fontFeatures: _figures)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(status ?? '', textAlign: TextAlign.center,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.small),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const MonoLabel('Best'),
              Text('$best', style: LbType.title.copyWith(fontFeatures: _figures)),
            ],
          ),
          const SizedBox(width: 12),
          PadButton(
            width: 56,
            height: 56,
            semanticsLabel: paused ? 'Resume game' : 'Pause game',
            enabled: !over,
            onDown: onPause,
            child: Icon(paused ? Icons.play_arrow_sharp : Icons.pause_sharp),
          ),
        ]),
      );
    });
  }
}

/// Whether the game is actually showing on the device: streaming to it and
/// it isn't switched off. Otherwise the phone shows a small copy instead.
bool _onDevice(PlaybackController pb, DeviceStore devices) => pb.isStreaming && devices.isOn != false;

class _PhoneOnlyStrip extends StatelessWidget {
  const _PhoneOnlyStrip({required this.off});

  /// The device is connected but switched off: offer to wake it.
  final bool off;

  @override
  Widget build(BuildContext context) => Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Lb.panel,
          border: const Border.fromBorderSide(Lb.hairline),
          borderRadius: BorderRadius.circular(Lb.rControl),
        ),
        child: Row(children: [
          const StatusDot(on: false),
          const SizedBox(width: 10),
          Expanded(child: Text(off ? 'Your device is off' : 'Playing on your phone only', style: LbType.small)),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, Lb.touch)),
            onPressed: () => off ? PowerKey.set(context, true) : goToMatrix(context),
            child: Text(off ? 'Turn on' : 'Connect'),
          ),
        ]),
      );
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
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Lb.panel,
        borderRadius: BorderRadius.circular(Lb.rPanel),
        border: Border.all(color: highlight ? Lb.text : Lb.line),
      ),
      child: Column(children: [
        Flexible(
          fit: FlexFit.tight,
          child: SingleChildScrollView(
            child: Column(children: [
              Text(title, style: LbType.title),
              const SizedBox(height: 6),
              for (final l in lines)
                Text(l,
                    textAlign: TextAlign.center,
                    style: l == 'New best!'
                        ? LbType.bodyStrong.copyWith(color: Lb.text)
                        : LbType.body.copyWith(color: Lb.text2)),
            ]),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: Lb.cta,
          child: FilledButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              primary.$2();
            },
            child: Text(primary.$1),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(0, Lb.touch)),
          onPressed: () {
            HapticFeedback.selectionClick();
            secondary.$2();
          },
          child: Text(secondary.$1),
        ),
      ]),
    );
  }
}
