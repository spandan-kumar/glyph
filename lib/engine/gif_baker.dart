import 'dart:math';
import 'dart:typed_data';

import 'frame.dart';
import 'generator.dart';
import 'gif_encoder.dart';
import 'palette.dart';

class BakeResult {
  const BakeResult(this.bytes, this.frameCount, this.duration);

  final Uint8List bytes;
  final int frameCount;
  final Duration duration;
}

/// Renders [seconds] of [generator] and encodes it as a looping GIF.
/// Stateful effects (fire, particles, trails) are run for [warmup] seconds
/// first so the GIF doesn't start on an empty screen. [timeScale] plays the
/// effect faster or slower, matching a library item's speed.
BakeResult bakeGif({
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
}) =>
    bakeFrames(
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

/// The frames [bakeGif] would encode.
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
