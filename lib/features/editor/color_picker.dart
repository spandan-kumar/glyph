import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme.dart';

/// Opens the HSV picker; [onChanged] fires live while dragging. Resolves to
/// the final colour (0xRRGGBB) once the sheet closes.
Future<int> showColorPickerSheet(BuildContext context,
    {required int initial, required ValueChanged<int> onChanged}) async {
  var current = initial;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: HsvPicker(
        initial: initial,
        onChanged: (c) {
          current = c;
          onChanged(c);
        },
      ),
    ),
  );
  return current;
}

class HsvPicker extends StatefulWidget {
  const HsvPicker({super.key, required this.initial, required this.onChanged});

  final int initial;
  final ValueChanged<int> onChanged;

  @override
  State<HsvPicker> createState() => _HsvPickerState();
}

class _HsvPickerState extends State<HsvPicker> {
  late HSVColor _hsv = HSVColor.fromColor(Color(0xFF000000 | widget.initial));
  late final _hex = TextEditingController(text: _hexOf(widget.initial));

  static String _hexOf(int c) => c.toRadixString(16).padLeft(6, '0').toUpperCase();

  int get _rgb => _hsv.toColor().toARGB32() & 0xFFFFFF;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _update(HSVColor hsv, {bool fromText = false}) {
    setState(() => _hsv = hsv);
    if (!fromText) _hex.text = _hexOf(_rgb);
    widget.onChanged(_rgb);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 180,
              child: _Pad(
                hsv: _hsv,
                onChanged: (s, v) => _update(_hsv.withSaturation(s).withValue(v)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 32,
              child: _HueBar(hue: _hsv.hue, onChanged: (h) => _update(_hsv.withHue(h))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _hsv.toColor(),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: GlyphColors.outline),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hex,
                  decoration: const InputDecoration(prefixText: '#  ', isDense: true),
                  style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: (s) {
                    if (s.length != 6) return;
                    final c = int.parse(s, radix: 16);
                    _update(HSVColor.fromColor(Color(0xFF000000 | c)), fromText: true);
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Saturation left→right, value bottom→top.
class _Pad extends StatelessWidget {
  const _Pad({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final void Function(double s, double v) onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        void at(Offset p) => onChanged(
            (p.dx / c.maxWidth).clamp(0.0, 1.0), 1 - (p.dy / c.maxHeight).clamp(0.0, 1.0));
        return GestureDetector(
          onPanDown: (d) => at(d.localPosition),
          onPanUpdate: (d) => at(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(painter: _PadPainter(hsv), size: Size.infinite),
          ),
        );
      });
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor());
    canvas.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(colors: [Colors.white, Color(0x00FFFFFF)])
              .createShader(r));
    canvas.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Colors.black],
          ).createShader(r));
    final p = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(
        p,
        10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white);
    canvas.drawCircle(
        p,
        11.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black54);
  }

  @override
  bool shouldRepaint(_PadPainter old) => old.hsv != hsv;
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        void at(Offset p) => onChanged((p.dx / c.maxWidth).clamp(0.0, 1.0) * 359.9);
        return GestureDetector(
          onPanDown: (d) => at(d.localPosition),
          onPanUpdate: (d) => at(d.localPosition),
          child: CustomPaint(painter: _HuePainter(hue), size: Size.infinite),
        );
      });
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.2, size.width, size.height * 0.6),
        Radius.circular(size.height));
    canvas.drawRRect(
        bar,
        Paint()
          ..shader = LinearGradient(colors: [
            for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h % 360, 1, 1).toColor(),
          ]).createShader(bar.outerRect));
    final c = Offset(hue / 360 * size.width, size.height / 2);
    canvas.drawCircle(c, size.height / 2 - 2,
        Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor());
    canvas.drawCircle(
        c,
        size.height / 2 - 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}
