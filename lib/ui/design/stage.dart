import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/frame.dart';
import '../widgets/led_matrix_view.dart';
import 'tokens.dart';
import 'type.dart';

/// The hero: a faithful, glowing mirror of the matrix. Swiping sideways
/// "changes channel" (UX.md, AHA #2).
class Stage extends StatefulWidget {
  const Stage({
    super.key,
    required this.frame,
    this.repaint,
    this.deviceName,
    this.connected = false,
    this.onSwipe,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.maxWidth = 360,
  });

  final Frame frame;
  final Listenable? repaint;
  final String? deviceName;
  final bool connected;

  /// +1 = next (swiped left), -1 = previous.
  final ValueChanged<int>? onSwipe;
  final VoidCallback? onTap, onDoubleTap, onLongPress;
  final double maxWidth;

  @override
  State<Stage> createState() => _StageState();
}

class _StageState extends State<Stage> with SingleTickerProviderStateMixin {
  double _dx = 0;
  late final AnimationController _spring =
      AnimationController(vsync: this, duration: Lb.medium)..addListener(() => setState(() => _dx = _from * (1 - Lb.ease.transform(_spring.value))));
  double _from = 0;

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (widget.onSwipe != null && (_dx.abs() > 48 || v.abs() > 420)) {
      HapticFeedback.selectionClick();
      widget.onSwipe!((_dx != 0 ? _dx : v) < 0 ? 1 : -1);
    }
    _from = _dx;
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final panel = LedMatrixView(
      frame: widget.frame,
      repaint: widget.repaint,
      glow: true,
      bezel: true,
      borderRadius: Lb.rControl,
    );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: widget.onTap,
              onDoubleTap: widget.onDoubleTap,
              onLongPress: widget.onLongPress,
              onHorizontalDragUpdate: widget.onSwipe == null
                  ? null
                  : (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(-80.0, 80.0)),
              onHorizontalDragEnd: widget.onSwipe == null ? null : _end,
              child: Transform.translate(
                offset: Offset(_dx * 0.35, 0),
                child: Transform.rotate(angle: _dx * 0.0006, child: panel),
              ),
            ),
            if (widget.deviceName != null) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.connected ? Lb.ok : Lb.text3,
                      boxShadow: widget.connected
                          ? [BoxShadow(color: Lb.ok.withValues(alpha: 0.6), blurRadius: 6)]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(widget.deviceName!.toUpperCase(), style: LbType.label),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
