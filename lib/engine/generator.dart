import 'frame.dart';
import 'palette.dart';

/// A tweakable number exposed by a generator, e.g. "speed" or "density".
class ParamSpec {
  const ParamSpec(this.key, this.label,
      {this.min = 0, this.max = 1, this.defaultValue = 0.5});

  final String key;
  final String label;
  final double min;
  final double max;
  final double defaultValue;
}

/// Describes an animation algorithm. Library entries are data that point at a
/// generator id plus params and a palette, so the catalog can grow without
/// shipping new code.
abstract class Generator {
  String get id;
  String get name;
  String get defaultPalette => 'rainbow';
  List<ParamSpec> get params => const [];

  /// Follows something only the phone knows (e.g. what's playing), so it
  /// can't be baked into a GIF and sent to the device.
  bool get liveOnly => false;

  /// Creates per-run state (particles, heat buffers, …) for a matrix size.
  EffectInstance create(int width, int height, int seed);
}

abstract class EffectInstance {
  /// Draws into [out]. [t] is seconds since start, [dt] seconds since the last
  /// frame. Instances may keep state between calls and must not assume [out]
  /// was cleared.
  void render(Frame out, double t, double dt, Params p, Palette pal);
}

class Params {
  Params(this._values);

  final Map<String, double> _values;

  double operator [](String key) => _values[key] ?? 0.5;

  static Params defaultsFor(Generator g, [Map<String, double>? overrides]) =>
      Params({
        for (final s in g.params) s.key: s.defaultValue,
        ...?overrides,
      });

  Map<String, double> toMap() => Map.of(_values);
}
