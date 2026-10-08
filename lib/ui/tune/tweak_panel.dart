import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/clip.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../actions.dart';
import '../design/ambient.dart';
import '../design/knob.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';

/// J3: the control surface of a synth. Colour strip, one knob per
/// parameter, a brightness fader. Everything applies live — no "apply".
class TweakPanel extends StatelessWidget {
  const TweakPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback, devices = scope.devices;
    final accent = AmbientScope.of(context).accent;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Lb.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Lb.rSheet)),
        side: Lb.hairline,
      ),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: Listenable.merge([playback, devices]),
        builder: (context, _) {
          final g = playback.generator;
          return ListView(
            padding: EdgeInsets.fromLTRB(0, 0, 0, bottom + 16),
            children: [
              // Drag handle + heading. Dragging down closes.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 120) onClose();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Lb.gutter, 10, 8, 0),
                  child: Column(children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: Lb.line, borderRadius: BorderRadius.circular(Lb.rTile)),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      const MonoLabel('Tweak'),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(playback.item?.title ?? g?.name ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LbType.small.copyWith(color: Lb.text2)),
                      ),
                      TextButton(
                        onPressed: onClose,
                        style: TextButton.styleFrom(
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(Radius.circular(Lb.rControl))),
                        ),
                        child: Text('DONE', style: LbType.label.copyWith(color: Lb.text)),
                      ),
                    ]),
                  ]),
                ),
              ),
              if (g == null)
                Padding(
                  padding: const EdgeInsets.all(Lb.gutter),
                  child: Text('Pick a look first.', style: LbType.body),
                )
              else ...[
                PanelSection(
                  label: 'Colour',
                  trailing: Text(g is ClipGenerator ? '' : playback.palette.name.toUpperCase(),
                      style: LbType.label.copyWith(color: Lb.text2)),
                  padding: const EdgeInsets.fromLTRB(Lb.gutter, 8, Lb.gutter, 0),
                  child: g is ClipGenerator
                      ? Text('This one keeps its own colours.', style: LbType.small)
                      : const SizedBox.shrink(),
                ),
                if (g is! ClipGenerator) ...[
                  const SizedBox(height: 8),
                  PaletteStrip(key: ValueKey(g.id), accent: accent),
                ],
                if (g.params.isNotEmpty)
                  PanelSection(
                    label: 'Feel',
                    child: SizedBox(
                      height: 104,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final spec in g.params)
                            Padding(
                              padding: const EdgeInsets.only(right: 18),
                              child: _ParamKnob(spec: spec, accent: accent),
                            ),
                        ],
                      ),
                    ),
                  ),
                PanelSection(
                  label: 'Brightness',
                  trailing: Text(
                    devices.isConnected ? '${((devices.brightness ?? 128) / 255 * 100).round()}%' : '',
                    style: LbType.label.copyWith(color: Lb.text2),
                  ),
                  child: devices.isConnected
                      ? LedFader(
                          value: (devices.brightness ?? 128) / 255,
                          accent: accent,
                          onChanged: (v) => devices.setBrightness((v * 255).round()),
                        )
                      : Text('Connect a device to dim or brighten it.', style: LbType.small),
                ),
                if (devices.isConnected && !playback.isStreaming)
                  PanelSection(
                    label: 'Device',
                    child: Row(children: [
                      Expanded(
                        child: Text('Show this on your device',
                            style: LbType.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      OutlinedButton(
                        onPressed: () => GlyphActions.ensureStreaming(context),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: accent),
                          minimumSize: const Size(64, 40),
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(Radius.circular(Lb.rControl))),
                        ),
                        child: Text('SHOW', style: LbType.label.copyWith(color: Lb.text)),
                      ),
                    ]),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ParamKnob extends StatelessWidget {
  const _ParamKnob({required this.spec, required this.accent});

  final ParamSpec spec;
  final Color accent;

  /// Whole-number ranges (e.g. a motion style 0–6) turn in whole steps.
  bool get _stepped =>
      spec.max - spec.min >= 2 &&
      spec.max - spec.min <= 12 &&
      spec.min == spec.min.roundToDouble() &&
      spec.max == spec.max.roundToDouble() &&
      spec.defaultValue == spec.defaultValue.roundToDouble();

  @override
  Widget build(BuildContext context) {
    final playback = AppScope.of(context).playback;
    final v = playback.params[spec.key].clamp(spec.min, spec.max).toDouble();
    return Knob(
      value: v,
      min: spec.min,
      max: spec.max,
      label: spec.label,
      accent: accent,
      size: 60,
      detents: _stepped ? (spec.max - spec.min).round() : 20,
      onChanged: (x) {
        final next = _stepped ? x.roundToDouble() : x;
        if (next != playback.params[spec.key]) playback.setParam(spec.key, next);
      },
    );
  }
}

/// AHA #4: palettes as little LED strips on a snapping reel. Whichever
/// one sits in the middle is on the device.
class PaletteStrip extends StatefulWidget {
  const PaletteStrip({super.key, required this.accent});

  final Color accent;

  @override
  State<PaletteStrip> createState() => _PaletteStripState();
}

class _PaletteStripState extends State<PaletteStrip> {
  static const _chip = 92.0;
  PageController? _pages;
  double _width = 0;

  int _indexOf(String id) => palettes.indexWhere((p) => p.id == id).clamp(0, palettes.length - 1);

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  void _onPage(int i) {
    final playback = AppScope.of(context).playback;
    if (palettes[i].id == playback.palette.id) return;
    HapticFeedback.selectionClick();
    playback.setPalette(palettes[i]);
  }

  @override
  Widget build(BuildContext context) {
    final playback = AppScope.of(context).playback;
    return LayoutBuilder(builder: (context, c) {
      if (_pages == null || c.maxWidth != _width) {
        final page = _pages != null && _pages!.hasClients ? _pages!.page!.round() : _indexOf(playback.palette.id);
        _pages?.dispose();
        _width = c.maxWidth;
        _pages = PageController(viewportFraction: (_chip / _width).clamp(0.1, 1.0), initialPage: page);
      }
      // Follow palette changes made elsewhere (a new look tuned in).
      final want = _indexOf(playback.palette.id);
      final pages = _pages!;
      if (pages.hasClients && pages.page != null && pages.page!.round() != want && !pages.position.isScrollingNotifier.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (pages.hasClients) pages.jumpToPage(want);
        });
      }
      return SizedBox(
        height: 70,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            PageView.builder(
              controller: pages,
              itemCount: palettes.length,
              onPageChanged: _onPage,
              itemBuilder: (context, i) => AnimatedBuilder(
                animation: pages,
                builder: (context, child) {
                  final p = pages.hasClients && pages.position.haveDimensions ? pages.page ?? want.toDouble() : want.toDouble();
                  final d = (p - i).abs().clamp(0.0, 1.0);
                  return Opacity(opacity: 1 - 0.55 * d, child: Transform.scale(scale: 1 - 0.14 * d, child: child));
                },
                child: GestureDetector(
                  onTap: () => pages.animateToPage(i, duration: Lb.medium, curve: Lb.ease),
                  child: _PaletteChip(palette: palettes[i]),
                ),
              ),
            ),
            // The notch that marks "on the matrix".
            IgnorePointer(
              child: Container(
                width: 18,
                height: 3,
                decoration: BoxDecoration(
                  color: widget.accent,
                  borderRadius: BorderRadius.circular(Lb.rTile),
                  boxShadow: [BoxShadow(color: widget.accent.withValues(alpha: 0.7), blurRadius: 6)],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({required this.palette});

  final Palette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 9, 5, 0),
      child: Column(children: [
        Container(
          height: 30,
          decoration: BoxDecoration(
            color: Lb.bezel,
            borderRadius: BorderRadius.circular(Lb.rControl),
            border: Border.all(color: Lb.line),
          ),
          child: CustomPaint(painter: _StripPainter(palette), child: const SizedBox.expand()),
        ),
        const SizedBox(height: 6),
        Text(palette.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LbType.label.copyWith(fontSize: 9.5)),
      ]),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter(this.palette);

  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 8;
    final cell = (size.width - 8) / n;
    final r = cell * 0.36;
    final p = Paint();
    for (var row = 0; row < 2; row++) {
      for (var i = 0; i < n; i++) {
        final c = palette.at((i + row * 0.5) / n);
        p.color = Color(0xFF000000 | c);
        canvas.drawCircle(Offset(4 + (i + 0.5) * cell, size.height * (row == 0 ? 0.32 : 0.68)), r, p);
      }
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) => old.palette != palette;
}

/// A horizontal fader drawn as a row of LED segments. Drag or tap to set.
class LedFader extends StatefulWidget {
  const LedFader({super.key, required this.value, required this.onChanged, this.accent = Lb.phosphor});

  final double value;
  final ValueChanged<double> onChanged;
  final Color accent;

  @override
  State<LedFader> createState() => _LedFaderState();
}

class _LedFaderState extends State<LedFader> {
  static const _segments = 24;
  int _last = -1;

  void _set(Offset local, double width) {
    final v = (local.dx / width).clamp(0.0, 1.0);
    final seg = (v * _segments).round();
    if (seg != _last) {
      _last = seg;
      HapticFeedback.selectionClick();
    }
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return Semantics(
        slider: true,
        label: 'Brightness',
        value: '${(widget.value * 100).round()}%',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _set(d.localPosition, c.maxWidth),
          onHorizontalDragUpdate: (d) => _set(d.localPosition, c.maxWidth),
          child: SizedBox(
            height: 36,
            child: CustomPaint(
              painter: _FaderPainter(widget.value, widget.accent, _segments),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    });
  }
}

class _FaderPainter extends CustomPainter {
  _FaderPainter(this.value, this.accent, this.segments);

  final double value;
  final Color accent;
  final int segments;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = 3.0;
    final w = (size.width - gap * (segments - 1)) / segments;
    final lit = (value * segments).round();
    final on = Paint();
    final off = Paint()..color = Lb.raised;
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (var i = 0; i < segments; i++) {
      // Segments grow taller toward the bright end, like a VU meter.
      final h = size.height * (0.45 + 0.55 * i / (segments - 1));
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (w + gap), size.height - h, w, h),
        const Radius.circular(Lb.rTile),
      );
      if (i < lit) {
        final k = 0.45 + 0.55 * (i + 1) / segments;
        on.color = Color.lerp(Lb.ledOff, accent, k)!;
        if (i == lit - 1) canvas.drawRRect(r.inflate(1), glow..color = accent.withValues(alpha: 0.6));
        canvas.drawRRect(r, on);
      } else {
        canvas.drawRRect(r, off);
      }
    }
  }

  @override
  bool shouldRepaint(_FaderPainter old) => old.value != value || old.accent != accent;
}
