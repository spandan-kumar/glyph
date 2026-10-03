import 'dart:math';

import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../features/audio/audio_engine.dart';
import '../../features/audio/visualizers.dart';
import '../../features/editor/templates.dart';
import '../../features/games/catalog.dart';
import '../../features/games/core/game_generator.dart';
import '../../features/text/text_generators.dart';
import '../../features/text/text_settings.dart';

// Self-demonstrating previews for the Make studio tiles (UX.md, J5): each
// tile shows what the tool makes instead of an icon.

/// A pixel heart being drawn: the outline as one stroke, then the fill
/// row by row, with a bright "pen" pixel; holds, then starts over.
final FrameClip drawDemoClip = _drawDemo();

FrameClip _drawDemo() {
  final heart = editorTemplates.firstWhere((t) => t.name == 'Heart').build(16, 16).frames.first;
  bool lit(int x, int y) =>
      x >= 0 && y >= 0 && x < 16 && y < 16 && heart.get(x, y) != 0;

  final outline = <(int, int)>[], fill = <(int, int)>[];
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      if (!lit(x, y)) continue;
      final edge = !lit(x - 1, y) || !lit(x + 1, y) || !lit(x, y - 1) || !lit(x, y + 1);
      (edge ? outline : fill).add((x, y));
    }
  }
  // Trace the outline clockwise from the dip between the lobes.
  const cx = 7.5, cy = 7.5;
  double angle((int, int) p) => (atan2(p.$2 - cy, p.$1 - cx) + pi / 2 + 2 * pi) % (2 * pi);
  outline.sort((a, b) => angle(a).compareTo(angle(b)));
  // Fill in serpentine rows, like a hand going back and forth.
  fill.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : (a.$2.isEven ? a.$1 - b.$1 : b.$1 - a.$1));

  final frames = <Frame>[], delays = <int>[];
  final canvas = Frame(16, 16);
  void strokes(List<(int, int)> pts, int perFrame, int ms) {
    for (var i = 0; i < pts.length; i += perFrame) {
      final end = min(i + perFrame, pts.length);
      for (var j = i; j < end; j++) {
        canvas.set(pts[j].$1, pts[j].$2, heart.get(pts[j].$1, pts[j].$2));
      }
      final f = canvas.copy();
      final (px, py) = pts[end - 1];
      f.set(px, py, 0xFFFFFF);
      frames.add(f);
      delays.add(ms);
    }
  }

  frames.add(Frame(16, 16));
  delays.add(400);
  strokes(outline, 2, 60);
  strokes(fill, 4, 55);
  frames.add(canvas.copy());
  delays.add(1600);
  return FrameClip(width: 16, height: 16, frames: frames, delaysMs: delays);
}

/// A little pixel alien walking in place over drifting stars — the kind of
/// sprite people bring in as a GIF.
final FrameClip gifDemoClip = _gifDemo();

const _alienA = [
  '..X.....X..',
  '...X...X...',
  '..XXXXXXX..',
  '.XX.XXX.XX.',
  'XXXXXXXXXXX',
  'X.XXXXXXX.X',
  'X.X.....X.X',
  '...XX.XX...',
];
const _alienB = [
  '..X.....X..',
  'X..X...X..X',
  'X.XXXXXXX.X',
  'XXX.XXX.XXX',
  'XXXXXXXXXXX',
  '.XXXXXXXXX.',
  '..X.....X..',
  '.X.......X.',
];

FrameClip _gifDemo() {
  const stars = [(2, 1, 0x6B6BFF), (9, 2, 0xFFFFFF), (14, 0, 0xFFB547), (5, 14, 0xFFFFFF), (12, 13, 0x6BFFD0), (0, 12, 0xFF6AD5)];
  final frames = <Frame>[];
  for (var i = 0; i < 16; i++) {
    final f = Frame(16, 16);
    for (final (x, y, c) in stars) {
      f.set((x - i) % 16, y, scaleColor(c, i.isEven ? 0.55 : 0.35));
    }
    final sprite = (i ~/ 2).isEven ? _alienA : _alienB;
    final oy = 4 + ((i ~/ 4).isEven ? 0 : 1);
    for (var y = 0; y < sprite.length; y++) {
      for (var x = 0; x < sprite[y].length; x++) {
        if (sprite[y][x] == 'X') f.set(2 + x, oy + y, 0x7CFF6B);
      }
    }
    frames.add(f);
  }
  return FrameClip.uniform(frames, fps: 8);
}

/// "HELLO" scrolling in rainbow letters.
Generator writeDemo() => ScrollingText(TextSettings(
      text: 'HELLO',
      font: 'classic',
      large: false,
      colorMode: 'rainbow',
      speed: 0.3,
    ));

/// The clock, with seconds running round the edge.
Generator clockDemo() => ClockGenerator(TextSettings(
      font: 'tiny',
      colorMode: 'animated',
      palette: 'ocean',
      seconds: true,
      date: false,
    ));

/// Spectrum bars dancing to their own idle beat (no microphone).
Generator musicDemo() => SpectrumBars(_Quiet());

class _Quiet implements AudioFeed {
  @override
  AudioFeatures get latest => AudioFeatures.silence;
}

/// Snake playing itself.
Generator playDemo() => GameGenerator(gameById('snake'));
