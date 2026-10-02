import 'dart:math';

import 'package:flutter/material.dart';

import '../../../ui/theme.dart';
import '../core/game.dart';

// Raw pointer Listeners rather than gesture recognisers: input lands in the
// game on touch-down with no arena delay, and several buttons can be held
// at once.

class PadButton extends StatefulWidget {
  const PadButton({
    super.key,
    required this.child,
    required this.onDown,
    this.onUp,
    this.width = 72,
    this.height = 72,
    this.radius,
    this.color = GlyphColors.surfaceHigh,
    this.label,
  });

  final Widget child;
  final VoidCallback onDown;
  final VoidCallback? onUp;
  final double width, height;
  final double? radius;
  final Color color;
  final String? label;

  @override
  State<PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<PadButton> {
  int _pointers = 0;

  void _down(PointerDownEvent _) {
    setState(() => _pointers++);
    widget.onDown();
  }

  void _up(PointerEvent _) {
    if (_pointers == 0) return;
    setState(() => _pointers--);
    if (_pointers == 0) widget.onUp?.call();
  }

  double get _iconSize {
    final s = min(widget.width, widget.height);
    return s.isFinite ? s * 0.45 : 44;
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _pointers > 0;
    final r = widget.radius ?? min(widget.width, widget.height) / 2;
    return Semantics(
      button: true,
      label: widget.label,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: pressed ? Color.lerp(widget.color, Colors.white, 0.18) : widget.color,
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
                color: pressed ? GlyphColors.primary : GlyphColors.outline, width: 1.5),
          ),
          child: Center(
            child: IconTheme(
              data: IconThemeData(size: _iconSize),
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Four-way pad. [onUp] fires on release, for games with held keys.
class DPad extends StatelessWidget {
  const DPad({
    super.key,
    required this.onDown,
    this.onUp,
    this.size = 68,
    this.upIcon = Icons.keyboard_arrow_up_rounded,
  });

  final void Function(GameKey k) onDown;
  final void Function(GameKey k)? onUp;
  final double size;
  final IconData upIcon;

  Widget _b(GameKey k, IconData icon) => PadButton(
        width: size,
        height: size,
        radius: size * 0.3,
        label: k.name,
        onDown: () => onDown(k),
        onUp: onUp == null ? null : () => onUp!(k),
        child: Icon(icon),
      );

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(width: size, height: size);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [gap, _b(GameKey.up, upIcon), gap]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        _b(GameKey.left, Icons.keyboard_arrow_left_rounded),
        gap,
        _b(GameKey.right, Icons.keyboard_arrow_right_rounded),
      ]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        gap,
        _b(GameKey.down, Icons.keyboard_arrow_down_rounded),
        gap,
      ]),
    ]);
  }
}

/// Turns swipes into direction presses. Keeps tracking while the finger is
/// down, so you can steer in one continuous stroke.
class SwipeArea extends StatefulWidget {
  const SwipeArea({super.key, required this.onSwipe, required this.child});

  final void Function(GameKey k) onSwipe;
  final Widget child;

  @override
  State<SwipeArea> createState() => _SwipeAreaState();
}

class _SwipeAreaState extends State<SwipeArea> {
  final _origins = <int, Offset>{};

  void _move(PointerMoveEvent e) {
    final o = _origins[e.pointer];
    if (o == null) return;
    final d = e.localPosition - o;
    if (d.distance < 22) return;
    widget.onSwipe(d.dx.abs() > d.dy.abs()
        ? (d.dx > 0 ? GameKey.right : GameKey.left)
        : (d.dy > 0 ? GameKey.down : GameKey.up));
    _origins[e.pointer] = e.localPosition;
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _origins[e.pointer] = e.localPosition,
        onPointerMove: _move,
        onPointerUp: (e) => _origins.remove(e.pointer),
        onPointerCancel: (e) => _origins.remove(e.pointer),
        child: widget.child,
      );
}

/// A touch strip: the finger's position along it is the paddle position.
class DragPad extends StatelessWidget {
  const DragPad({
    super.key,
    required this.onPosition,
    this.onDown,
    this.vertical = false,
    this.label = '',
  });

  final void Function(double v) onPosition;
  final VoidCallback? onDown;
  final bool vertical;
  final String label;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        void at(Offset p) {
          const m = 28.0;
          final ext = vertical ? c.maxHeight : c.maxWidth;
          final pos = vertical ? p.dy : p.dx;
          onPosition(((pos - m) / max(1.0, ext - 2 * m)).clamp(0.0, 1.0));
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            onDown?.call();
            at(e.localPosition);
          },
          onPointerMove: (e) => at(e.localPosition),
          child: _Surface(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(vertical ? Icons.swap_vert_rounded : Icons.swap_horiz_rounded,
                  size: 40, color: GlyphColors.textMuted),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: GlyphColors.textMuted)),
            ]),
          ),
        );
      });
}

class TapPad extends StatelessWidget {
  const TapPad({super.key, required this.onTap, this.label = 'TAP'});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => PadButton(
        width: double.infinity,
        height: double.infinity,
        radius: 24,
        color: GlyphColors.surface,
        label: label,
        onDown: onTap,
        child: Text(label,
            style: const TextStyle(fontSize: 28, color: GlyphColors.textMuted, letterSpacing: 6)),
      );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: GlyphColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: GlyphColors.outline),
        ),
        child: child,
      );
}
