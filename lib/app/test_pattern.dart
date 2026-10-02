import '../engine/frame.dart';
import '../engine/generator.dart';
import '../engine/palette.dart';

/// Orientation check: red top-left, green top-right, blue bottom-left, and a
/// white bar along the top. If the matrix shows anything else, the layout
/// settings need adjusting.
class TestPattern extends Generator {
  @override
  String get id => '_test';
  @override
  String get name => 'Orientation test';

  @override
  EffectInstance create(int width, int height, int seed) => _TestPattern();
}

class _TestPattern extends EffectInstance {
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final w = out.width, h = out.height;
    final k = (w / 5).ceil().clamp(1, 4);
    out.fill(0);
    for (var x = 0; x < w; x++) {
      out.set(x, 0, 0x303030);
    }
    // A dot sweeps along the top row to show the scan direction.
    out.set((t * 6).floor() % w, 0, 0xFFFFFF);
    for (var y = 0; y < k; y++) {
      for (var x = 0; x < k; x++) {
        out.set(x, y + 1, 0xFF0000);
        out.set(w - 1 - x, y + 1, 0x00FF00);
        out.set(x, h - 1 - y, 0x0000FF);
      }
    }
  }
}
