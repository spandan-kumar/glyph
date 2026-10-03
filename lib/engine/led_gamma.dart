import 'dart:math' as math;
import 'dart:typed_data';

import 'frame.dart';

// How app colours become LED drive levels. WS2812-style LEDs are linear in
// their PWM level, so WLED gamma-corrects colours before they reach the
// strip (wled00/FX_fcn.cpp WS2812FX::show, table from colors.cpp
// calcGammaTable). Without it a red such as #E8283C lights green and blue
// at 16-24 % and reads pink, and near-black backgrounds visibly glow.

/// Gamma WLED ships with (cfg `light.gc.val`, wled.h gammaCorrectVal).
const defaultLedGamma = 2.2;

/// Lowest LED drive level (0-255, after gamma) that is let through. A pixel
/// whose brightest channel would land below this is switched fully off, so
/// near-black in the app means an unlit LED rather than a dim, off-colour
/// glow (WS2812s show levels 1-2 as a visible, tinted speck).
const ledOffLevel = 3;

/// WLED's colour gamma table for [gamma]: exactly the values colors.cpp
/// NeoGammaWLEDMethod::calcGammaTable computes, so a frame corrected here
/// matches what WLED does for its own effects.
Uint8List ledGammaTable(double gamma) {
  final t = Uint8List(256);
  for (var i = 1; i < 256; i++) {
    t[i] = (math.pow(i / 255, gamma) * 255 + 0.5).toInt().clamp(0, 255);
  }
  return t;
}

/// Smallest raw channel value that still reaches [ledOffLevel] once [gamma]
/// is applied: 32 for 2.2 (WLED maps 31 to 2), 3 for no gamma.
int ledBlackThreshold(double gamma) {
  final t = ledGammaTable(gamma);
  for (var i = 0; i < 256; i++) {
    if (t[i] >= ledOffLevel) return i;
  }
  return 256;
}

/// Per-channel gains applied in LED (linear) space, after gamma: WS2812B
/// green is about 3.5x as bright as blue at the same drive level (typical
/// datasheet: R 390-420, G 660-720, B 180-200 mcd), so an app cyan or light
/// blue whose green and blue are close reads green on the matrix, the more
/// so at low brightness where vision shifts towards green. Green is cut by
/// a fifth: milder than FastLED's TypicalLEDStrip correction (0xFFB0F0,
/// green x0.69, blue x0.94), enough to tip those colours back to blue
/// without turning yellows orange.
typedef LedWhiteBalance = ({double r, double g, double b});

/// Default [LedWhiteBalance] for WS2812-family strips.
const ws2812WhiteBalance = (r: 1.0, g: 0.8, b: 1.0);

/// No white balance.
const neutralWhiteBalance = (r: 1.0, g: 1.0, b: 1.0);

/// Turns RGB bytes into what an LED should receive, given the [gamma] of the
/// LEDs' path and whether this code applies it ([applyGamma]) or the device
/// does (WLED's Image effect, or live data with `no-gc` off):
///
/// 1. Each channel's LED level is gamma(raw) x [balance] gain.
/// 2. A pixel whose brightest LED level would be below [ledOffLevel] is
///    sent as (0, 0, 0): near-black means off.
/// 3. Otherwise, with [applyGamma] the LED levels are sent; without it each
///    channel is sent as raw x gain^(1/gamma), which the device's gamma
///    turns into the same LED level.
///
/// WLED then scales by master brightness (bus_manager.cpp
/// BusDigital::setPixelColor, color_fade "video" mode), after gamma, so hue
/// ratios set here survive dimming; color_fade also keeps any channel above
/// a quarter of the brightest at level >= 1, so a dim blue doesn't vanish.
class LedCorrection {
  LedCorrection({
    this.gamma = defaultLedGamma,
    this.applyGamma = true,
    this.balance = ws2812WhiteBalance,
  }) {
    final gains = [balance.r, balance.g, balance.b];
    for (var c = 0; c < 3; c++) {
      final level = Uint8List(256), send = Uint8List(256);
      final k = gains[c].clamp(0.0, 1.0), kRaw = math.pow(k, 1 / gamma);
      for (var i = 1; i < 256; i++) {
        level[i] = (math.pow(i / 255, gamma) * 255 * k + 0.5).toInt().clamp(0, 255);
        send[i] = applyGamma ? level[i] : (i * kRaw + 0.5).toInt().clamp(0, 255);
      }
      _level[c] = level;
      _send[c] = send;
    }
  }

  /// Gamma of the LEDs' path, used for the black floor either way.
  final double gamma;

  /// Whether this correction applies [gamma] or leaves it to the device.
  final bool applyGamma;

  /// Per-channel LED-space gains.
  final LedWhiteBalance balance;

  final _level = List<Uint8List>.filled(3, Uint8List(0));
  final _send = List<Uint8List>.filled(3, Uint8List(0));
  Uint8List _out = Uint8List(0);

  /// LED level (0-255, before master brightness) of [raw] on channel [c].
  int ledLevel(int c, int raw) => _level[c][raw];

  /// Corrected copy of [rgb] in a buffer owned by this object, overwritten
  /// on the next call.
  Uint8List apply(Uint8List rgb) {
    if (_out.length != rgb.length) _out = Uint8List(rgb.length);
    applyInto(rgb, _out);
    return _out;
  }

  /// Writes the corrected [src] into [dst] (may be the same list).
  void applyInto(Uint8List src, Uint8List dst) {
    final lr = _level[0], lg = _level[1], lb = _level[2];
    final sr = _send[0], sg = _send[1], sb = _send[2];
    final n = src.length - src.length % 3;
    for (var i = 0; i < n; i += 3) {
      final r = src[i], g = src[i + 1], b = src[i + 2];
      if (lr[r] < ledOffLevel && lg[g] < ledOffLevel && lb[b] < ledOffLevel) {
        dst[i] = 0;
        dst[i + 1] = 0;
        dst[i + 2] = 0;
      } else {
        dst[i] = sr[r];
        dst[i + 1] = sg[g];
        dst[i + 2] = sb[b];
      }
    }
  }
}

/// [frames] as a GIF for a player that applies [gamma] itself (WLED's Image
/// effect) should store them: white balance and black floor applied, gamma
/// left to the device (see [LedCorrection] with applyGamma false). The input
/// frames are not modified.
List<Frame> ledFramesForDevice(
  List<Frame> frames, {
  double gamma = defaultLedGamma,
  LedWhiteBalance balance = ws2812WhiteBalance,
}) {
  final c = LedCorrection(gamma: gamma, applyGamma: false, balance: balance);
  Frame correct(Frame f) {
    final o = Frame(f.width, f.height);
    c.applyInto(f.rgb, o.rgb);
    return o;
  }

  return [for (final f in frames) correct(f)];
}
