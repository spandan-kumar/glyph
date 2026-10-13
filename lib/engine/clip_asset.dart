import 'dart:typed_data';

import 'bake_limits.dart';
import 'clip.dart';
import 'frame.dart';
import 'generator.dart';
import 'palette.dart';

/// A content-addressed clip. The index is small; pixels load separately.
class ClipAsset {
  const ClipAsset({
    required this.id,
    required this.title,
    required this.sha256,
    required this.bytes,
    required this.width,
    required this.height,
    required this.frames,
  });
  final String id, title, sha256;
  final int bytes, width, height, frames;
  String get path => 'collections/imported/$sha256.clip.gz';
}

abstract final class ClipAssetLibrary {
  static final _generators = <String, AssetClipGenerator>{};
  static final _clips = <String, FrameClip>{};
  static const maxCachedPixels = 4 * 1024 * 1024;
  static int _pixels = 0;

  static void register(Iterable<ClipAsset> assets) {
    for (final asset in assets) {
      _generators[asset.id] = AssetClipGenerator(asset);
    }
  }

  static AssetClipGenerator? byId(String id) => _generators[id];
  static FrameClip? cached(String sha) {
    final clip = _clips.remove(sha);
    if (clip != null) _clips[sha] = clip;
    return clip;
  }

  static void retain(String sha, FrameClip clip) {
    final old = _clips.remove(sha);
    if (old != null) _pixels -= old.width * old.height * old.frames.length;
    _clips[sha] = clip;
    _pixels += clip.width * clip.height * clip.frames.length;
    while (_pixels > maxCachedPixels && _clips.length > 1) {
      final removed = _clips.remove(_clips.keys.first)!;
      _pixels -= removed.width * removed.height * removed.frames.length;
    }
  }

  static void clearCache() {
    _clips.clear();
    _pixels = 0;
  }
}

/// Preview instances adopt pixels when they arrive; render never does I/O.
class AssetClipGenerator extends Generator {
  AssetClipGenerator(this.asset);
  final ClipAsset asset;
  @override
  String get id => asset.id;
  @override
  String get name => asset.title;
  @override
  List<ParamSpec> get params => const [
    ParamSpec('speed', 'Speed', min: 0.25, max: 3, defaultValue: 1),
  ];
  @override
  EffectInstance create(int width, int height, int seed) =>
      _AssetInstance(asset, width, height, seed);

  ClipGenerator loaded(FrameClip clip) => _LoadedClip(asset, clip);
}

class _LoadedClip extends ClipGenerator {
  _LoadedClip(this.asset, FrameClip clip) : super(clip, title: asset.title);
  final ClipAsset asset;
  @override
  String get id => asset.id;
}

class _AssetInstance extends EffectInstance {
  _AssetInstance(this.asset, this.width, this.height, this.seed);
  final ClipAsset asset;
  final int width, height, seed;
  EffectInstance? _delegate;
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    if (_delegate == null) {
      final clip = ClipAssetLibrary.cached(asset.sha256);
      if (clip != null) {
        _delegate = ClipGenerator(clip).create(width, height, seed);
      }
    }
    if (_delegate == null) {
      out.rgb.fillRange(0, out.rgb.length, 0);
    } else {
      _delegate!.render(out, t, dt, p, pal);
    }
  }
}

/// Decodes an already bounded, uncompressed GLC1 payload.
FrameClip decodeClipAsset(Uint8List bytes, ClipAsset expected) {
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'GLC1') {
    throw const FormatException('Invalid animation file');
  }
  final data = ByteData.sublistView(bytes);
  final w = data.getUint16(4, Endian.little),
      h = data.getUint16(6, Endian.little);
  final n = data.getUint32(8, Endian.little);
  if (w != expected.width || h != expected.height || n != expected.frames) {
    throw const FormatException('Animation dimensions or frame count changed');
  }
  checkBakeSize(w, h, n);
  final pixels = w * h * 3;
  if (bytes.length != 12 + n * (4 + pixels)) {
    throw const FormatException('Incomplete animation file');
  }
  final frames = <Frame>[], delays = <int>[];
  var at = 12;
  for (var i = 0; i < n; i++) {
    final ms = data.getUint32(at, Endian.little);
    if (ms == 0 || ms > 655350) {
      throw const FormatException('Invalid frame timing');
    }
    delays.add(ms);
    at += 4;
    frames.add(
      Frame(w, h)..rgb.setAll(0, Uint8List.sublistView(bytes, at, at + pixels)),
    );
    at += pixels;
  }
  return FrameClip(width: w, height: h, frames: frames, delaysMs: delays);
}
