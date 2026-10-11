import 'core/game.dart';
import 'logic/blocks.dart';
import 'logic/breaker.dart';
import 'logic/flap.dart';
import 'logic/invaders.dart';
import 'logic/pong.dart';
import 'logic/racer.dart';
import 'logic/snake.dart';

final gameDefs = <GameDef>[
  GameDef(
    id: 'snake',
    name: 'Snake',
    blurb: 'Eat, grow, don\'t bite',
    hint: 'Swipe anywhere or use the pad',
    controls: Controls.dpad,
    options: const [('walls', 'Solid walls')],
    build: (w, h, s, demo, o) => Snake(w, h, s, demo: demo, wrap: !o.contains('walls')),
  ),
  GameDef(
    id: 'blocks',
    name: 'Blocks',
    blurb: 'Stack and clear lines',
    hint: 'Hold left or right to slide · down to drop faster',
    controls: Controls.blocks,
    build: (w, h, s, demo, o) => Blocks(w, h, s, demo: demo),
  ),
  GameDef(
    id: 'breaker',
    name: 'Brick Breaker',
    blurb: 'Smash every brick',
    hint: 'Drag to move · tap to launch',
    controls: Controls.paddle,
    build: (w, h, s, demo, o) => Breaker(w, h, s, demo: demo),
  ),
  GameDef(
    id: 'pong',
    name: 'Pong',
    blurb: 'Out-rally the machine',
    hint: 'Drag to move your paddle',
    controls: Controls.paddle,
    build: (w, h, s, demo, o) => Pong(w, h, s, demo: demo),
  ),
  GameDef(
    id: 'flap',
    name: 'Flap',
    blurb: 'Tap through the gaps',
    hint: 'Tap anywhere to flap',
    controls: Controls.tap,
    build: (w, h, s, demo, o) => Flap(w, h, s, demo: demo),
  ),
  GameDef(
    id: 'racer',
    name: 'Racer',
    blurb: 'Dodge the traffic',
    hint: 'Tap a side to change lanes',
    controls: Controls.steer,
    rotateWide: true,
    build: (w, h, s, demo, o) => Racer(w, h, s, demo: demo),
  ),
  GameDef(
    id: 'invaders',
    name: 'Invaders',
    blurb: 'Hold the line',
    hint: 'Hold left or right to move · fire away',
    controls: Controls.shooter,
    build: (w, h, s, demo, o) => Invaders(w, h, s, demo: demo),
  ),
];

GameDef gameById(String id) => gameDefs.firstWhere((g) => g.id == id);
