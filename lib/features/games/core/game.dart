import 'dart:math';

import '../../../engine/frame.dart';
import 'digits.dart';

/// Logical buttons. Each game maps them to its own actions.
enum GameKey { left, right, up, down, a, b }

/// Things worth a haptic tick or a UI refresh.
enum GameEvent { move, score, bounce, hit, clear, level, flap, over }

/// How the phone presents a game's controls.
enum Controls { dpad, blocks, paddle, tap, steer, shooter }

typedef GameBuilder = Game Function(
    int width, int height, int seed, bool demo, Set<String> options);

class GameDef {
  const GameDef({
    required this.id,
    required this.name,
    required this.blurb,
    required this.controls,
    required this.build,
    this.hint = '',
    this.options = const [],
    this.rotateWide = false,
  });

  final String id;
  final String name;
  final String blurb;
  final String hint;
  final Controls controls;
  final GameBuilder build;

  /// Boolean toggles as (key, label).
  final List<(String, String)> options;

  /// Plays sideways on matrices wider than tall (e.g. a 32×8 strip).
  final bool rotateWide;
}

/// Pure game state. Deterministic for a given seed, input sequence and dt
/// sequence, so it's unit-testable without Flutter.
abstract class Game {
  Game(this.width, this.height, int seed, {this.demo = false}) : rng = Random(seed);

  final int width;
  final int height;
  final Random rng;

  /// Attract mode: [think] drives the inputs.
  final bool demo;

  int score = 0;
  bool paused = false;
  double time = 0;
  double overTime = 0;
  bool _over = false;
  void Function(GameEvent e)? onEvent;

  bool get isOver => _over;

  /// Short extra HUD text for the phone, e.g. "Level 2".
  String? get status => null;

  /// Whether a drag controller should follow the vertical axis.
  bool get pointerVertical => false;

  void update(double dt);
  void draw(Frame f);
  void think(double dt) {}
  void press(GameKey k) {}
  void release(GameKey k) {}

  /// Absolute control position, 0..1 along the paddle axis.
  void pointer(double v) {}

  void emit(GameEvent e) => onEvent?.call(e);

  void endGame() {
    if (_over) return;
    _over = true;
    overTime = 0;
    emit(GameEvent.over);
  }

  void tick(double dt) {
    if (paused) return;
    if (_over) {
      overTime += dt;
      return;
    }
    time += dt;
    if (demo) think(dt);
    update(dt);
  }

  /// Length of the game-over dissolve before the score shows.
  static const overFx = 1.0;

  void render(Frame f) {
    draw(f);
    if (!_over) return;
    // A red flash, then the field dissolves from the top down.
    final p = (overTime / overFx).clamp(0.0, 1.0);
    final flash = max(0.0, 1 - overTime / 0.35);
    final cut = p * height;
    for (var y = 0; y < height; y++) {
      final keep = y < cut ? 0.1 : 1 - 0.5 * p;
      for (var x = 0; x < width; x++) {
        var c = scaleColor(f.get(x, y), keep);
        if (flash > 0) c = addColors(c, rgb((140 * flash).toInt(), 0, 0));
        f.set(x, y, c);
      }
    }
  }
}

/// Fits a [Game] onto a real matrix: integer upscaling on big panels,
/// rotation for wide strips, and the pause / score overlays.
class GameView {
  GameView(this.def, this.width, this.height,
      {required this.seed, this.demo = false, this.options = const {}}) {
    _build();
  }

  final GameDef def;
  final int width;
  final int height;
  final bool demo;
  final Set<String> options;
  int seed;

  late Game game;
  late bool rotated;
  late int scale;
  late int _ox, _oy;
  late Frame _buf;
  /// Record to beat; a score that matches it shows gold at game over.
  int? best;
  void Function(GameEvent e)? _onEvent;

  set onEvent(void Function(GameEvent e)? f) {
    _onEvent = f;
    game.onEvent = f;
  }

  void _build() {
    rotated = def.rotateWide && width > height;
    final lw = rotated ? height : width, lh = rotated ? width : height;
    scale = max(1, min(lw, lh) ~/ 16);
    final gw = max(4, lw ~/ scale), gh = max(4, lh ~/ scale);
    game = def.build(gw, gh, seed, demo, options)..onEvent = _onEvent;
    _ox = (lw - gw * scale) ~/ 2;
    _oy = (lh - gh * scale) ~/ 2;
    _buf = Frame(gw, gh);
  }

  void restart() {
    seed++;
    _build();
  }

  void tick(double dt) {
    game.tick(dt);
    if (demo && game.isOver && game.overTime > 3) restart();
  }

  void render(Frame out) {
    final g = game;
    g.render(_buf);
    final direct = !rotated && scale == 1 && out.width == _buf.width && out.height == _buf.height;
    if (direct) {
      out.rgb.setAll(0, _buf.rgb);
    } else {
      for (var fy = 0; fy < out.height; fy++) {
        for (var fx = 0; fx < out.width; fx++) {
          final lx = rotated ? fy : fx, ly = rotated ? out.width - 1 - fx : fy;
          final dx = lx - _ox, dy = ly - _oy;
          final gx = dx < 0 ? -1 : dx ~/ scale, gy = dy < 0 ? -1 : dy ~/ scale;
          out.set(fx, fy,
              gx >= 0 && gy >= 0 && gx < _buf.width && gy < _buf.height ? _buf.get(gx, gy) : 0);
        }
      }
    }
    if (g.isOver && g.overTime >= Game.overFx) {
      final record = g.score > 0 && g.score >= (best ?? 0);
      final pulse = 0.75 + 0.25 * sin(g.overTime * 5);
      drawNumber(out, g.score, scaleColor(record ? 0xFFC83C : 0xFFFFFF, pulse),
          scale: scale, t: g.overTime - Game.overFx);
    } else if (g.paused && !g.isOver) {
      out.fade(0.3);
      final s = scale, h = 5 * s;
      final x0 = (out.width - 3 * s) ~/ 2, y0 = (out.height - h) ~/ 2;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < s; x++) {
          out.set(x0 + x, y0 + y, 0xFFFFFF);
          out.set(x0 + 2 * s + x, y0 + y, 0xFFFFFF);
        }
      }
    }
  }
}
