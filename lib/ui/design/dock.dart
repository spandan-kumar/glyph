import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'type.dart';

/// A 5×5 LED-dot icon: '#' is lit, '.' is an unlit dot.
class DockGlyph {
  const DockGlyph(this.rows);

  final List<String> rows;

  /// A small lit matrix inside a dark frame.
  static const display = DockGlyph(['.....', '.###.', '.###.', '.###.', '.....']);

  /// A pencil stroke with its tip set apart.
  static const make = DockGlyph(['...##', '..###', '.###.', '.##..', '#....']);

  /// The controller board: a chip with pins.
  static const device = DockGlyph(['.#.#.', '#####', '#...#', '#####', '.#.#.']);
}

class DockItem {
  const DockItem(this.label, this.glyph);
  final String label;
  final DockGlyph glyph;
}

/// The navigation strip: a slim, square-cornered instrument panel inset by
/// the gutters. Each tab is an LED-dot glyph plus its name; the active tab's
/// glyph lights in the room colour and a lit segment slides along the top
/// hairline to it.
class Dock extends StatelessWidget {
  const Dock({super.key, required this.items, required this.index, required this.onSelect, this.accent = Lb.phosphor});

  static const height = 56.0;

  final List<DockItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final n = items.length;
    // A scrim under the strip so rails scrolling beneath fade out instead of
    // showing through the system gesture area.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.55],
          colors: [Lb.ink.withValues(alpha: 0), Lb.ink.withValues(alpha: 0.92)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Lb.rPanel),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Lb.panel.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(Lb.rPanel),
                  border: Border.all(color: Lb.line),
                ),
                child: SizedBox(
                  height: Dock.height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Material(
                          type: MaterialType.transparency,
                          child: Row(
                            children: [
                              for (var i = 0; i < n; i++) ...[
                                if (i > 0) const _Tick(),
                                Expanded(
                                  child: _DockTab(
                                    item: items[i],
                                    active: i == index,
                                    accent: accent,
                                    onTap: () {
                                      if (i != index) HapticFeedback.selectionClick();
                                      onSelect(i);
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // The lit segment on the top hairline.
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 2,
                        child: IgnorePointer(
                          child: AnimatedAlign(
                            key: const ValueKey('dock-indicator'),
                            alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
                            duration: Lb.medium,
                            curve: Lb.ease,
                            child: FractionallySizedBox(
                              widthFactor: 1 / n,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 22),
                                child: AnimatedContainer(
                                  duration: Lb.medium,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 8)],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// A short hairline between tabs, like the rule between panel sections.
class _Tick extends StatelessWidget {
  const _Tick();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 16, child: ColoredBox(color: Lb.line));
}

class _DockTab extends StatelessWidget {
  const _DockTab({required this.item, required this.active, required this.accent, required this.onTap});

  final DockItem item;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  static final _labelStyle = LbType.heading.copyWith(fontSize: 14, letterSpacing: 0.1, height: 1);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Lb.raised.withValues(alpha: 0.6),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: active ? accent : Lb.text3),
                duration: Lb.medium,
                curve: Lb.ease,
                builder: (context, color, _) => CustomPaint(
                  size: const Size.square(DockGlyphPainter.extent),
                  painter: DockGlyphPainter(item.glyph, color ?? Lb.text3, glow: active),
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: Lb.medium,
                  curve: Lb.ease,
                  style: _labelStyle.copyWith(color: active ? Lb.text : Lb.text3),
                  child: Text(item.label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints a [DockGlyph] as LED dots: lit dots in [color] (with a little
/// bloom when [glow]), the rest as unlit LEDs.
class DockGlyphPainter extends CustomPainter {
  DockGlyphPainter(this.glyph, this.color, {this.glow = false});

  static const cell = 3.2;
  static const extent = cell * 5;

  final DockGlyph glyph;
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final on = Paint()..color = color;
    final off = Paint()..color = Lb.ledOff;
    final bloom = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, cell * 0.7);
    final r = cell * 0.38;
    for (var y = 0; y < glyph.rows.length; y++) {
      final row = glyph.rows[y];
      for (var x = 0; x < row.length; x++) {
        final c = Offset((x + 0.5) * cell, (y + 0.5) * cell);
        if (row[x] != '#') {
          canvas.drawCircle(c, r, off);
          continue;
        }
        if (glow) canvas.drawCircle(c, cell * 0.6, bloom);
        canvas.drawCircle(c, r, on);
      }
    }
  }

  @override
  bool shouldRepaint(DockGlyphPainter old) => old.glyph != glyph || old.color != color || old.glow != glow;
}
