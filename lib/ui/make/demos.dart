import 'dart:math';
import 'dart:typed_data';

import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../../features/audio/audio_engine.dart';
import '../../features/audio/visualizers.dart';
import '../../features/editor/templates.dart';
import '../../features/games/catalog.dart';
import '../../features/games/core/game_generator.dart';
import '../../features/now_playing/cover_art.dart';
import '../../features/now_playing/now_playing.dart';
import '../../features/now_playing/now_playing_generator.dart';
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

/// Snap, an original little instant camera whose lens is its eye: it looks
/// about, blinks, pops its flash and a picture slides out and develops —
/// the kind of thing people bring in as a GIF. Lit on dark for LED panels.
final FrameClip gifDemoClip = _gifDemo();

const _snapInk = {
  'B': 0xFF8A5C, // body
  'b': 0xC4523A, // grip band
  'R': 0xE4E4EE, // lens ring / eyelid
  'L': 0x3A78FF, // lens
  'k': 0x0A1430, // pupil
  'H': 0xFFFFFF, // glint
  'S': 0xFF3B6B, // shutter button
  'F': 0xFFD54A, // flash
  'W': 0xFFFFFF, // flash burst
  'd': 0x262632, // slot / undeveloped photo
  'P': 0xF2F2F2, // photo border
  's': 0x5EC8FF, // photo sky
  'u': 0xFFD54A, // photo sun
  'm': 0x4CD07A, // photo hill
};

// 14x9, drawn at (1, 1). Lens interior: rows 3-6.
const _snapBody = [
  '..SS......FF..',
  '.BBBBBBBBBBBB.',
  'BBBBBRRRRBBBBB',
  'BBBBRLLLLRBBBB',
  'bbbRLLLLLLRbbb',
  'bbbRLLLLLLRbbb',
  'BBBBRLLLLRBBBB',
  'BBBBBRRRRBBBBB',
  '.BBBBddddBBBB.',
];

// 8x6 photo, slides out of the slot under the camera at (4, 10).
const _snapPhoto = [
  'PPPPPPPP',
  'PsssssuP',
  'PsmmsssP',
  'PmmmmssP',
  'PmmmmmmP',
  'PPPPPPPP',
];

/// [look]: pupil column offset (-1 left, 0 centre, 1 right); [shown]: photo
/// rows out of the slot; [develop]: 0 blank .. 1 full colour.
Frame _snap({int look = 0, bool blink = false, bool flash = false, int shown = 0, double develop = 0}) {
  final f = Frame(16, 16);
  void dot(int x, int y, int c) {
    if (x >= 0 && y >= 0 && x < 16 && y < 16) f.set(x, y, c);
  }

  for (var y = 0; y < _snapBody.length; y++) {
    for (var x = 0; x < _snapBody[y].length; x++) {
      var ch = _snapBody[y][x];
      if (ch == '.') continue;
      if (ch == 'L' && blink) ch = y == 5 ? 'b' : 'R';
      if (ch == 'F' && flash) ch = 'W';
      dot(1 + x, 1 + y, _snapInk[ch]!);
    }
  }
  if (!blink) {
    // A 2x2 pupil with a glint, sliding to look around.
    final px = 1 + 6 + look, py = 1 + 4;
    for (final (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)]) {
      dot(px + dx, py + dy, _snapInk['k']!);
    }
    dot(px + 1, py, _snapInk['H']!);
  }
  if (flash) {
    for (final (x, y) in [(10, 0), (14, 0), (9, 1), (15, 1)]) {
      dot(x, y, 0xFFF3B0);
    }
  }
  for (var r = 0; r < shown && r < _snapPhoto.length; r++) {
    final row = _snapPhoto[_snapPhoto.length - shown + r];
    for (var x = 0; x < row.length; x++) {
      final ch = row[x];
      final c = ch == 'P'
          ? _snapInk['P']!
          : develop <= 0
              ? _snapInk['d']!
              : scaleColor(_snapInk[ch]!, 0.25 + 0.75 * develop);
      dot(4 + x, 10 + r, c);
    }
  }
  return f;
}

FrameClip _gifDemo() {
  final frames = <Frame>[
    _snap(look: 1),
    _snap(blink: true),
    _snap(look: -1),
    _snap(flash: true),
    _snap(shown: 3),
    _snap(shown: 6, develop: 0.35),
    _snap(shown: 6, develop: 1),
    _snap(shown: 6, develop: 1, blink: true),
  ];
  return FrameClip(width: 16, height: 16, frames: frames, delaysMs: const [700, 140, 500, 160, 180, 260, 900, 140]);
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

/// A timer counting down from ten at double speed, pulsing through the
/// last seconds, bursting into "GO!" at zero, then starting over.
Generator timerDemo() => _TimerDemo();

class _TimerDemo extends Generator {
  @override
  String get id => '_timer_demo';
  @override
  String get name => 'Timer';
  @override
  String get defaultPalette => 'sunset';

  @override
  EffectInstance create(int width, int height, int seed) => _TimerDemoInstance(width, height);
}

class _TimerDemoInstance extends EffectInstance {
  _TimerDemoInstance(this.w, this.h);

  static const _from = 10; // seconds on the timer
  static const _pace = 2.0; // demo seconds per real second
  static const _cycle = _from / _pace + 2.4; // count down, celebrate, repeat

  static final _epoch = DateTime(2026);
  static final _settings = TextSettings(
    font: 'bold',
    large: true,
    colorMode: 'animated',
    palette: 'sunset',
    durationSec: _from,
    doneText: 'GO!',
  );

  final int w, h;
  CountdownInstance? _run;
  double _start = 0;
  DateTime _now = _epoch;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    if (_run == null || t - _start >= _cycle) {
      _start = t;
      // The countdown reads the time through [_now], so it runs on demo time.
      _run = CountdownInstance(_settings, w, h, () => _now, _epoch.add(const Duration(seconds: _from)));
    }
    _now = _epoch.add(Duration(microseconds: ((t - _start) * _pace * 1e6).round()));
    _run!.render(out, t, dt, p, pal);
  }
}

/// Spectrum bars dancing to their own idle beat (no microphone).
Generator musicDemo() => SpectrumBars(_Quiet());

class _Quiet implements AudioFeed {
  @override
  AudioFeatures get latest => AudioFeatures.silence;
}

/// Snake playing itself.
Generator playDemo() => GameGenerator(gameById('snake'));

/// Now Playing running through three made-up songs with covers drawn here
/// (a sunset, a record, a bloom): never real album art.
Generator nowPlayingDemo() => NowPlayingGenerator(_DemoTracks());

class _DemoTracks implements NowPlayingFeed {
  static const _songMs = 7000;
  static final _songs = [
    ('Golden Hour', 'Pixel Coast', _sunsetCover()),
    ('Spin Cycle', 'The Grooves', _recordCover()),
    ('Petal Pop', 'Bloom Club', _bloomCover()),
  ];
  final _start = DateTime.now();

  @override
  NowPlaying get current {
    final now = DateTime.now();
    final ms = now.difference(_start).inMilliseconds;
    final (title, artist, art) = _songs[(ms ~/ _songMs) % _songs.length];
    return NowPlaying(
      title: title,
      artist: artist,
      durationMs: _songMs,
      positionMs: ms % _songMs,
      at: now,
      art: art,
      artSize: _coverSize,
    );
  }
}

const _coverSize = 32;

Uint8List _cover(int Function(double x, double y) paint) {
  final out = Uint8List(_coverSize * _coverSize * 3);
  for (var y = 0; y < _coverSize; y++) {
    for (var x = 0; x < _coverSize; x++) {
      final c = paint((x + 0.5) / _coverSize, (y + 0.5) / _coverSize);
      final i = (y * _coverSize + x) * 3;
      out[i] = (c >> 16) & 0xFF;
      out[i + 1] = (c >> 8) & 0xFF;
      out[i + 2] = c & 0xFF;
    }
  }
  return out;
}

Uint8List _sunsetCover() => _cover((x, y) {
      if (y > 0.66) return (y * 40).floor().isEven ? 0x123C6E : 0x0B2550; // sea
      final sun = (x - 0.5) * (x - 0.5) + (y - 0.6) * (y - 0.6) < 0.05;
      return sun ? 0xFFD447 : lerpColor(0x5A1E8C, 0xFF7A3D, y / 0.66);
    });

Uint8List _recordCover() => _cover((x, y) {
      final r = sqrt((x - 0.5) * (x - 0.5) + (y - 0.5) * (y - 0.5));
      if (r < 0.1) return 0xFF3B5C; // label
      if (r < 0.44) return (r * 30).floor().isEven ? 0x111116 : 0x23232C; // grooves
      return 0x18C4B4;
    });

Uint8List _bloomCover() => _cover((x, y) {
      final dx = x - 0.5, dy = y - 0.5;
      final a = atan2(dy, dx), r = sqrt(dx * dx + dy * dy);
      if (r < 0.1) return 0xFFE14D;
      if (r < 0.2 + 0.18 * cos(a * 5).abs()) return 0xFF5FA8;
      return 0x2B3AA8;
    });
