import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/features/games/core/digits.dart';
import 'package:glyph/features/games/core/game.dart';
import 'package:glyph/features/games/logic/blocks.dart';
import 'package:glyph/features/games/logic/breaker.dart';
import 'package:glyph/features/games/logic/flap.dart';
import 'package:glyph/features/games/logic/invaders.dart';
import 'package:glyph/features/games/logic/pong.dart';
import 'package:glyph/features/games/logic/racer.dart';
import 'package:glyph/features/games/logic/snake.dart';

void run(Game g, double seconds, {double dt = 1 / 40}) {
  for (var t = 0.0; t < seconds; t += dt) {
    g.tick(dt);
  }
}

void main() {
  group('Snake', () {
    test('grows and scores when it eats', () {
      final g = Snake(16, 16, 1);
      final head = g.body.first;
      g.food = (head.$1 + 1, head.$2);
      g.step();
      expect(g.body.length, 4);
      expect(g.score, 1);
      expect(g.body.first, (head.$1 + 1, head.$2));
      expect(g.food, isNot(g.body.first));
    });

    test('dies when it bites itself', () {
      final g = Snake(16, 16, 1)
        ..body = [(5, 5), (5, 4), (6, 4), (6, 5), (6, 6), (5, 6)]
        ..dir = (0, 1)
        ..food = (0, 0);
      g.press(GameKey.right);
      g.step();
      expect(g.isOver, isTrue);
    });

    test('moving into the tail cell is safe', () {
      final g = Snake(16, 16, 1)
        ..body = [(5, 5), (5, 4), (6, 4), (6, 5)]
        ..dir = (0, 1)
        ..food = (0, 0);
      g.press(GameKey.right);
      g.step();
      expect(g.isOver, isFalse);
      expect(g.body.first, (6, 5));
    });

    test('wraps around edges, or dies on walls', () {
      final wrap = Snake(16, 16, 1)
        ..body = [(15, 3), (14, 3), (13, 3)]
        ..food = (0, 0);
      wrap.step();
      expect(wrap.body.first, (0, 3));
      expect(wrap.isOver, isFalse);

      final walls = Snake(16, 16, 1, wrap: false)
        ..body = [(15, 3), (14, 3), (13, 3)]
        ..food = (0, 0);
      walls.step();
      expect(walls.isOver, isTrue);
    });

    test('ignores reversing into its neck', () {
      final g = Snake(16, 16, 1)..food = (0, 0);
      final head = g.body.first;
      g.press(GameKey.left);
      g.step();
      expect(g.body.first, (head.$1 + 1, head.$2));
    });

    test('speeds up as it grows', () {
      final g = Snake(16, 16, 1);
      final slow = g.interval;
      g.score = 10;
      expect(g.interval, lessThan(slow));
    });

    test('is deterministic for a seed', () {
      final a = Snake(16, 16, 42, demo: true), b = Snake(16, 16, 42, demo: true);
      run(a, 20);
      run(b, 20);
      expect(a.body, b.body);
      expect(a.score, b.score);
      expect(a.score, greaterThan(0), reason: 'the demo AI should find food');
    });
  });

  group('Blocks', () {
    Set<(int, int)> cells(Blocks g) => g.piece!.cells.toSet();

    test('T rotates clockwise and back after four turns', () {
      final g = Blocks(10, 20, 1)..spawn(2);
      final start = cells(g);
      expect(start, {(4, 0), (3, 1), (4, 1), (5, 1)});
      expect(g.rotate(), isTrue);
      expect(cells(g), {(4, 0), (4, 1), (5, 1), (4, 2)});
      g
        ..rotate()
        ..rotate()
        ..rotate();
      expect(cells(g), start);
    });

    test('rotation kicks off the wall', () {
      final g = Blocks(10, 20, 1)..spawn(2);
      g.rotate();
      while (g.move(-1, 0)) {}
      expect(cells(g).map((c) => c.$1).reduce((a, b) => a < b ? a : b), 0);
      expect(g.rotate(), isTrue, reason: 'should kick right instead of failing');
      expect(g.piece!.rot, 2);
      expect(cells(g).every((c) => c.$1 >= 0), isTrue);
    });

    test('clears a line and scores it', () {
      final g = Blocks(10, 20, 1);
      for (var x = 0; x < 10; x++) {
        if (x < 3 || x > 6) g.setCell(x, 19, 1);
      }
      g.spawn(0);
      g.hardDrop();
      expect(g.clearing, [19]);
      g.tick(0.31);
      expect(g.lines, 1);
      expect(g.score, 2 * 19 + 100);
      expect(g.cells.every((c) => c == 0), isTrue);
      expect(g.piece, isNotNull);
    });

    test('four lines at once score 800 × level', () {
      final g = Blocks(10, 20, 1);
      for (var y = 16; y < 20; y++) {
        for (var x = 0; x < 9; x++) {
          g.setCell(x, y, 3);
        }
      }
      g
        ..spawn(0)
        ..rotate();
      while (g.move(1, 0)) {}
      g.hardDrop();
      expect(g.clearing, [16, 17, 18, 19]);
      g.tick(0.31);
      expect(g.lines, 4);
      expect(g.score, 2 * 17 + 800);
    });

    test('soft drop moves down immediately and gravity locks pieces', () {
      final g = Blocks(10, 20, 1)..spawn(1);
      final y = g.piece!.y;
      g.press(GameKey.down);
      expect(g.piece!.y, y + 1);
      g.release(GameKey.down);
      run(g, 30);
      expect(g.cells.any((c) => c != 0), isTrue);
    });

    test('stacking to the top ends the game', () {
      final g = Blocks(10, 20, 1);
      for (var i = 0; i < 60 && !g.isOver; i++) {
        g.hardDrop();
      }
      expect(g.isOver, isTrue);
    });

    test('blocked spawn ends the game', () {
      final g = Blocks(10, 20, 1);
      for (var y = 1; y < 20; y++) {
        for (var x = 1; x < 10; x++) {
          g.setCell(x, y, 1);
        }
      }
      g.spawn(2);
      expect(g.isOver, isTrue);
    });

    test('demo is deterministic and clears lines', () {
      final a = Blocks(16, 16, 7, demo: true), b = Blocks(16, 16, 7, demo: true);
      run(a, 60);
      run(b, 60);
      expect(a.cells, b.cells);
      expect(a.score, b.score);
      expect(a.lines, greaterThan(0));
    });
  });

  group('Brick Breaker', () {
    Breaker launched() => Breaker(16, 16, 1)
      ..stuck = false
      ..vx = 0;

    test('ball bounces off the paddle', () {
      final events = <GameEvent>[];
      final g = launched()
        ..bx = 8
        ..px = 8
        ..by = 14.5;
      g
        ..vy = g.speed
        ..onEvent = events.add;
      g.update(0.1);
      expect(g.vy, lessThan(0));
      expect(g.vx, isNot(0), reason: 'never returns perfectly vertical');
      expect(events, contains(GameEvent.bounce));
    });

    test('ball bounces off walls', () {
      final g = launched()
        ..bx = 0.3
        ..by = 9
        ..vx = -10
        ..vy = 0;
      g.update(0.05);
      expect(g.vx, greaterThan(0));
    });

    test('breaks a brick and scores', () {
      final g = launched();
      final below = g.top + g.rows + 0.3;
      g
        ..bx = 4.5
        ..by = below
        ..vy = -10;
      final before = g.bricks.where((b) => b).length;
      g.update(0.1);
      expect(g.bricks.where((b) => b).length, before - 1);
      expect(g.vy, greaterThan(0));
      expect(g.score, greaterThan(0));
    });

    test('missing the ball costs a life', () {
      final g = launched()..pointer(1);
      g
        ..bx = 0.5
        ..by = 14.5
        ..vy = 10;
      g.update(0.2);
      expect(g.lives, 2);
      expect(g.stuck, isTrue);
    });

    test('demo is deterministic', () {
      final a = Breaker(16, 16, 3, demo: true), b = Breaker(16, 16, 3, demo: true);
      run(a, 30);
      run(b, 30);
      expect(a.score, b.score);
      expect(a.bx, b.bx);
    });
  });

  group('Pong', () {
    Pong live() => Pong(16, 16, 1)..update(1);

    test('player paddle returns the ball', () {
      final g = live()
        ..me = 8
        ..ba = 8
        ..bd = 14.6
        ..va = 0
        ..vd = 8;
      g.update(0.06);
      expect(g.vd, lessThan(0));
    });

    test('getting past the machine scores', () {
      final g = live()
        ..ai = 2
        ..ba = 15.5
        ..bd = 0.5
        ..va = 0
        ..vd = -10;
      g.update(0.06);
      expect(g.score, 1);
    });

    test('three misses end the game', () {
      final g = Pong(16, 16, 1);
      for (var i = 0; i < 3; i++) {
        g.update(1);
        g
          ..me = 2
          ..ba = 15.5
          ..bd = 15.5
          ..va = 0
          ..vd = 10;
        g.update(0.06);
      }
      expect(g.isOver, isTrue);
    });

    test('wide matrices play sideways', () {
      expect(Pong(32, 8, 1).pointerVertical, isTrue);
      expect(Pong(16, 16, 1).pointerVertical, isFalse);
    });
  });

  group('Flap', () {
    test('hitting a pipe ends the game', () {
      final g = Flap(16, 16, 1)
        ..started = true
        ..y = 10;
      g.pipes.add(Pipe(g.birdX.toDouble(), 0, 3));
      g.update(0.01);
      expect(g.isOver, isTrue);
    });

    test('flying through the gap scores', () {
      final g = Flap(16, 16, 1)
        ..started = true
        ..y = 8;
      g.pipes.add(Pipe(g.birdX - 1.0, 6, 6));
      for (var i = 0; i < 3; i++) {
        g.update(0.1);
      }
      expect(g.isOver, isFalse);
      expect(g.score, 1);
    });

    test('falling to the ground ends the game', () {
      final g = Flap(16, 16, 1)
        ..started = true
        ..y = 15.5
        ..vy = 5;
      g.update(0.1);
      expect(g.isOver, isTrue);
    });

    test('flap pushes the bird up', () {
      final g = Flap(16, 16, 1)..flap();
      expect(g.vy, lessThan(0));
      expect(g.started, isTrue);
    });
  });

  group('Racer', () {
    test('crashing into traffic ends the game', () {
      final g = Racer(16, 16, 1);
      g.cars.add(Car(g.lane, g.playerY - 1.0, 0));
      g.update(0.01);
      expect(g.isOver, isTrue);
    });

    test('changing lanes dodges', () {
      final g = Racer(16, 16, 1);
      g.cars.add(Car(g.lane, g.playerY - 1.0, 0));
      g.press(GameKey.right);
      g.update(0.01);
      expect(g.isOver, isFalse);
    });

    test('steering stops at the road edge', () {
      final g = Racer(16, 16, 1);
      for (var i = 0; i < 10; i++) {
        g.press(GameKey.left);
      }
      expect(g.lane, 0);
    });

    test('demo survives a while and is deterministic', () {
      final a = Racer(16, 16, 5, demo: true), b = Racer(16, 16, 5, demo: true);
      run(a, 20);
      run(b, 20);
      expect(a.score, b.score);
      expect(a.lane, b.lane);
      expect(a.score, greaterThan(5));
    });
  });

  group('Invaders', () {
    test('a shot destroys an invader', () {
      final g = Invaders(16, 16, 1);
      g.px = g.invX(0).toDouble();
      g.fire();
      for (var i = 0; i < 40 && g.score == 0; i++) {
        g.update(1 / 40);
      }
      expect(g.score, greaterThan(0));
    });
  });

  test('digits fit, wrap and scroll without throwing', () {
    for (final (w, h) in [(16, 16), (8, 8), (32, 8), (4, 4)]) {
      final f = Frame(w, h);
      for (final n in [0, 7, 1234, 98765432]) {
        drawNumber(f, n, 0xFFFFFF, t: 3.3);
      }
    }
    final f = Frame(16, 16);
    drawNumber(f, 42, 0xFFFFFF);
    expect(f.rgb.any((v) => v != 0), isTrue);
  });
}
