import 'dart:math' show max;

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/generators/sprite.dart';
import 'package:glyph/engine/gif_baker.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';

import 'gif_encoder_test.dart' show decodeTestGif;

// A GIF on the matrix loops forever, so its last frame is followed by its
// first. These tests measure that step against the steps the animation takes
// anyway: a seam the eye notices is one much bigger than a typical step.

/// Mean absolute channel difference, 0..255.
double _dist(List<int> a, List<int> b) {
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d += (a[i] - b[i]).abs();
  }
  return d / a.length;
}

class _Seam {
  _Seam(List<List<int>> f)
      : steps = [for (var i = 0; i + 1 < f.length; i++) _dist(f[i], f[i + 1])]..sort(),
        seam = _dist(f.last, f.first);

  final List<double> steps;
  final double seam;

  double get median => steps[steps.length ~/ 2];
  double get p90 => steps[(steps.length * 0.9).floor()];

  @override
  String toString() => 'seam ${seam.toStringAsFixed(2)}, median step '
      '${median.toStringAsFixed(2)}, p90 ${p90.toStringAsFixed(2)}';
}

_Seam _seamOf(List<Frame> frames) => _Seam([for (final f in frames) f.rgb]);

LoopFrames _loop(String id,
    {Map<String, double>? params, double seconds = 4, int w = 16, int h = 16, double fade = 0.8}) {
  final g = findGenerator(id)!;
  return renderLoop(
    generator: g,
    params: Params.defaultsFor(g, params),
    palette: paletteById(g.defaultPalette),
    width: w,
    height: h,
    seconds: seconds,
    fade: fade,
  );
}

/// Whether [a][j] == [b][(j + shift) % n] for every j.
bool _isRotation(List<Frame> a, List<Frame> b, int shift) {
  if (a.length != b.length) return false;
  for (var j = 0; j < a.length; j++) {
    final x = a[j].rgb, y = b[(j + shift) % b.length].rgb;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
  }
  return true;
}

void main() {
  // Library looks that showed a jump on the matrix every loop (catalog
  // params), plus slow effects where any jump stands out.
  const smooth = <String, Map<String, double>>{
    'plasma': {'speed': 0.2, 'scale': 0.35}, // Ocean Plasma
    'noise': {'speed': 0.25, 'scale': 0.4, 'warp': 0.8}, // Haunted Fog
    'swirl': {'speed': 0.35, 'arms': 2.0, 'twist': 0.7}, // Spooky Swirl
    'bubbles': {'count': 8.0, 'size': 0.5}, // Lava Bubbles
    'aurora': {},
    'galaxy': {},
    'tunnel': {},
    'kaleido': {},
    'silk': {},
    'wash': {},
    'sky': {},
  };

  group('procedural loops are seamless', () {
    for (final MapEntry(key: id, value: params) in smooth.entries) {
      test(id, () {
        final g = findGenerator(id)!;
        final p = Params.defaultsFor(g, params);
        final pal = paletteById(g.defaultPalette);
        final loop = _loop(id, params: params);
        final after = _seamOf(loop.frames);
        expect(after.seam, lessThanOrEqualTo(1.5 * after.median + 1e-9), reason: '$after');

        // What the old bake did: 4 s cut wherever it ended.
        final cut = _seamOf(renderFrames(
            generator: g, params: p, palette: pal, width: 16, height: 16));
        // ignore: avoid_print
        print('$id: cut $cut | loop $after, ${loop.seconds} s');
      });
    }

    test('the old cut jumped: Ocean Plasma, Haunted Fog, aurora, galaxy', () {
      for (final id in ['plasma', 'noise', 'aurora', 'galaxy']) {
        final g = findGenerator(id)!;
        final cut = _seamOf(renderFrames(
            generator: g,
            params: Params.defaultsFor(g, smooth[id]),
            palette: paletteById(g.defaultPalette),
            width: 16,
            height: 16));
        expect(cut.seam, greaterThan(10 * cut.median), reason: '$id: $cut');
      }
    });

    test('no effect jumps more at the seam than it does anyway', () {
      var withinP90 = 0;
      for (final g in generators) {
        final s = _seamOf(_loop(g.id).frames);
        // Bursty effects (lightning, pixel sort, fireflies) have a small
        // median step but regular big ones; the seam is no bigger than those.
        expect(s.seam, lessThanOrEqualTo(max(1.5 * s.median, s.steps.last) + 1e-9),
            reason: '${g.id}: $s');
        if (s.seam <= max(1.5 * s.median, s.p90)) withinP90++;
      }
      expect(withinP90, greaterThanOrEqualTo(generators.length - 1));
    });

    test('the baked GIF loops seamlessly too', () {
      final loop = _loop('plasma', params: smooth['plasma']);
      final gif = decodeTestGif(bakeLoop(loop).bytes);
      final s = _Seam(gif.frames);
      expect(s.seam, lessThanOrEqualTo(1.5 * s.median), reason: '$s');
    });

    test('stays within ±25% of the requested length, at 20 fps', () {
      for (final id in ['plasma', 'fire', 'life', 'retrogrid']) {
        for (final seconds in [3.0, 4.0]) {
          final loop = _loop(id, seconds: seconds);
          expect(loop.seconds, inInclusiveRange(seconds * 0.75, seconds * 1.25), reason: id);
          expect(loop.frames.length, (loop.seconds * deviceGifFps).round());
        }
      }
    });

    test('non-square and fade-free loops work', () {
      final loop = _loop('helix', w: 8, h: 32, seconds: 1);
      expect(loop.frames.first.width, 8);
      expect(loop.frames.first.height, 32);
      final plain = _loop('plasma', fade: 0);
      expect(plain.frames.length, inInclusiveRange(60, 100));
    });
  });

  group('sprites loop on whole periods', () {
    Sprite sprite(Map<String, dynamic> s) => Sprite.parsePackJson({
          'pack': 'test',
          'colors': {'R': '#FF0000', 'G': '#00FF00', 'B': '#0000FF', 'C': 'c:0.2'},
          'sprites': [s],
        }).single;

    const rows = ['RRRR', 'RGGR', 'RGGR', 'RRRR'];
    const rows2 = ['GGGG', 'GBBG', 'GBBG', 'GGGG'];
    const rows3 = ['BBBB', 'BRRB', 'BRRB', 'BBBB'];

    /// Renders [g]'s loop with and without the fade and checks the fade
    /// changed nothing (the content repeats exactly), and that one more
    /// period continues from the first frame.
    LoopFrames exact(SpriteGenerator g, {Map<String, double>? params}) {
      final p = Params.defaultsFor(g, params);
      final pal = paletteById('rainbow');
      LoopFrames r(double fade) => renderLoop(
          generator: g, params: p, palette: pal, width: 16, height: 16, fade: fade);
      final faded = r(0.8), plain = r(0);
      final n = plain.frames.length;
      expect(faded.frames.length, n);
      expect(_isRotation(faded.frames, plain.frames, 16 < n ~/ 2 ? 16 : n ~/ 2), isTrue,
          reason: 'content repeats exactly after ${plain.seconds} s');
      return faded;
    }

    test('frame sequence: 0.9 s loop baked 4 times, steps keep their timing', () {
      final g = SpriteGenerator(sprite({
        'id': 'steps',
        'ms': [300, 250, 200, 150],
        'frames': [rows, rows2, rows3, rows2],
      }));
      expect(g.loopSeconds(Params.defaultsFor(g), 16, 16), closeTo(0.9, 1e-9));
      final loop = exact(g);
      expect(loop.seconds, closeTo(3.6, 1e-9));
      expect(loop.frames.length, 72);
      // Runs of identical frames: 6, 5, 4, 3 frames (300/250/200/150 ms), x4.
      final runs = <int>[];
      for (var i = 0; i < loop.frames.length; i++) {
        final same = i > 0 && _dist(loop.frames[i].rgb, loop.frames[i - 1].rgb) == 0;
        if (same) {
          runs[runs.length - 1]++;
        } else {
          runs.add(1);
        }
      }
      // The loop may start mid-step; join the wrap-around run.
      if (_dist(loop.frames.first.rgb, loop.frames.last.rgb) == 0) {
        runs[0] += runs.removeLast();
      }
      runs.sort();
      expect(runs, [for (final r in [3, 4, 5, 6]) ...List.filled(4, r)]..sort());
    });

    test('motion: bounce (0.7 s) with a 0.7 s sequence is a 4.2 s loop', () {
      final g = SpriteGenerator(sprite({
        'id': 'hop',
        'motion': 'bounce',
        'ms': 350,
        'frames': [rows, rows2],
      }));
      expect(g.loopSeconds(Params.defaultsFor(g), 16, 16), closeTo(0.7, 1e-9));
      expect(exact(g).seconds, closeTo(4.2, 1e-9));
      // Half speed doubles the period.
      expect(g.loopSeconds(Params.defaultsFor(g, {'speed': 0.5}), 16, 16), closeTo(1.4, 1e-9));
    });

    test('scrolling text keeps the whole message', () {
      final g = SpriteGenerator(sprite({
        'id': 'banner',
        'motion': 'scroll',
        'ms': 200,
        'frames': [
          [List.filled(10, 'R.G.').join(), List.filled(10, 'RGBR').join()],
        ],
      }));
      // 40x2 fits by height (x8): 320 px wide, travels 16 + 320 + 2 px at
      // 0.45 * 16 = 7.2 px/s.
      final period = g.loopSeconds(Params.defaultsFor(g), 16, 16, maxSeconds: 60)!;
      expect(period, closeTo(338 / 7.2, 1e-9));
      // Longer than any loop renderLoop bakes: no exact loop then.
      expect(g.loopSeconds(Params.defaultsFor(g), 16, 16, maxSeconds: maxNaturalSeconds), isNull);

      final short = SpriteGenerator(sprite({
        'id': 'hi',
        'motion': 'scroll',
        'ms': 200,
        'frames': [
          List.filled(4, List.filled(8, 'RGB.').join()),
        ],
      }));
      // 32x4 fits by height (x4): 128 px, travels 146 px in 20.28 s > 20 s;
      // at speed 2 it's 10.14 s, baked once.
      final fast = {'speed': 2.0};
      final s = short.loopSeconds(Params.defaultsFor(short, fast), 16, 16)!;
      expect(s, closeTo(146 / 7.2 / 2, 1e-9));
      final loop = exact(short, params: fast);
      expect(loop.seconds, closeTo(s, 1e-9));
    });

    test('colour cycling joins the period when it fits', () {
      final g = SpriteGenerator(sprite({
        'id': 'cyc',
        'ms': 500,
        'frames': [
          ['CCCC', 'CRRC', 'CRRC', 'CCCC'],
          ['CCCC', 'CGGC', 'CGGC', 'CCCC'],
        ],
      }));
      // lcm(1 s sequence, 4 s palette cycle).
      expect(g.loopSeconds(Params.defaultsFor(g), 16, 16), closeTo(4, 1e-9));
      expect(exact(g).seconds, closeTo(4, 1e-9));
    });

    test('library sprites bake exact loops that are small', () {
      var exactLoops = 0;
      for (final g in spriteGenerators) {
        final p = Params.defaultsFor(g);
        final s = g.loopSeconds(p, 16, 16, maxSeconds: maxNaturalSeconds);
        if (s == null) continue;
        final loop = renderLoop(
            generator: g, params: p, palette: paletteById(g.defaultPalette), width: 16, height: 16);
        // A whole number of periods.
        final k = loop.seconds / s;
        expect((k - k.round()).abs(), lessThan(1e-6), reason: g.id);
        expect(bakeLoop(loop).bytes.length, lessThan(40 * 1024), reason: g.id);
        exactLoops++;
      }
      expect(exactLoops, greaterThan(spriteGenerators.length * 0.8));
    });

    test('library bouncing sprites repeat exactly', () {
      for (final id in ['taco', 'burger']) {
        final g = findGenerator('sprite:$id')! as SpriteGenerator;
        expect(g.params.firstWhere((p) => p.key == 'motion').defaultValue, SpriteMotion.bounce.index);
        exact(g);
      }
    });
  });

  test('clips loop on their own length', () {
    final frames = [
      for (var i = 0; i < 3; i++) Frame(4, 4)..fill(rgb(80 * i, 0, 0)),
    ];
    final g = ClipGenerator(FrameClip(width: 4, height: 4, frames: frames, delaysMs: [300, 300, 400]));
    final p = Params.defaultsFor(g);
    expect(g.loopSeconds(p), closeTo(1.0, 1e-9));
    final loop = renderLoop(
        generator: g, params: p, palette: paletteById('rainbow'), width: 4, height: 4);
    expect(loop.seconds, closeTo(4.0, 1e-9));
    final gif = decodeTestGif(bakeLoop(loop).bytes);
    expect(gif.delays.fold(0, (a, b) => a + b), 400);
    // Four whole passes: what shows at each centisecond repeats every 1 s,
    // also across the GIF's own loop.
    final shown = gif.timeline(List.filled(400, 1));
    for (var i = 0; i < 400; i++) {
      expect(shown[i], shown[(i + 100) % 400], reason: 'cs $i');
    }
    // and each clip frame keeps its own length (300/300/400 ms).
    var changes = 0;
    for (var i = 0; i < 400; i++) {
      if (_dist(shown[i], shown[(i + 1) % 400]) != 0) changes++;
    }
    expect(changes, 12);
  });
}
