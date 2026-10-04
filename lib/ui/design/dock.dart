import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import '../../features/text/fonts.dart';
import 'led_text.dart';

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

/// The navigation island: a small, sharp-cornered panel floating above the
/// content. Tab names are drawn in Glyph's own pixel font, like the LED
/// section headers on Display; the active tab sits on a raised block, faintly
/// tinted by the room, that slides between tabs, its name lit in the room
/// colour.
///
/// Tabs share one width so the island is symmetric (Make sits dead centre),
/// and the LED cell is snapped to whole device pixels so every letter's dots
/// land on the same grid instead of smearing across pixel boundaries.
class Dock extends StatelessWidget {
  const Dock({super.key, required this.items, required this.index, required this.onSelect, this.accent = Lb.phosphor});

  static const height = 42.0;
  static const _dot = 2.2;
  static const _padX = 14.0;
  static const _inset = 4.0;

  final List<DockItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    double snap(double v) => (v * dpr).round() / dpr;
    final dot = snap(_dot);
    final cells = items.fold(0, (m, i) => math.max(m, tinyFont.measure(i.label.toUpperCase())));
    final tab = snap(cells * dot + 2 * _padX);
    final widths = [for (final _ in items) tab];
    final left = tab * index;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Center(
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Lb.rPanel),
              boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Lb.rPanel),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // Opaque enough that busy thumbnails don't muddy the labels.
                    color: Lb.panel.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(Lb.rPanel),
                    border: Border.all(color: Lb.line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(_inset),
                    child: SizedBox(
                      height: height - 2 * _inset,
                      width: widths.fold<double>(0, (a, b) => a + b),
                      child: Stack(
                        children: [
                          // The raised block under the active tab.
                          AnimatedPositioned(
                            key: const ValueKey('dock-indicator'),
                            duration: Lb.medium,
                            curve: Lb.ease,
                            left: left,
                            top: 0,
                            bottom: 0,
                            width: widths[index],
                            child: AnimatedContainer(
                              duration: Lb.medium,
                              decoration: BoxDecoration(
                                color: Color.alphaBlend(accent.withValues(alpha: 0.12), Lb.raised),
                                borderRadius: BorderRadius.circular(Lb.rControl),
                                border: Border.all(color: accent.withValues(alpha: 0.28)),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var i = 0; i < items.length; i++)
                                SizedBox(
                                  width: widths[i],
                                  child: _DockTab(
                                    item: items[i],
                                    dot: dot,
                                    active: i == index,
                                    accent: accent,
                                    onTap: () {
                                      if (i != index) HapticFeedback.selectionClick();
                                      onSelect(i);
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
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

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.item,
    required this.dot,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final DockItem item;
  final double dot;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: active ? accent : Lb.text3),
            duration: Lb.medium,
            curve: Lb.ease,
            builder: (context, color, _) =>
                LedText(item.label.toUpperCase(), dot: dot, color: color ?? Lb.text3),
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
