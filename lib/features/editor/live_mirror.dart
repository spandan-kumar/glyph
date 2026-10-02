import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';

/// Streams whatever the editor is showing. [source] is read every render
/// tick; the fitted copy is only rebuilt when the frame or [revision] changes,
/// so drawing never waits on the stream.
class LiveMirrorGenerator extends Generator {
  LiveMirrorGenerator({required this.source, required this.revision, this.title = 'Drawing'});

  final Frame Function() source;
  final int Function() revision;
  final String title;

  @override
  String get id => '_editor_live';
  @override
  String get name => title;

  @override
  EffectInstance create(int width, int height, int seed) => _LiveInstance(this);
}

class _LiveInstance extends EffectInstance {
  _LiveInstance(this.g);

  final LiveMirrorGenerator g;
  Frame? _src, _fitted;
  int _rev = -1;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    final src = g.source(), rev = g.revision();
    var fitted = _fitted;
    if (fitted == null ||
        !identical(src, _src) ||
        rev != _rev ||
        fitted.width != out.width ||
        fitted.height != out.height) {
      fitted = FrameClip(width: src.width, height: src.height, frames: [src], delaysMs: const [100])
          .fitTo(out.width, out.height)
          .frames
          .first
          .copy();
      _fitted = fitted;
      _src = src;
      _rev = rev;
    }
    out.rgb.setAll(0, fitted.rgb);
  }
}
