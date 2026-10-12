import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../ui/design/tokens.dart';
import '../../../ui/design/type.dart';
import '../../../ui/make/studio_kit.dart';
import '../core/game.dart';

// Raw pointer Listeners rather than gesture recognisers: input lands in the
// game on touch-down with no arena delay, and several buttons can be held
// at once.

class PadButton extends StatefulWidget {
  const PadButton({
    super.key,
    required this.child,
    required this.onDown,
    required this.semanticsLabel,
    this.onUp,
    this.width = 72,
    this.height = 72,
    this.radius,
    this.color = Lb.raised,
    this.caption,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onDown;
  final VoidCallback? onUp;
  final double width, height;
  final double? radius;
  final Color color;
  final String? caption;
  final String semanticsLabel;
  final bool enabled;

  @override
  State<PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<PadButton> {
  final _pointers = <int>{};

  void _down(PointerDownEvent e) {
    setState(() => _pointers.add(e.pointer));
    widget.onDown();
  }

  void _up(PointerEvent e) {
    if (!_pointers.remove(e.pointer)) return;
    setState(() {});
    if (_pointers.isEmpty) widget.onUp?.call();
  }

  @override
  void didUpdateWidget(PadButton old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && old.enabled) _pointers.clear();
  }

  double get _iconSize {
    final s = min(widget.width, widget.height);
    return s.isFinite ? (s * 0.48).clamp(32.0, 52.0) : 48;
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _pointers.isNotEmpty;
    final accent = readAccent(context);
    final r = widget.radius ?? Lb.rControl;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      onTap: widget.enabled ? () {
        widget.onDown();
        widget.onUp?.call();
      } : null,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.4,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: widget.enabled ? _down : null,
          onPointerUp: widget.enabled ? _up : null,
          onPointerCancel: widget.enabled ? _up : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: widget.width.isFinite ? max(56.0, widget.width) : widget.width,
            height: widget.height.isFinite ? max(56.0, widget.height) : widget.height,
            decoration: BoxDecoration(
              color: pressed ? Color.lerp(Lb.raised, accent, 0.22) : widget.color,
              borderRadius: BorderRadius.circular(r),
              border: Border.all(color: pressed ? accent : Lb.text3, width: pressed ? 2 : 1.5),
            ),
            child: ExcludeSemantics(
              child: Center(
                child: IconTheme(
                  data: IconThemeData(size: _iconSize, color: Lb.text),
                  child: DefaultTextStyle.merge(
                    style: LbType.bodyStrong.copyWith(color: Lb.text),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      widget.child,
                      if (widget.caption != null) ...[
                        const SizedBox(height: 6),
                        Text(widget.caption!.toUpperCase(),
                            style: LbType.label.copyWith(color: Lb.text2), maxLines: 1),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Continuous swipe steering, with taps selecting one of the four triangles.
class SwipePad extends StatefulWidget {
  const SwipePad({super.key, required this.onDirection});

  final void Function(GameKey k) onDirection;

  @override
  State<SwipePad> createState() => _SwipePadState();
}

class _SwipePointer {
  _SwipePointer(this.origin) : last = origin;

  Offset origin, last;
  double travel = 0;
  bool swiped = false;

  void track(Offset p) {
    travel += (p - last).distance;
    last = p;
  }
}

class _SwipePadState extends State<SwipePad> {
  final _pointers = <int, _SwipePointer>{};
  GameKey? _direction;
  Timer? _flash;

  void _emit(GameKey k) {
    _flash?.cancel();
    setState(() => _direction = k);
    widget.onDirection(k);
    _flash = Timer(Lb.fast, () {
      if (mounted) setState(() => _direction = null);
    });
  }

  GameKey _axis(Offset v) => v.dx.abs() > v.dy.abs()
      ? (v.dx > 0 ? GameKey.right : GameKey.left)
      : (v.dy > 0 ? GameKey.down : GameKey.up);

  void _move(PointerMoveEvent e) {
    final p = _pointers[e.pointer];
    if (p == null) return;
    p.track(e.localPosition);
    final d = e.localPosition - p.origin;
    if (d.distance < 22) return;
    p.swiped = true;
    p.origin = e.localPosition;
    _emit(_axis(d));
  }

  void _up(PointerUpEvent e, Size size) {
    final p = _pointers.remove(e.pointer);
    if (p == null) return;
    p.track(e.localPosition);
    if (p.swiped || p.travel >= 18) return;
    final v = e.localPosition - size.center(Offset.zero);
    _emit(_axis(Offset(v.dx / (size.width / 2), v.dy / (size.height / 2))));
  }

  @override
  void dispose() {
    _flash?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        Widget chevron(GameKey k, IconData icon, Alignment alignment) => Align(
              alignment: alignment,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(icon, size: 56,
                    color: _direction == k ? readAccent(context) : Lb.text3),
              ),
            );
        return Semantics(
          label: 'Snake controls',
          customSemanticsActions: {
            for (final k in [GameKey.up, GameKey.down, GameKey.left, GameKey.right])
              CustomSemanticsAction(label: 'Move ${k.name}'): () => _emit(k),
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _pointers[e.pointer] = _SwipePointer(e.localPosition),
            onPointerMove: _move,
            onPointerUp: (e) => _up(e, size),
            onPointerCancel: (e) => _pointers.remove(e.pointer),
            child: _Surface(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: const _SwipeGuides(),
                  child: Stack(children: [
                    chevron(GameKey.up, Icons.keyboard_arrow_up_sharp, Alignment.topCenter),
                    chevron(GameKey.down, Icons.keyboard_arrow_down_sharp, Alignment.bottomCenter),
                    chevron(GameKey.left, Icons.keyboard_arrow_left_sharp, Alignment.centerLeft),
                    chevron(GameKey.right, Icons.keyboard_arrow_right_sharp, Alignment.centerRight),
                    const Center(child: Text('SWIPE OR TAP A SIDE', style: LbType.label)),
                  ]),
                ),
              ),
            ),
          ),
        );
      });
}

class _SwipeGuides extends CustomPainter {
  const _SwipeGuides();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Lb.line..strokeWidth = 1;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_SwipeGuides old) => false;
}

/// The finger's position along the track is the paddle position.
class DragPad extends StatefulWidget {
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
  State<DragPad> createState() => _DragPadState();
}

class _DragPadState extends State<DragPad> {
  double _value = 0.5;
  final _pointers = <int>{};

  void _report(double v) {
    setState(() => _value = v.clamp(0.0, 1.0));
    widget.onPosition(_value);
  }

  void _up(PointerEvent e) => setState(() => _pointers.remove(e.pointer));

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        void at(Offset p) {
          const m = 28.0;
          final ext = widget.vertical ? c.maxHeight : c.maxWidth;
          final pos = widget.vertical ? p.dy : p.dx;
          _report((pos - m) / max(1.0, ext - 2 * m));
        }

        return Semantics(
          slider: true,
          label: 'Paddle',
          value: '${(_value * 100).round()}%',
          increasedValue: '${((_value + 0.1).clamp(0.0, 1.0) * 100).round()}%',
          decreasedValue: '${((_value - 0.1).clamp(0.0, 1.0) * 100).round()}%',
          onIncrease: () => _report(_value + 0.1),
          onDecrease: () => _report(_value - 0.1),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              _pointers.add(e.pointer);
              widget.onDown?.call();
              at(e.localPosition);
            },
            onPointerMove: (e) => at(e.localPosition),
            onPointerUp: _up,
            onPointerCancel: _up,
            child: _Surface(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _PaddleTrack(widget.vertical, _value,
                      _pointers.isNotEmpty ? readAccent(context) : Lb.text2),
                  child: Stack(children: [
                    Positioned(
                      top: c.maxHeight / 2 + 20,
                      left: 0,
                      right: 0,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(widget.vertical ? Icons.swap_vert_sharp : Icons.swap_horiz_sharp,
                            size: 40, color: Lb.text3),
                        const SizedBox(height: 8),
                        Text(widget.label.toUpperCase(), textAlign: TextAlign.center, style: LbType.label),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      });
}

class _PaddleTrack extends CustomPainter {
  const _PaddleTrack(this.vertical, this.value, this.color);

  final bool vertical;
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final track = Paint()..color = Lb.line..strokeWidth = 2;
    canvas.drawLine(
        vertical ? Offset(centre.dx, 28) : Offset(28, centre.dy),
        vertical ? Offset(centre.dx, size.height - 28) : Offset(size.width - 28, centre.dy),
        track);
    final pos = 28 + value * ((vertical ? size.height : size.width) - 56);
    canvas.drawRect(Rect.fromCenter(
        center: vertical ? Offset(centre.dx, pos) : Offset(pos, centre.dy),
        width: vertical ? 12 : 64, height: vertical ? 64 : 12), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PaddleTrack old) =>
      old.vertical != vertical || old.value != value || old.color != color;
}

class TapPad extends StatelessWidget {
  const TapPad({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PadButton(
        width: double.infinity,
        height: double.infinity,
        radius: Lb.rPanel,
        color: Lb.panel,
        semanticsLabel: 'Flap',
        onDown: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('TAP', style: LbType.display),
          const SizedBox(height: 8),
          const Text('ANYWHERE TO FLAP', style: LbType.label),
        ]),
      );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Lb.panel,
            borderRadius: BorderRadius.circular(Lb.rPanel),
            border: Border.all(color: Lb.text3),
          ),
          child: child,
        ),
      );
}
