import 'dart:math';

import '../../engine/clip.dart';
import '../../engine/generator.dart';
import '../../engine/gif_baker.dart';
import '../../engine/palette.dart';
import 'text_generators.dart';
import 'text_settings.dart';

/// Runs in a worker isolate so full scrolling messages don't block the UI.
FrameClip bakeTextClip((TextSettings, String, int, int) request) {
  final (settings, mode, width, height) = request;
  final Generator generator = switch (mode) {
    'clock' => ClockGenerator(settings),
    'countdown' => CountdownGenerator(settings),
    _ => ScrollingText(settings),
  };
  var seconds = 4.0;
  if (mode == 'text') {
    seconds = (generator.create(width, height, 1) as TextInstance).loopSeconds ?? seconds;
  }
  final fps = min(20, max(8, (240 / seconds).floor()));
  final frames = renderFrames(
    generator: generator,
    params: Params({}),
    palette: paletteById(settings.palette),
    width: width,
    height: height,
    seconds: seconds,
    fps: fps,
    warmup: settings.background.isEmpty ? 0 : 1.5,
  );
  return FrameClip.uniform(frames, fps: fps);
}
