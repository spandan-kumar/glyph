import 'dart:convert';
import 'dart:typed_data';

import 'frame.dart';
import 'generator.dart';
import 'palette.dart';

/// A fixed sequence of frames: pixel-editor drawings, imported GIFs, baked
/// text. Plays through [ClipGenerator] so it streams and saves like any effect.
class FrameClip {
  FrameClip({
    required this.width,
    required this.height,
    required this.frames,
    required this.delaysMs,
  }) : assert(frames.isNotEmpty && frames.length == delaysMs.length);

  factory FrameClip.uniform(List<Frame> frames, {int fps = 10}) => FrameClip(
        width: frames.first.width,
        height: frames.first.height,
        frames: frames,
        delaysMs: List.filled(frames.length, (1000 / fps).round()),
      );

  final int width;
  final int height;
  final List<Frame> frames;
  final List<int> delaysMs;

  int get totalMs => delaysMs.fold(0, (a, b) => a + b);

  /// Approximate frames per second, for encoders that take a single rate.
  int get averageFps =>
      (frames.length * 1000 / totalMs.clamp(1, 1 << 30)).round().clamp(1, 60);

  /// Nearest-neighbour fit into [w]×[h], letterboxed and centred.
  FrameClip fitTo(int w, int h) {
    if (w == width && h == height) return this;
    final scale = (w / width) < (h / height) ? w / width : h / height;
    final dw = (width * scale).round().clamp(1, w), dh = (height * scale).round().clamp(1, h);
    final ox = (w - dw) ~/ 2, oy = (h - dh) ~/ 2;
    final out = <Frame>[];
    for (final f in frames) {
      final o = Frame(w, h);
      for (var y = 0; y < dh; y++) {
        for (var x = 0; x < dw; x++) {
          o.set(ox + x, oy + y, f.get(x * width ~/ dw, y * height ~/ dh));
        }
      }
      out.add(o);
    }
    return FrameClip(width: w, height: h, frames: out, delaysMs: delaysMs);
  }

  Map<String, dynamic> toJson() => {
        'w': width,
        'h': height,
        'delays': delaysMs,
        'frames': [for (final f in frames) base64Encode(f.rgb)],
      };

  factory FrameClip.fromJson(Map<String, dynamic> j) {
    final w = j['w'] as int, h = j['h'] as int;
    return FrameClip(
      width: w,
      height: h,
      delaysMs: [for (final d in j['delays'] as List) d as int],
      frames: [
        for (final s in j['frames'] as List)
          Frame(w, h)..rgb.setAll(0, base64Decode(s as String)),
      ],
    );
  }
}

/// Plays a [FrameClip] on loop. The palette is ignored: clips carry real
/// colours. Params: `speed` scales playback rate.
class ClipGenerator extends Generator {
  ClipGenerator(this.clip, {this.title = 'Clip'});

  final FrameClip clip;
  final String title;

  @override
  String get id => '_clip';
  @override
  String get name => title;
  @override
  List<ParamSpec> get params =>
      const [ParamSpec('speed', 'Speed', min: 0.25, max: 3, defaultValue: 1)];

  @override
  EffectInstance create(int width, int height, int seed) =>
      _ClipInstance(clip.fitTo(width, height));
}

class _ClipInstance extends EffectInstance {
  _ClipInstance(this.clip) : _ends = _cumulative(clip.delaysMs);

  final FrameClip clip;
  final List<int> _ends;
  double _ms = 0;

  static List<int> _cumulative(List<int> d) {
    var acc = 0;
    return [for (final x in d) acc += x.clamp(10, 60000)];
  }

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    _ms = (_ms + dt * 1000 * p['speed']) % _ends.last;
    var i = 0;
    while (i < _ends.length - 1 && _ms >= _ends[i]) {
      i++;
    }
    out.rgb.setAll(0, clip.frames[i].rgb);
  }
}

/// Helper for tests and encoders that want the raw bytes of every frame.
List<Uint8List> clipBytes(FrameClip c) => [for (final f in c.frames) f.rgb];
