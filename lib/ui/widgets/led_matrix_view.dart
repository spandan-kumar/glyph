import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/playback.dart';
import '../../engine/frame.dart';
import '../design/tokens.dart';
import 'preview_visibility.dart';

/// Draws a [Frame] as a real LED panel: warm unlit dots, lit dots with a hot
/// core, and (with [glow]) a single blurred bloom pass under them. Pass
/// [repaint] (e.g. the playback frame tick) to repaint without rebuilding.
class LedMatrixView extends StatefulWidget {
  const LedMatrixView({
    super.key,
    required this.frame,
    this.repaint,
    this.glow = false,
    this.borderRadius = Lb.rTile,
    this.bezel = false,
  });

  final Frame frame;
  final Listenable? repaint;
  final bool glow;
  final double borderRadius;

  /// Draw a thin hardware bezel around the panel.
  final bool bezel;

  @override
  State<LedMatrixView> createState() => _LedMatrixViewState();
}

class _LedMatrixViewState extends State<LedMatrixView> {
  PlaybackController? _playback;
  final _scrolls = <ScrollPosition>{};
  bool _visibilityPending = false;

  void _syncDemand() {
    final repaint = widget.repaint;
    final playback = repaint is PlaybackFrameTick ? repaint.playback : null;
    if (!identical(playback, _playback)) {
      _playback?.setPreviewActive(this, false);
    }
    _playback = playback;
    for (final scroll in _scrolls) { scroll.removeListener(_scheduleVisibility); }
    _scrolls.clear();
    if (playback == null) return;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        _scrolls.add((element.state as ScrollableState).position);
      }
      return true;
    });
    for (final scroll in _scrolls) { scroll.addListener(_scheduleVisibility); }
    if (!TickerMode.valuesOf(context).enabled) playback.setPreviewActive(this, false);
    _scheduleVisibility();
  }

  void _scheduleVisibility() {
    if (_visibilityPending) return;
    _visibilityPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityPending = false;
      if (!mounted) return;
      _playback?.setPreviewActive(this,
          TickerMode.valuesOf(context).enabled && previewIsVisible(context));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDemand();
  }

  @override
  void didUpdateWidget(LedMatrixView old) {
    super.didUpdateWidget(old);
    _syncDemand();
  }

  @override
  void dispose() {
    for (final scroll in _scrolls) { scroll.removeListener(_scheduleVisibility); }
    _playback?.setPreviewActive(this, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LedMatrixView(:frame, :repaint, :glow, :borderRadius, :bezel) =
        widget;
    Widget panel = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CustomPaint(
        painter: _LedPainter(frame, glow, repaint),
        child: const SizedBox.expand(),
      ),
    );
    if (bezel) {
      panel = DecoratedBox(
        decoration: BoxDecoration(
          color: Lb.bezel,
          // Crisp hardware edge: the bezel only softens by a pixel more
          // than the panel inside it.
          borderRadius: BorderRadius.circular(borderRadius + 1),
          border: Border.all(color: Lb.line),
        ),
        child: Padding(padding: const EdgeInsets.all(4), child: panel),
      );
    }
    return RepaintBoundary(
      child: AspectRatio(aspectRatio: frame.width / frame.height, child: panel),
    );
  }
}

class _LedPainter extends CustomPainter {
  _LedPainter(this.frame, this.glow, Listenable? repaint) : super(repaint: repaint);

  final Frame frame;
  final bool glow;

  static final _bg = Paint()..color = Lb.bezel;
  static const _off = Lb.ledOff;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _bg);
    final cell = size.width / frame.width;
    final r = cell * 0.38;
    final px = frame.rgb;

    if (glow) {
      // One blur for the whole panel instead of one per LED.
      canvas.saveLayer(Offset.zero & size, Paint()..imageFilter = ImageFilter.blur(sigmaX: cell * 0.7, sigmaY: cell * 0.7));
      final bloom = Paint();
      for (var y = 0; y < frame.height; y++) {
        for (var x = 0; x < frame.width; x++) {
          final i = (y * frame.width + x) * 3;
          final peak = _peak(px[i], px[i + 1], px[i + 2]);
          if (peak < 50) continue;
          bloom.color = Color.fromARGB((peak * 0.55).round(), px[i], px[i + 1], px[i + 2]);
          canvas.drawCircle(Offset((x + 0.5) * cell, (y + 0.5) * cell), cell * 0.62, bloom);
        }
      }
      canvas.restore();
    }

    final leds = <Color, List<Offset>>{};
    final cores = <Color, List<Offset>>{};
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final i = (y * frame.width + x) * 3;
        final cr = px[i], cg = px[i + 1], cb = px[i + 2];
        final c = Offset((x + 0.5) * cell, (y + 0.5) * cell);
        final peak = _peak(cr, cg, cb);
        if (peak < 6) {
          (leds[_off] ??= []).add(c);
          continue;
        }
        final color = Color.fromARGB(255, cr, cg, cb);
        (leds[color] ??= []).add(c);
        if (cell >= 6 && peak > 140) {
          // A whiter hot spot reads as emitted light rather than paint.
          final hot = Color.lerp(color, const Color(0xFFFFFFFF), 0.45)!.withValues(alpha: 0.7);
          (cores[hot] ??= []).add(c);
        }
      }
    }
    // LED discs don't overlap: batch equal colours into one draw call.
    _dots(canvas, leds, r);
    _dots(canvas, cores, r * 0.42);
  }

  static void _dots(Canvas canvas, Map<Color, List<Offset>> groups, double radius) {
    final paint = Paint()..strokeCap = StrokeCap.round..strokeWidth = radius * 2;
    for (final entry in groups.entries) {
      canvas.drawPoints(PointMode.points, entry.value, paint..color = entry.key);
    }
  }

  static int _peak(int r, int g, int b) => r > g ? (r > b ? r : b) : (g > b ? g : b);

  @override
  bool shouldRepaint(_LedPainter old) => old.frame != frame || old.glow != glow;
}
