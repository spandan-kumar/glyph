import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/bake_limits.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/gif_baker.dart';
import 'package:glyph/engine/gif_encoder.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';

void main() {
  test('a 64x64 full procedural recording fits the phone preparation budget', () {
    checkBakeSize(64, 64, 1125); // includes seam-search work
    checkBakeSize(16, 16, maxBakeFrames);
  });

  test('frame and pixel budgets reject work without shortening it', () {
    expect(() => checkBakeSize(1, 1, maxBakeFrames + 1),
        throwsA(isA<BakeLimitException>()));
    expect(() => checkBakeSize(64, 64, maxBakePixels ~/ (64 * 64) + 1),
        throwsA(isA<BakeLimitException>()));
  });

  test('rendering rejects an oversized recording before creating its effect', () {
    final g = _NeverCreated();
    expect(() => renderFrames(generator: g, params: Params({}),
      palette: paletteById('ocean'), width: 16, height: 16,
      seconds: maxBakeFrames.toDouble(), fps: 20,
    ), throwsA(isA<BakeLimitException>()));
    expect(() => renderDeviceLoop(generator: g, params: Params({}),
      palette: paletteById('ocean'), width: 512, height: 512,
    ), throwsA(isA<BakeLimitException>()));
  });

  test('encoding checks its budget before allocating colour buffers', () {
    final frame = Frame(1, 1);
    expect(() => encodeGif(List.filled(maxBakeFrames + 1, frame), []),
        throwsA(isA<BakeLimitException>()));
  });

  test('invalid animation dimensions fail explicitly', () {
    expect(() => checkBakeSize(0, 16, 10), throwsArgumentError);
    expect(() => checkBakeSize(16, -1, 10), throwsArgumentError);
  });

  test('normal frame baking retains its requested duration', () {
    final g = generatorById('plasma');
    final frames = renderFrames(generator: g, params: Params.defaultsFor(g),
      palette: paletteById('ocean'), width: 2, height: 2, seconds: 15,
    );
    expect(frames, hasLength(300));
    expect(bakeFrames(frames).duration, const Duration(seconds: 15));
  });
}

class _NeverCreated extends Generator {
  @override
  String get id => 'never-created';
  @override
  String get name => 'Never created';
  @override
  EffectInstance create(int width, int height, int seed) =>
      throw StateError('Budget must be checked before creating an effect');
}
