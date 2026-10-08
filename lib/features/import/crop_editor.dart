import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../ui/design/tokens.dart';
import '../../ui/make/studio_kit.dart';
import 'processing.dart';

/// Shows the oriented source with the area that reaches the matrix. In fill
/// mode the window (aspect locked to the matrix) is dragged and pinched.
/// Taps report a point in oriented source pixels via [onTap].
class CropEditor extends StatefulWidget {
  const CropEditor({
    super.key,
    required this.image,
    required this.width,
    required this.height,
    required this.settings,
    required this.targetWidth,
    required this.targetHeight,
    required this.onChanged,
    this.onTap,
  });

  /// Oriented source image; null while it's being prepared.
  final ui.Image? image;

  /// Oriented working size.
  final int width, height;
  final ImportSettings settings;
  final int targetWidth, targetHeight;
  final ValueChanged<ImportSettings> onChanged;
  final void Function(double x, double y)? onTap;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  double _startZoom = 1;
  Offset _center = Offset.zero;

  bool get _fill => widget.settings.fit == FitMode.fill;

  Rect _imageRect(Size box) {
    final s = math.min(box.width / widget.width, box.height / widget.height);
    final w = widget.width * s, h = widget.height * s;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Rect _window() {
    if (!_fill) return Rect.fromLTWH(0, 0, widget.width.toDouble(), widget.height.toDouble());
    final (x, y, w, h) = cropWindow(
        widget.width, widget.height, widget.settings, widget.targetWidth, widget.targetHeight);
    return Rect.fromLTWH(x, y, w, h);
  }

  void _update(Size box, double scale, Offset delta) {
    final px = _imageRect(box).width / widget.width;
    final s = widget.settings;
    final zoom = (_startZoom * scale).clamp(
        1.0, maxZoom(widget.width, widget.height, widget.targetWidth, widget.targetHeight));
    _center += delta / px;
    var next = s.copyWith(
        zoom: zoom, cropX: _center.dx / widget.width, cropY: _center.dy / widget.height);
    // Store the clamped centre so dragging past an edge doesn't build up slack.
    final (x, y, w, h) =
        cropWindow(widget.width, widget.height, next, widget.targetWidth, widget.targetHeight);
    next = next.copyWith(cropX: (x + w / 2) / widget.width, cropY: (y + h / 2) / widget.height);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final box = Size(c.maxWidth, c.maxHeight);
      final outline = readAccent(context);
      return Semantics(
        label: 'Crop window',
        hint: _fill
            ? 'Drag to move, pinch to zoom'
            : widget.settings.fit == FitMode.fit
                ? 'The whole image fits the device'
                : 'The whole image is stretched to the device',
        value: _fill ? 'Zoom ${widget.settings.zoom.toStringAsFixed(1)} times' : null,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _fill
            ? (d) {
                _startZoom = widget.settings.zoom;
                _center = _window().center;
              }
            : null,
        onScaleUpdate: _fill ? (d) => _update(box, d.scale, d.focalPointDelta) : null,
        onTapUp: widget.onTap == null
            ? null
            : (d) {
                final r = _imageRect(box);
                if (!r.contains(d.localPosition)) return;
                final px = r.width / widget.width;
                widget.onTap!((d.localPosition.dx - r.left) / px, (d.localPosition.dy - r.top) / px);
              },
        child: CustomPaint(
          size: box,
          painter: _CropPainter(
            image: widget.image,
            imageRect: _imageRect(box),
            window: _window(),
            scale: _imageRect(box).width / widget.width,
            grid: (widget.targetWidth, widget.targetHeight),
            showGrid: _fill || widget.settings.fit == FitMode.stretch,
            smooth: !widget.settings.pixelArt,
            outline: outline,
          ),
        ),
        ),
      );
    });
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.imageRect,
    required this.window,
    required this.scale,
    required this.grid,
    required this.showGrid,
    required this.smooth,
    required this.outline,
  });

  final ui.Image? image;
  final Rect imageRect, window;
  final double scale;
  final (int, int) grid;
  final bool showGrid, smooth;

  /// The room colour: the window is live chrome.
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null) {
      canvas.drawRect(imageRect, Paint()..color = Lb.panel);
    } else {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        imageRect,
        Paint()..filterQuality = smooth ? FilterQuality.medium : FilterQuality.none,
      );
    }
    final w = Rect.fromLTWH(imageRect.left + window.left * scale,
        imageRect.top + window.top * scale, window.width * scale, window.height * scale);
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(imageRect)
      ..addRect(w);
    canvas.drawPath(shade, Paint()..color = Lb.bezel.withValues(alpha: 0.65));
    final (gw, gh) = grid;
    if (showGrid && gw <= 64 && gh <= 64 && w.width / gw >= 4) {
      final line = Paint()
        ..color = Lb.text.withValues(alpha: 0.2)
        ..strokeWidth = 1;
      for (var i = 1; i < gw; i++) {
        final x = w.left + w.width * i / gw;
        canvas.drawLine(Offset(x, w.top), Offset(x, w.bottom), line);
      }
      for (var i = 1; i < gh; i++) {
        final y = w.top + w.height * i / gh;
        canvas.drawLine(Offset(w.left, y), Offset(w.right, y), line);
      }
    }
    canvas.drawRect(
        w.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = outline);
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image ||
      old.imageRect != imageRect ||
      old.window != window ||
      old.grid != grid ||
      old.showGrid != showGrid ||
      old.smooth != smooth ||
      old.outline != outline;
}
