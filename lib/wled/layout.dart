import 'dart:typed_data';

import '../engine/frame.dart';

/// Maps the logical frame (row-major, top-left origin) to the byte order the
/// LEDs expect over DDP.
///
/// The identity layout is right whenever the device has a 2D matrix set up in
/// LED Preferences and "Use LED map for realtime" (cfg if.live.rlm) on: WLED
/// then applies its own panel/serpentine mapping to realtime data. The other
/// options are for devices configured as a plain 1D strip.
///
/// Transforms apply in order: [rotation] (quarter turns clockwise), [flipX],
/// [flipY], then [serpentine] (odd physical rows run right-to-left). Quarter
/// turns 1 and 3 only make sense on a square matrix and are ignored otherwise.
class MatrixLayout {
  const MatrixLayout(
      {this.rotation = 0,
      this.flipX = false,
      this.flipY = false,
      this.serpentine = false});

  final int rotation;
  final bool flipX;
  final bool flipY;
  final bool serpentine;

  static const identity = MatrixLayout();

  bool get isIdentity => rotation % 4 == 0 && !flipX && !flipY && !serpentine;

  /// Returns the LED-ordered bytes. For the identity layout this is [f.rgb]
  /// itself; otherwise a buffer owned by this layout that is overwritten on
  /// the next call, so send it before rendering again.
  Uint8List apply(Frame f) {
    if (isIdentity) return f.rgb;
    final cache = _caches[this] ??= _Cache();
    if (cache.width != f.width || cache.height != f.height) {
      cache
        ..width = f.width
        ..height = f.height
        ..map = _buildMap(f.width, f.height)
        ..out = Uint8List(f.rgb.length);
    }
    final map = cache.map, out = cache.out, src = f.rgb;
    for (var i = 0; i < map.length; i++) {
      final s = i * 3, d = map[i] * 3;
      out[d] = src[s];
      out[d + 1] = src[s + 1];
      out[d + 2] = src[s + 2];
    }
    return out;
  }

  /// Destination LED index for each logical pixel.
  Int32List _buildMap(int w, int h) {
    final map = Int32List(w * h);
    final quarter = w == h ? rotation % 4 : (rotation % 4 == 2 ? 2 : 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var (px, py) = switch (quarter) {
          1 => (w - 1 - y, x),
          2 => (w - 1 - x, h - 1 - y),
          3 => (y, h - 1 - x),
          _ => (x, y),
        };
        if (flipX) px = w - 1 - px;
        if (flipY) py = h - 1 - py;
        if (serpentine && py.isOdd) px = w - 1 - px;
        map[y * w + x] = py * w + px;
      }
    }
    return map;
  }

  MatrixLayout copyWith(
          {int? rotation, bool? flipX, bool? flipY, bool? serpentine}) =>
      MatrixLayout(
        rotation: rotation ?? this.rotation,
        flipX: flipX ?? this.flipX,
        flipY: flipY ?? this.flipY,
        serpentine: serpentine ?? this.serpentine,
      );

  Map<String, dynamic> toJson() => {
        'rotation': rotation,
        'flipX': flipX,
        'flipY': flipY,
        'serpentine': serpentine,
      };

  factory MatrixLayout.fromJson(Map json) => MatrixLayout(
        rotation: (json['rotation'] as num?)?.toInt() ?? 0,
        flipX: json['flipX'] == true,
        flipY: json['flipY'] == true,
        serpentine: json['serpentine'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is MatrixLayout &&
      other.rotation % 4 == rotation % 4 &&
      other.flipX == flipX &&
      other.flipY == flipY &&
      other.serpentine == serpentine;

  @override
  int get hashCode => Object.hash(rotation % 4, flipX, flipY, serpentine);

  static final _caches = Expando<_Cache>();
}

class _Cache {
  int width = -1, height = -1;
  Int32List map = Int32List(0);
  Uint8List out = Uint8List(0);
}
