import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../engine/frame.dart';
import '../../ui/design/tokens.dart';
import '../../ui/make/studio_kit.dart';
import 'editor_model.dart';

/// Zoom/pan of the canvas: content is scaled about the viewport centre, then
/// shifted by [offset] (screen px).
class CanvasView extends ChangeNotifier {
  double _scale = 1;
  Offset _offset = Offset.zero;

  double get scale => _scale;
  Offset get offset => _offset;
  bool get isZoomed => _scale > 1.01 || _offset.distance > 1;

  void set(double scale, Offset offset) {
    _scale = scale;
    _offset = offset;
    notifyListeners();
  }

  void reset() => set(1, Offset.zero);
}

/// Maps between widget-local positions and matrix cells.
class _Geometry {
  _Geometry(Size size, int w, int h, this.view)
      : cell = math.min(size.width / w, size.height / h),
        center = size.center(Offset.zero),
        content = Size(w * math.min(size.width / w, size.height / h),
            h * math.min(size.width / w, size.height / h));

  final double cell;
  final Offset center;
  final Size content;
  final CanvasView view;

  Offset toContent(Offset p) =>
      (p - center - view.offset) / view.scale + content.center(Offset.zero);

  (int, int) cellAt(Offset p) {
    final c = toContent(p);
    return ((c.dx / cell).floor(), (c.dy / cell).floor());
  }

  void apply(Canvas canvas) {
    final cc = content.center(Offset.zero);
    canvas
      ..translate(center.dx + view.offset.dx, center.dy + view.offset.dy)
      ..scale(view.scale)
      ..translate(-cc.dx, -cc.dy);
  }
}

/// The drawing surface. One finger paints; a second finger cancels the
/// stroke and pinches/pans instead, so a zoom never leaves a stray mark.
class EditorCanvas extends StatefulWidget {
  const EditorCanvas({
    super.key,
    required this.model,
    required this.preview,
    required this.led,
    this.onTouch,
  });

  final EditorModel model;

  /// Frame index being played back, or null while editing.
  final ValueListenable<int?> preview;
  final bool led;
  final VoidCallback? onTouch;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

enum _Mode { idle, paint, tap, transform }

class _EditorCanvasState extends State<EditorCanvas> {
  final _view = CanvasView();
  final _pointers = <int, Offset>{};
  _Mode _mode = _Mode.idle;
  int? _painter;
  Offset _tapStart = Offset.zero;
  Size _size = Size.zero;

  double _scale0 = 1, _dist0 = 1;
  Offset _offset0 = Offset.zero, _focal0 = Offset.zero;

  EditorModel get _m => widget.model;
  _Geometry get _geo => _Geometry(_size, _m.width, _m.height, _view);

  @override
  void didUpdateWidget(EditorCanvas old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) _view.reset();
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  bool get _tapTool => _m.tool == EditorTool.fill || _m.tool == EditorTool.picker;

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    widget.onTouch?.call();
    if (_pointers.length == 1 && _mode == _Mode.idle) {
      _painter = e.pointer;
      if (_tapTool) {
        _mode = _Mode.tap;
        _tapStart = e.localPosition;
      } else {
        _mode = _Mode.paint;
        final (x, y) = _geo.cellAt(e.localPosition);
        _m.strokeStart(x, y);
      }
    } else if (_pointers.length == 2) {
      if (_mode == _Mode.paint) _m.strokeCancel();
      _mode = _Mode.transform;
      _beginPinch();
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    switch (_mode) {
      case _Mode.paint when e.pointer == _painter:
        final (x, y) = _geo.cellAt(e.localPosition);
        _m.strokeMove(x, y);
      case _Mode.tap when (e.localPosition - _tapStart).distance > 24:
        _mode = _Mode.idle;
      case _Mode.transform when _pointers.length >= 2:
        _updatePinch();
      default:
        break;
    }
  }

  void _up(PointerEvent e, {bool cancelled = false}) {
    if (_pointers.remove(e.pointer) == null) return;
    if (e.pointer == _painter) {
      if (_mode == _Mode.paint) cancelled ? _m.strokeCancel() : _m.strokeEnd();
      if (_mode == _Mode.tap && !cancelled) {
        final (x, y) = _geo.cellAt(e.localPosition);
        _m.strokeStart(x, y);
      }
      _painter = null;
      if (_mode != _Mode.transform) _mode = _Mode.idle;
    }
    if (_pointers.isEmpty) {
      _mode = _Mode.idle;
    } else if (_mode == _Mode.transform && _pointers.length >= 2) {
      _beginPinch();
    }
  }

  (Offset, Offset) get _pair {
    final it = _pointers.values.iterator..moveNext();
    final a = it.current;
    it.moveNext();
    return (a, it.current);
  }

  void _beginPinch() {
    final (a, b) = _pair;
    _dist0 = math.max((a - b).distance, 1);
    _focal0 = (a + b) / 2;
    _scale0 = _view.scale;
    _offset0 = _view.offset;
  }

  void _updatePinch() {
    final (a, b) = _pair;
    final g = _geo;
    final maxScale = math.max(3.0, 72 / g.cell);
    final scale = (_scale0 * (a - b).distance / _dist0).clamp(1.0, maxScale);
    // Keep the content point that was under the fingers' midpoint under it.
    final anchor = (_focal0 - g.center - _offset0) / _scale0;
    final focal = (a + b) / 2;
    var offset = focal - g.center - anchor * scale;
    final lim = Offset(g.content.width * scale / 2, g.content.height * scale / 2);
    offset = Offset(offset.dx.clamp(-lim.dx, lim.dx), offset.dy.clamp(-lim.dy, lim.dy));
    _view.set(scale, offset);
  }

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final s = (_view.scale * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(1.0, 12.0);
    _view.set(s, s == 1 ? Offset.zero : _view.offset);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _size = c.biggest;
      return Stack(children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: (e) => _up(e, cancelled: true),
            onPointerSignal: _wheel,
            child: CustomPaint(
              painter: _CanvasPainter(
                model: _m,
                preview: widget.preview,
                led: widget.led,
                view: _view,
              ),
            ),
          ),
        ),
        Positioned(
          right: 4,
          bottom: 4,
          child: ListenableBuilder(
            listenable: _view,
            builder: (context, _) => _view.isZoomed
                ? IconButton.outlined(
                    tooltip: 'Fit to screen',
                    style: IconButton.styleFrom(
                        backgroundColor: Lb.panel, side: Lb.hairline, shape: studioShape),
                    onPressed: _view.reset,
                    icon: const Icon(Icons.fit_screen, size: 20),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ]);
    });
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({required this.model, required this.preview, required this.led, required this.view})
      : super(repaint: Listenable.merge([model, model.pixels, preview, view]));

  final EditorModel model;
  final ValueListenable<int?> preview;
  final bool led;
  final CanvasView view;

  static const _panel = Color(0xFF050403);
  static const _off = Lb.ledOff;

  @override
  void paint(Canvas canvas, Size size) {
    final w = model.width, h = model.height;
    final g = _Geometry(size, w, h, view);
    final cell = g.cell;
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    g.apply(canvas);

    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & g.content, const Radius.circular(Lb.rTile)),
        Paint()..color = _panel);

    final p = preview.value;
    final frames = model.frames;
    final Frame f = p != null ? frames[p.clamp(0, frames.length - 1)] : model.frame;
    final ghost = p == null && model.onion ? model.previous : null;
    final px = f.rgb, gpx = ghost?.rgb;

    final paint = Paint();
    final r = cell * 0.4;
    final gap = cell * 0.07;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 3;
        final cr = px[i], cg = px[i + 1], cb = px[i + 2];
        var color = _off;
        if ((cr | cg | cb) != 0) {
          color = Color.fromARGB(255, cr, cg, cb);
        } else if (gpx != null && (gpx[i] | gpx[i + 1] | gpx[i + 2]) != 0) {
          color = Color.fromARGB(80, gpx[i], gpx[i + 1], gpx[i + 2]);
          // Ghost sits over the unlit LED so it reads as "off but hinted".
          paint.color = _off;
          _cell(canvas, paint, x, y, cell, r, gap);
        }
        paint.color = color;
        _cell(canvas, paint, x, y, cell, r, gap);
      }
    }

    if (p == null && (model.mirrorX || model.mirrorY)) {
      final guide = Paint()
        ..color = Lb.phosphor.withValues(alpha: 0.55)
        ..strokeWidth = 1.5 / view.scale;
      if (model.mirrorX) {
        canvas.drawLine(Offset(g.content.width / 2, 0),
            Offset(g.content.width / 2, g.content.height), guide);
      }
      if (model.mirrorY) {
        canvas.drawLine(Offset(0, g.content.height / 2),
            Offset(g.content.width, g.content.height / 2), guide);
      }
    }
    canvas.restore();
  }

  void _cell(Canvas canvas, Paint paint, int x, int y, double cell, double r, double gap) {
    if (led) {
      canvas.drawCircle(Offset((x + 0.5) * cell, (y + 0.5) * cell), r, paint);
    } else {
      canvas.drawRect(
          Rect.fromLTWH(x * cell + gap, y * cell + gap, cell - gap * 2, cell - gap * 2), paint);
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.model != model || old.led != led || old.preview != preview || old.view != view;
}

/// Small square-pixel rendering of a frame for the timeline and template
/// tiles.
class FrameThumb extends StatelessWidget {
  const FrameThumb({super.key, required this.frame, this.repaint});

  final Frame frame;
  final Listenable? repaint;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: frame.width / frame.height,
        child: CustomPaint(painter: _ThumbPainter(frame, repaint)),
      );
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.frame, Listenable? repaint) : super(repaint: repaint);

  final Frame frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF050403));
    final cw = size.width / frame.width, ch = size.height / frame.height;
    final paint = Paint();
    final px = frame.rgb;
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final i = (y * frame.width + x) * 3;
        if ((px[i] | px[i + 1] | px[i + 2]) == 0) continue;
        paint.color = Color.fromARGB(255, px[i], px[i + 1], px[i + 2]);
        // Slight overdraw hides hairline seams between cells.
        canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.frame != frame;
}
