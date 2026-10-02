import '../../../engine/frame.dart';
import '../../../engine/generator.dart';
import '../../../engine/palette.dart';
import 'game.dart';

/// Runs a game inside the playback loop so it streams like any effect.
///
/// The instance rendering into [liveFrame] (the playback frame) drives the
/// shared, player-controlled [view]. Any other instance — e.g. a recording
/// for "Save to matrix" — gets its own attract-mode game, so it can't
/// disturb the one being played.
class GameGenerator extends Generator {
  GameGenerator(this.def, {this.liveFrame, this.options = const {}});

  final GameDef def;
  Frame Function()? liveFrame;
  Set<String> options;
  GameView? view;
  int? best;
  void Function(GameEvent e)? onEvent;
  int _seed = DateTime.now().microsecondsSinceEpoch & 0x3fffffff;

  @override
  String get id => 'game.${def.id}';
  @override
  String get name => def.name;

  /// Starts a fresh player game at the given matrix size.
  GameView newGame(int width, int height) => view =
      GameView(def, width, height, seed: _seed++, options: options)
        ..best = best
        ..onEvent = (e) => onEvent?.call(e);

  @override
  EffectInstance create(int width, int height, int seed) => _GameInstance(this, seed);
}

class _GameInstance extends EffectInstance {
  _GameInstance(this.gen, this.seed);

  final GameGenerator gen;
  final int seed;
  GameView? _demo;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final GameView v;
    if (identical(out, gen.liveFrame?.call())) {
      final cur = gen.view;
      v = cur != null && cur.width == out.width && cur.height == out.height
          ? cur
          : gen.newGame(out.width, out.height);
    } else {
      final d = _demo;
      v = d != null && d.width == out.width && d.height == out.height
          ? d
          : _demo = GameView(gen.def, out.width, out.height,
              seed: seed, demo: true, options: gen.options);
    }
    v
      ..tick(dt)
      ..render(out);
  }
}
