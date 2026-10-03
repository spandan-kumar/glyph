import 'dart:math';
import 'dart:typed_data';

import 'clip.dart';
import 'frame.dart';
import 'generator.dart';
import 'generators/sprite.dart';
import 'gif_encoder.dart';
import 'palette.dart';

/// Frame rate for GIFs that WLED's Image effect plays. WLED advances a GIF
/// only on its effect tick (every 1000/42 ≈ 23 ms at the default 42 FPS) and
/// carries any overshoot into the next wait (image_loader.cpp
/// renderImageToSegment), so 50 ms frames land on an even two ticks while
/// 40 ms frames alternate one and two ticks and 66 ms frames two and three,
/// both of which judder.
const deviceGifFps = 20;

/// Longest exact loop [renderLoop] bakes for a sprite or clip, so a
/// scrolling message is kept whole; pixel art stays small even at this
/// length.
const maxNaturalSeconds = 20.0;

class BakeResult {
  const BakeResult(this.bytes, this.frameCount, this.duration);

  final Uint8List bytes;
  final int frameCount;
  final Duration duration;
}

/// Frames that play as a seamless loop: the frame after the last is the
/// first.
class LoopFrames {
  const LoopFrames(this.frames, this.seconds);

  final List<Frame> frames;

  /// How long all [frames] play for, together.
  final double seconds;
}

/// Renders about [seconds] of [generator] as a seamless loop (see
/// [renderLoop]) and encodes it as a looping GIF. Stateful effects (fire,
/// particles, trails) are run for [warmup] seconds first so the GIF doesn't
/// start on an empty screen. [timeScale] plays the effect faster or slower,
/// matching a library item's speed. [seamless] = false encodes exactly
/// [seconds] of [renderFrames] instead, cut wherever it ends.
BakeResult bakeGif({
  required Generator generator,
  required Params params,
  required Palette palette,
  required int width,
  required int height,
  double seconds = 4,
  int fps = deviceGifFps,
  double warmup = 1.5,
  int seed = 1,
  double timeScale = 1,
  bool seamless = true,
}) {
  if (!seamless) {
    return bakeFrames(
      renderFrames(
        generator: generator,
        params: params,
        palette: palette,
        width: width,
        height: height,
        seconds: seconds,
        fps: fps,
        warmup: warmup,
        seed: seed,
        timeScale: timeScale,
      ),
      fps: fps,
    );
  }
  return bakeLoop(renderLoop(
    generator: generator,
    params: params,
    palette: palette,
    width: width,
    height: height,
    seconds: seconds,
    fps: fps,
    warmup: warmup,
    seed: seed,
    timeScale: timeScale,
  ));
}

/// Renders [generator] as a loop of about [seconds] whose last frame flows
/// into its first, so a player looping it (a GIF on the matrix) shows no
/// jump at the seam.
///
/// Sprites and clips repeat exactly after a known time, so a whole number of
/// those periods is rendered, sampled evenly. Procedural effects never
/// repeat: of the loop lengths within ±25% of [seconds], the one whose start
/// best matches what follows its end is picked, and its last [fade] seconds
/// cross-fade into what the first frames continue from. Where the two
/// already match (a periodic effect) the fade changes nothing.
LoopFrames renderLoop({
  required Generator generator,
  required Params params,
  required Palette palette,
  required int width,
  required int height,
  double seconds = 4,
  int fps = deviceGifFps,
  double warmup = 1.5,
  int seed = 1,
  double timeScale = 1,
  double fade = 0.8,
}) {
  if (fps <= 0) throw ArgumentError.value(fps, 'fps', 'must be positive');
  final effect = generator.create(width, height, seed);
  final out = Frame(width, height);
  var t = 0.0;
  void step(double dt) {
    effect.render(out, t, dt, params, palette);
    t += dt;
  }

  List<Frame> take(int n, double dt) {
    final frames = <Frame>[];
    for (var i = 0; i < n; i++) {
      step(dt);
      frames.add(out.copy());
    }
    return frames;
  }

  final baseDt = timeScale / fps;
  for (var i = (warmup * fps).round(); i > 0; i--) {
    step(baseDt);
  }

  final natural =
      _naturalLoop(generator, params, width, height, max(3 * seconds, maxNaturalSeconds) * timeScale);
  if (natural != null) {
    final (effectSeconds, blend) = natural;
    final period = effectSeconds / timeScale;
    final total = max(1, (seconds / period).round()) * period;
    final n = max(1, (total * fps).round());
    final dt = total * timeScale / n;
    // Sample between, not on, the sprite's step boundaries, so rounding
    // can't put a step change one frame early in one pass only.
    step(dt / 2);
    final m = blend ? min((fade * fps).round(), n ~/ 2) : 0;
    return LoopFrames(_crossFade(take(n + m, dt), n, m), total);
  }

  final target = max(1, (seconds * fps).round());
  final lo = max(1, (target * 0.75).round()), hi = max(lo, (target * 1.25).round());
  final m0 = min((fade * fps).round(), lo ~/ 2);
  final s = take(hi + max(hi ~/ 2, 1), baseDt);
  double mismatch(int n, int m) {
    var c = 0.0;
    for (var k = 0; k < max(m, 1); k++) {
      c += _distance(s[n + k], s[k]);
    }
    return c / max(m, 1);
  }

  // Candidates nearest the target first, so ties keep the file small.
  final order = [for (var n = lo; n <= hi; n++) n]
    ..sort((a, b) => (a - target).abs().compareTo((b - target).abs()));
  var best = order.first;
  var bestCost = double.infinity;
  for (final n in order) {
    final c = mismatch(n, m0) * (1 + 0.2 * (n - target).abs() / target);
    if (c < bestCost) {
      bestCost = c;
      best = n;
    }
  }
  // The fade adds about mismatch / (m + 1) to each of its steps. Slow
  // effects barely change per frame, so stretch their fade (up to half the
  // loop) until that stays near a third of a typical step.
  var m = m0;
  if (m > 0) {
    final steps = [for (var i = 0; i + 1 < s.length; i++) _distance(s[i], s[i + 1])]..sort();
    final typical = steps[steps.length ~/ 2];
    while (m < best ~/ 2 && mismatch(best, m) / (m + 1) > 0.35 * typical) {
      m++;
    }
  }
  return LoopFrames(_crossFade(s, best, m), best / fps);
}

/// Encodes [loop] as an infinitely looping GIF lasting [LoopFrames.seconds].
BakeResult bakeLoop(LoopFrames loop) {
  final frames = loop.frames;
  if (frames.isEmpty) throw ArgumentError('No frames to bake');
  // Round each frame's end time to whole centiseconds, as [bakeFrames] does.
  final totalCs = loop.seconds * 100;
  final delays = List<int>.filled(frames.length, 0);
  var total = 0;
  for (var i = 0; i < frames.length; i++) {
    final end = ((i + 1) * totalCs / frames.length).round();
    delays[i] = max(2, end - total);
    total += delays[i];
  }
  return BakeResult(
    encodeGif(frames, delays),
    frames.length,
    Duration(milliseconds: total * 10),
  );
}

/// The effect-time loop length of generators that repeat exactly, and
/// whether a cross-fade may smooth what doesn't (twinkles, backdrop drift).
/// Shake jitters at random, so blending would only ghost the sprite.
(double, bool)? _naturalLoop(Generator g, Params p, int w, int h, double maxSeconds) {
  final double? s;
  var blend = true;
  if (g is SpriteGenerator) {
    s = g.loopSeconds(p, w, h, maxSeconds: maxSeconds);
    blend = p['motion'].round() != SpriteMotion.shake.index;
  } else if (g is ClipGenerator) {
    s = g.loopSeconds(p);
  } else {
    return null;
  }
  return s != null && s > 0 && s <= maxSeconds ? (s, blend) : null;
}

/// [s] with its first [m] frames dropped and its last [m] frames, past
/// frame [n], cross-faded into them: output j is s[j + m], blended towards
/// s[j + m - n] by (k + 1) / (m + 1) for the k-th of the last m. The final
/// frame is then almost s[m - 1], which flows into output 0 = s[m].
List<Frame> _crossFade(List<Frame> s, int n, int m) {
  if (m == 0) return s.sublist(0, n);
  return [
    for (var j = 0; j < n; j++)
      j < n - m ? s[j + m] : _blend(s[j + m], s[j + m - n], (j - n + m + 1) / (m + 1)),
  ];
}

Frame _blend(Frame a, Frame b, double w) {
  final o = Frame(a.width, a.height);
  for (var i = 0; i < o.rgb.length; i++) {
    o.rgb[i] = (a.rgb[i] + (b.rgb[i] - a.rgb[i]) * w).round();
  }
  return o;
}

/// Mean absolute channel difference, 0..255.
double _distance(Frame a, Frame b) {
  var d = 0;
  for (var i = 0; i < a.rgb.length; i++) {
    d += (a.rgb[i] - b.rgb[i]).abs();
  }
  return d / a.rgb.length;
}

/// [seconds] of [generator] after [warmup], cut wherever it ends.
List<Frame> renderFrames({
  required Generator generator,
  required Params params,
  required Palette palette,
  required int width,
  required int height,
  double seconds = 4,
  int fps = 20,
  double warmup = 1.5,
  int seed = 1,
  double timeScale = 1,
}) {
  final effect = generator.create(width, height, seed);
  final out = Frame(width, height);
  final dt = timeScale / fps;
  var t = 0.0;
  for (var i = (warmup * fps).round(); i > 0; i--) {
    effect.render(out, t, dt, params, palette);
    t += dt;
  }
  final frames = <Frame>[];
  for (var i = max(1, (seconds * fps).round()); i > 0; i--) {
    effect.render(out, t, dt, params, palette);
    frames.add(out.copy());
    t += dt;
  }
  return frames;
}

/// Encodes [frames] (all the same size) as an infinitely looping GIF.
///
/// With up to 255 distinct colours across the whole animation (effects that
/// only draw palette colours) the GIF is pixel-identical to the input; beyond
/// that one shared 255-colour palette is used, without dithering. Runs of
/// identical frames become a single longer GIF frame; [BakeResult.frameCount]
/// still counts the input frames.
BakeResult bakeFrames(List<Frame> frames, {int fps = 20}) {
  if (frames.isEmpty) throw ArgumentError('No frames to bake');
  if (fps <= 0) throw ArgumentError.value(fps, 'fps', 'must be positive');
  // GIF delays are whole centiseconds. Round each frame's end time rather
  // than each delay, so 30 fps alternates 3/4/3 and the total stays exact;
  // browsers slow anything under 2, so never go below that.
  final delays = List<int>.filled(frames.length, 0);
  var total = 0;
  for (var i = 0; i < frames.length; i++) {
    final end = ((i + 1) * 100 + fps ~/ 2) ~/ fps;
    delays[i] = max(2, end - total);
    total += delays[i];
  }
  return BakeResult(
    encodeGif(frames, delays),
    frames.length,
    Duration(milliseconds: total * 10),
  );
}
