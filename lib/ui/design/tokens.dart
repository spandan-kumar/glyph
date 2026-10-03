import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Colour, shape and motion tokens for the "Lightbox" design language
/// (docs/design/UX.md). Surfaces stay neutral warm-black; colour comes from
/// the LEDs (see AmbientController).
abstract final class Lb {
  static const ink = Color(0xFF0B0A09);
  static const panel = Color(0xFF131210);
  static const raised = Color(0xFF1B1917);
  static const line = Color(0xFF2B2723);
  static const text = Color(0xFFF3EFE8);
  static const text2 = Color(0xFFA39C91);
  static const text3 = Color(0xFF6B655C);
  static const ledOff = Color(0xFF1D1A17);
  static const phosphor = Color(0xFFFFB547);
  static const danger = Color(0xFFFF6A5C);
  static const ok = Color(0xFF7BE0A0);

  // Matrix-like geometry: crisp rectangles, not pills. A 2 px radius just
  // softens the pixel edge; LED dots and rotary knobs stay round because
  // they are round in real hardware.
  static const rControl = 2.0;
  static const rPanel = 2.0;
  static const rSheet = 3.0;
  static const rTile = 1.0;

  static const gutter = 20.0;

  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const ease = Curves.easeOutCubic;

  static const hairline = BorderSide(color: line, width: 1);
}
