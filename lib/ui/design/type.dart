import 'package:flutter/painting.dart';

import 'tokens.dart';

/// Text styles. Bricolage Grotesque is a variable font, so weight, optical
/// size and width are set through font variations as well as fontWeight.
abstract final class LbType {
  static TextStyle _bricolage(double size, double wght,
          {double? opsz, double wdth = 100, double tracking = 0, Color color = Lb.text, double? height}) =>
      TextStyle(
        fontFamily: 'Bricolage',
        fontSize: size,
        fontWeight: FontWeight.values[((wght / 100).round() - 1).clamp(0, 8)],
        fontVariations: [
          FontVariation('wght', wght),
          FontVariation('opsz', (opsz ?? size).clamp(12, 96)),
          FontVariation('wdth', wdth),
        ],
        letterSpacing: size * tracking,
        height: height,
        color: color,
      );

  /// Big screen titles ("Tune", "Make").
  static final display = _bricolage(40, 780, opsz: 72, wdth: 88, tracking: -0.025, height: 1.0);

  /// Animation titles under the Stage, sheet titles.
  static final title = _bricolage(24, 720, opsz: 48, wdth: 90, tracking: -0.015, height: 1.1);

  /// Section and card titles.
  static final heading = _bricolage(17, 650, opsz: 24, wdth: 95, tracking: -0.005);

  static final body = _bricolage(15, 420, height: 1.35);
  static final bodyStrong = _bricolage(15, 600, height: 1.35);
  static final small = _bricolage(13, 420, color: Lb.text2, height: 1.3);

  /// Instrument-panel labels: DM Mono, uppercase, tracked.
  static const label = TextStyle(
    fontFamily: 'DMMono',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.9,
    color: Lb.text3,
  );

  static const mono = TextStyle(fontFamily: 'DMMono', fontSize: 12, color: Lb.text2);
}
