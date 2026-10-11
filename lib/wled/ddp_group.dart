import 'dart:typed_data';

import '../engine/frame.dart';
import '../engine/led_gamma.dart';
import 'ddp.dart';
import 'device.dart';
import 'layout.dart';

/// One matrix in a streaming group. [width]/[height] null means "same as the
/// rendered frame" (the primary device); otherwise frames are scaled to that
/// size with nearest-neighbour sampling before [layout] applies.
///
/// [color] is how that WLED gamma-corrects colours; frames are corrected to
/// match (see [LedColorConfig.streamCorrection]). Null looks the host up in
/// [knownLedColor] when the group opens, else assumes WLED's defaults.
class DdpTarget {
  const DdpTarget(
    this.host, {
    this.layout = MatrixLayout.identity,
    this.width,
    this.height,
    this.port = ddpPort,
    this.color,
  });

  final String host;
  final MatrixLayout layout;
  final int? width, height;
  final int port;
  final LedColorConfig? color;

  DdpTarget copyWith({MatrixLayout? layout, int? width, int? height, LedColorConfig? color}) => DdpTarget(
    host,
    layout: layout ?? this.layout,
    width: width ?? this.width,
    height: height ?? this.height,
    port: port,
    color: color ?? this.color,
  );

  /// [color], else the last config read from [host], else WLED's defaults.
  LedColorConfig get resolvedColor =>
      color ?? knownLedColor[host.toLowerCase()] ?? LedColorConfig.unknown;

  @override
  bool operator ==(Object other) =>
      other is DdpTarget &&
      other.host == host &&
      other.layout == layout &&
      other.width == width &&
      other.height == height &&
      other.port == port &&
      other.color == color;

  @override
  int get hashCode => Object.hash(host, layout, width, height, port, color);

  @override
  String toString() => 'DdpTarget($host${width != null ? ' ${width}x$height' : ''})';
}

/// Mirrors every frame to several WLEDs. The first target is the primary:
/// failing to open it throws, while unreachable secondaries are skipped and
/// listed in [failedHosts]. Duplicate host:port targets are dropped (first
/// one wins), so the primary can safely also appear among the mirrors.
class DdpGroupSender {
  DdpGroupSender(List<DdpTarget> targets) : targets = _dedupe(targets);

  final List<DdpTarget> targets;
  final _senders = <DdpTarget, DdpSender>{};
  final _scalers = <DdpTarget, _Scaler>{};
  final _corrections = <DdpTarget, LedCorrection>{};
  final failedHosts = <String>[];

  bool get isOpen => _senders.isNotEmpty;

  /// Hosts currently receiving frames.
  List<String> get activeHosts => [for (final t in _senders.keys) t.host];

  DdpSender? get primary => targets.isEmpty ? null : _senders[targets.first];

  int get framesSent => primary?.framesSent ?? 0;

  /// Dropped frames summed over every target.
  int get errors => _senders.values.fold(0, (s, x) => s + x.errors);

  Future<void> open() async {
    for (final (i, t) in targets.indexed) {
      final s = DdpSender(t.host, port: t.port);
      try {
        await s.open();
        _senders[t] = s;
        _corrections[t] = t.resolvedColor.streamCorrection();
      } catch (_) {
        if (i == 0) {
          close();
          rethrow;
        }
        failedHosts.add(t.host);
      }
    }
  }

  void send(Frame f, {Frame? overrideFrame, String? overrideHost}) {
    for (final MapEntry(key: t, value: s) in _senders.entries) {
      final source = t.host == overrideHost && overrideFrame != null ? overrideFrame : f;
      final w = t.width ?? source.width, h = t.height ?? source.height;
      final out = w == source.width && h == source.height ? source : (_scalers[t] ??= _Scaler()).scale(source, w, h);
      final bytes = t.layout.apply(out);
      final c = _corrections[t];
      s.send(c == null ? bytes : c.apply(bytes));
    }
  }

  /// Correction in use for [target] while open (for tests and diagnostics).
  LedCorrection? correctionFor(DdpTarget target) => _corrections[target];

  void close() {
    for (final s in _senders.values) {
      s.close();
    }
    _senders.clear();
    _corrections.clear();
  }

  static List<DdpTarget> _dedupe(List<DdpTarget> targets) {
    final seen = <String>{};
    return [
      for (final t in targets)
        if (seen.add('${t.host.toLowerCase()}:${t.port}')) t,
    ];
  }
}

/// Nearest-neighbour resize into a reused frame, sampling pixel centres so a
/// 2× upscale duplicates pixels exactly and a downscale stays centred.
class _Scaler {
  Frame? _out;
  Int32List _map = Int32List(0);
  int _sw = -1, _sh = -1;

  Frame scale(Frame src, int w, int h) {
    var out = _out;
    if (out == null || out.width != w || out.height != h || _sw != src.width || _sh != src.height) {
      out = _out = Frame(w, h);
      _sw = src.width;
      _sh = src.height;
      _map = Int32List(w * h);
      for (var y = 0; y < h; y++) {
        final sy = ((y + 0.5) * src.height / h).floor().clamp(0, src.height - 1);
        for (var x = 0; x < w; x++) {
          final sx = ((x + 0.5) * src.width / w).floor().clamp(0, src.width - 1);
          _map[y * w + x] = (sy * src.width + sx) * 3;
        }
      }
    }
    final s = src.rgb, d = out.rgb, map = _map;
    for (var i = 0; i < map.length; i++) {
      final o = map[i], j = i * 3;
      d[j] = s[o];
      d[j + 1] = s[o + 1];
      d[j + 2] = s[o + 2];
    }
    return out;
  }
}

/// Nearest-neighbour resize of [src] to [w]×[h] (a new frame).
Frame scaleFrameNearest(Frame src, int w, int h) => _Scaler().scale(src, w, h);
