import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/generators/sprite.dart';
import 'package:glyph/engine/gif_baker.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';

import 'gif_encoder_test.dart' show decodeTestGif;

void main() {
  test('Ocean Send retains at least 30 seconds with valid looping GIF timing', () {
    final g = generatorById('plasma');
    final loop = renderDeviceLoop(
      generator: g,
      params: Params.defaultsFor(g, {'speed': 0.2, 'scale': 0.35}),
      palette: paletteById('ocean'),
      width: 16,
      height: 16,
    );
    final gif = decodeTestGif(bakeLoop(loop).bytes);
    expect(loop.seconds, greaterThanOrEqualTo(30));
    expect(loop.seconds, lessThanOrEqualTo(37.5));
    expect(gif.frames.length, greaterThanOrEqualTo(600));
    expect(gif.delays.reduce((a, b) => a + b), (loop.seconds * 100).round());
    expect(gif.delays, everyElement(5));
    expect(gif.loop, 0);
  });

  SpriteGenerator sprite(Map<String, dynamic> s) => SpriteGenerator(
    Sprite.parsePackJson({
      'pack': 'test',
      'colors': {'R': '#FF0000', 'G': '#00FF00', 'B': '#0000FF'},
      'sprites': [s],
    }).single,
  );

  test('slow authored sequence keeps the beginning, middle and end without blending', () {
    final g = sprite({
      'id': 'long-sequence',
      'motion': 'still',
      'ms': [1000, 1000, 10000, 10000, 8000],
      'seq': [0, 1, 2, 2, 2],
      'frames': [['R'], ['G'], ['B']],
    });
    final loop = renderDeviceLoop(
      generator: g,
      params: Params.defaultsFor(g, {'speed': 0.25}),
      palette: paletteById('ocean'),
      width: 1,
      height: 1,
      timeScale: 0.5,
    );
    expect(loop.seconds, 240);
    expect(loop.frames.take(160).map((f) => f.get(0, 0)), everyElement(0xFF0000));
    expect(loop.frames.skip(160).take(160).map((f) => f.get(0, 0)), everyElement(0x00FF00));
    expect(loop.frames.skip(320).map((f) => f.get(0, 0)), everyElement(0x0000FF));
  });

  test('fast sprite Send retains every authored step even below the device tick', () {
    final g = sprite({
      'id': 'fast', 'ms': 20, 'frames': [['R'], ['G'], ['B']],
    });
    final loop = renderDeviceLoop(
      generator: g, params: Params.defaultsFor(g, {'speed': 3}),
      palette: paletteById('ocean'), width: 1, height: 1,
    );
    expect(loop.frames.map((f) => f.get(0, 0)), [0xFF0000, 0x00FF00, 0x0000FF]);
    final gif = decodeTestGif(bakeLoop(loop).bytes);
    expect(gif.frames, hasLength(3));
    expect(gif.delays, [2, 2, 2]);
  });

  test('long scrolling banner includes its complete travel at the chosen speed', () {
    final g = sprite({
      'id': 'banner',
      'motion': 'scroll',
      'frames': [List.filled(2, List.filled(10, 'RGBR').join())],
    });
    final p = Params.defaultsFor(g, {'speed': 0.25});
    final loop = renderDeviceLoop(
      generator: g, params: p, palette: paletteById('ocean'), width: 16, height: 16,
    );
    expect(loop.seconds, closeTo(338 / 7.2 / 0.25, 1e-9));
    expect(loop.frames.first.rgb, everyElement(0));
    expect(loop.frames.last.rgb, everyElement(0));
    expect(loop.frames.any((f) => f.rgb.any((v) => v != 0)), isTrue);
  });
}
