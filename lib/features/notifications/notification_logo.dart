import 'dart:math' as math;
import 'dart:typed_data';

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';

/// A fixed-size installed app icon. No notification artwork or text.
class NotificationLogo {
  NotificationLogo(Uint8List bytes) : rgb = Uint8List.fromList(bytes) {
    if (bytes.length != size * size * 3) {
      throw ArgumentError('Expected a 32px RGB icon');
    }
  }
  static const size = 32;
  final Uint8List rgb;

  static final fallback = _fallback();
  static NotificationLogo _fallback() {
    final f = Frame(size, size);
    // Neutral bell for an app whose installed icon could not be loaded.
    for (var y = 7; y < 23; y++) {
      final half = y < 11
          ? 4
          : y < 20
          ? 8
          : 10;
      for (var x = 16 - half; x < 16 + half; x++) {
        f.set(x, y, 0xffb547);
      }
    }
    for (var y = 25; y < 28; y++) {
      for (var x = 13; x < 19; x++) {
        f.set(x, y, 0xffb547);
      }
    }
    return NotificationLogo(f.rgb);
  }
}

class NotificationLogoGenerator extends Generator {
  NotificationLogoGenerator(this.logo);
  final NotificationLogo logo;
  @override
  String get id => 'notification-logo';
  @override
  String get name => 'Notifications';
  @override
  bool get liveOnly => true;
  @override
  EffectInstance create(int width, int height, int seed) => _LogoEffect(logo);
}

class _LogoEffect extends EffectInstance {
  _LogoEffect(this.logo);
  final NotificationLogo logo;
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    out.fill(0);
    final side = math.max(1, (math.min(out.width, out.height) * 0.7).floor());
    final margin = (out.height - side) ~/ 2;
    final lift = (math.sin(t * math.pi * 2 / 1.1).abs() * math.min(3, margin))
        .round();
    final left = (out.width - side) ~/ 2, top = margin - lift;
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final sx = ((x + 0.5) * NotificationLogo.size / side).floor();
        final sy = ((y + 0.5) * NotificationLogo.size / side).floor();
        final i = (sy * NotificationLogo.size + sx) * 3;
        out.set(
          left + x,
          top + y,
          rgb(logo.rgb[i], logo.rgb[i + 1], logo.rgb[i + 2]),
        );
      }
    }
  }
}
