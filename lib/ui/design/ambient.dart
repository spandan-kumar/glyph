import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../app/playback.dart';
import 'tokens.dart';

/// Samples the colours currently on the matrix and exposes a smoothed
/// "room light" colour, so the app is lit by the LEDs (UX.md, AHA #3).
class AmbientController extends ChangeNotifier {
  AmbientController(this._playback) {
    _timer = Timer.periodic(const Duration(milliseconds: 160), (_) => _sample());
  }

  final PlaybackController _playback;
  Timer? _timer;
  Color _color = Lb.phosphor.withValues(alpha: 0);
  Color _target = Lb.phosphor.withValues(alpha: 0);

  /// Current room colour. Alpha encodes how much light there is (0 = dark).
  Color get color => _color;

  /// The room colour at full strength, for accents (falls back to phosphor).
  Color get accent => _color.a < 0.05 ? Lb.phosphor : _color.withValues(alpha: 1);

  void _sample() {
    if (_playback.generator == null) {
      _target = Lb.phosphor.withValues(alpha: 0);
    } else {
      final px = _playback.frame.rgb;
      // Brightness-weighted mean: dark pixels shouldn't drag the colour down,
      // a few bright ones should define it.
      var r = 0.0, g = 0.0, b = 0.0, w = 0.0;
      for (var i = 0; i + 2 < px.length; i += 3) {
        final pr = px[i], pg = px[i + 1], pb = px[i + 2];
        final l = max(pr, max(pg, pb)) / 255.0;
        final k = l * l;
        r += pr * k;
        g += pg * k;
        b += pb * k;
        w += k;
      }
      if (w < 0.5) {
        _target = Lb.phosphor.withValues(alpha: 0);
      } else {
        final c = Color.fromARGB(255, (r / w).round(), (g / w).round(), (b / w).round());
        final hsl = HSLColor.fromColor(c);
        // Rooms are lit by saturated light; keep it rich but not neon.
        final lit = hsl
            .withSaturation(min(1, hsl.saturation * 1.15))
            .withLightness(hsl.lightness.clamp(0.35, 0.62))
            .toColor();
        final presence = (w / (px.length / 3)).clamp(0.0, 1.0);
        _target = lit.withValues(alpha: 0.35 + 0.65 * sqrt(presence));
      }
    }
    final next = Color.lerp(_color, _target, 0.22)!;
    if (next != _color) {
      _color = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class AmbientScope extends InheritedNotifier<AmbientController> {
  const AmbientScope({super.key, required AmbientController controller, required super.child})
      : super(notifier: controller);

  static AmbientController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmbientScope>()!.notifier!;

  /// Like [of] without subscribing to changes.
  static AmbientController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AmbientScope>()!.notifier!;
}

/// Paints the room light: a soft glow from the top (where the Stage sits)
/// over the warm-black background.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ambient = AmbientScope.read(context);
    return CustomPaint(
      painter: _BackdropPainter(ambient),
      child: child,
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.ambient) : super(repaint: ambient);

  final AmbientController ambient;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Lb.ink);
    final c = ambient.color;
    if (c.a < 0.01) return;
    final center = Offset(size.width / 2, size.height * 0.16);
    final radius = size.longestSide * 0.75;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            c.withValues(alpha: 0.30 * c.a),
            c.withValues(alpha: 0.10 * c.a),
            c.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.ambient != ambient;
}
