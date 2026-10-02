import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/gif_baker.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/features/games/catalog.dart';
import 'package:glyph/features/games/core/game.dart';
import 'package:glyph/features/games/core/game_generator.dart';

void main() {
  const sizes = [(16, 16), (32, 8), (8, 8), (64, 32), (24, 12), (60, 1)];
  final params = Params({});
  final pal = palettes.first;

  for (final def in gameDefs) {
    group(def.name, () {
      for (final (w, h) in sizes) {
        test('runs live at $w×$h with input', () {
          final out = Frame(w, h);
          final gen = GameGenerator(def, liveFrame: () => out);
          final fx = gen.create(w, h, 1);
          var t = 0.0;
          for (var i = 0; i < 1200; i++) {
            const dt = 1 / 40;
            t += dt;
            final g = gen.view?.game;
            if (g != null && i % 7 == 0) {
              final k = GameKey.values[i ~/ 7 % GameKey.values.length];
              g
                ..press(k)
                ..pointer((i % 50) / 50);
              if (i % 3 == 0) g.release(k);
            }
            if (i == 400) gen.view!.game.paused = true;
            if (i == 440) gen.view!.game.paused = false;
            if (g != null && g.isOver && i % 200 == 0) gen.newGame(w, h);
            fx.render(out, t, dt, params, pal);
          }
          expect(gen.view, isNotNull);
          expect(gen.view!.width, w);
        });

        test('attract mode runs at $w×$h', () {
          final v = GameView(def, w, h, seed: 3, demo: true);
          final out = Frame(w, h);
          for (var i = 0; i < 2400; i++) {
            v
              ..tick(1 / 40)
              ..render(out);
          }
        });
      }

      test('game over shows the score on the matrix', () {
        final v = GameView(def, 16, 16, seed: 1);
        v.game.score = 42;
        v.game.endGame();
        v.tick(Game.overFx + 0.2);
        final out = Frame(16, 16);
        v.render(out);
        expect(out.rgb.any((c) => c > 120), isTrue);
      });

      test('recording for save does not touch the live game', () {
        final live = Frame(16, 16);
        final gen = GameGenerator(def, liveFrame: () => live);
        gen.create(16, 16, 1).render(live, 0, 0.025, params, pal);
        final game = gen.view!.game;
        final frames = renderFrames(
            generator: gen, params: params, palette: pal, width: 16, height: 16, seconds: 1);
        expect(frames, hasLength(20));
        expect(identical(gen.view!.game, game), isTrue);
        expect(game.time, closeTo(0.025, 1e-9));
      });
    });
  }

  test('wide racer is rotated, square is not', () {
    final racer = gameById('racer');
    expect(GameView(racer, 32, 8, seed: 1).rotated, isTrue);
    expect(GameView(racer, 16, 16, seed: 1).rotated, isFalse);
    expect(GameView(racer, 64, 64, seed: 1).scale, 4);
  });
}
