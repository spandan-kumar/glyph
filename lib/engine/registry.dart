import 'generator.dart';
import 'generators/fields.dart';
import 'generators/more.dart';
import 'generators/simulations.dart';

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
];

Generator generatorById(String id) =>
    generators.firstWhere((g) => g.id == id, orElse: () => generators.first);
