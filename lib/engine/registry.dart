import 'generator.dart';
import 'generators/fields.dart';
import 'generators/more.dart';
import 'generators/patterns.dart';
import 'generators/scenes.dart';
import 'generators/sims.dart';
import 'generators/sprite.dart';
import 'generators/sprite_library.dart';
import 'generators/simulations.dart';

/// Procedural generators, in picker order. Sprite generators live in
/// [spriteGenerators]; [findGenerator] resolves both.
final generators = <Generator>[
  Plasma(),
  Fire(),
  DigitalRain(),
  Metaballs(),
  Starfield(),
  Ripples(),
  Swirl(),
  Life(),
  Twinkle(),
  Aurora(),
  NoiseFlow(),
  Fireworks(),
  Snowfall(),
  BouncingBalls(),
  Helix(),
  Galaxy(),
  Oscilloscope(),
  Heartbeat(),
  Tunnel(),
  // Library v2.
  Kaleidoscope(),
  Voronoi(),
  Interference(),
  HypnoRings(),
  OpArt(),
  Silk(),
  Lattice(),
  Caustics(),
  Wash(),
  Breathe(),
  Bokeh(),
  RetroGrid(),
  Spinner(),
  Radar(),
  Disco(),
  Sky(),
  Clouds(),
  OceanWaves(),
  WindowRain(),
  Lightning(),
  MeteorShower(),
  Orbits(),
  BlackHole(),
  Borealis(),
  Fireflies(),
  Candle(),
  Magma(),
  ReactionDiffusion(),
  LangtonsAnt(),
  Maze(),
  FallingSand(),
  PixelSort(),
  Glitch(),
  Confetti(),
  Bubbles(),
  Equalizer(),
  PendulumWave(),
  Boids(),
  FlowField(),
  Floaters(),
  Comets(),
  Spirograph(),
  Wireframe(),
];

/// Pixel-art loops, one generator per sprite (ids start with `sprite:`).
List<SpriteGenerator> get spriteGenerators => SpriteLibrary.all;

/// Procedural and sprite generators together.
Iterable<Generator> get allGenerators => [...generators, ...spriteGenerators];

Generator? findGenerator(String id) {
  if (id.startsWith(SpriteGenerator.prefix)) return SpriteLibrary.byId(id);
  for (final g in generators) {
    if (g.id == id) return g;
  }
  return null;
}

Generator generatorById(String id) => findGenerator(id) ?? generators.first;
