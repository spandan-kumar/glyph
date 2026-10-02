import 'dart:typed_data';

/// A gradient baked into a 256-entry lookup table. Effects produce a 0..1
/// value and the palette decides the colour, so any effect can be recoloured.
class Palette {
  Palette(this.id, this.name, List<(double, int)> stops)
      : lut = _bake(stops),
        swatch = stops.map((s) => s.$2).toList();

  final String id;
  final String name;
  final Uint32List lut;
  final List<int> swatch;

  /// Colour at [v], wrapping so values outside 0..1 cycle smoothly.
  int at(double v) {
    final f = v - v.floorToDouble();
    return lut[(f * 255).toInt()];
  }

  static Uint32List _bake(List<(double, int)> stops) {
    final out = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      final p = i / 255;
      var a = stops.first, b = stops.last;
      for (var s = 0; s < stops.length - 1; s++) {
        if (p >= stops[s].$1 && p <= stops[s + 1].$1) {
          a = stops[s];
          b = stops[s + 1];
          break;
        }
      }
      final span = b.$1 - a.$1;
      final t = span == 0 ? 0.0 : (p - a.$1) / span;
      out[i] = _lerp(a.$2, b.$2, t);
    }
    return out;
  }

  static int _lerp(int a, int b, double t) {
    int ch(int shift) {
      final x = (a >> shift) & 0xFF, y = (b >> shift) & 0xFF;
      return (x + (y - x) * t).round();
    }

    return (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }
}

final palettes = <Palette>[
  Palette('rainbow', 'Rainbow', [
    (0.0, 0xFF0000),
    (0.17, 0xFFAA00),
    (0.33, 0x55FF00),
    (0.5, 0x00FFAA),
    (0.67, 0x0055FF),
    (0.83, 0xAA00FF),
    (1.0, 0xFF0000),
  ]),
  Palette('sunset', 'Sunset', [
    (0.0, 0x1A0033),
    (0.35, 0xB0004F),
    (0.6, 0xFF5A1F),
    (0.85, 0xFFC94A),
    (1.0, 0x1A0033),
  ]),
  Palette('ocean', 'Ocean', [
    (0.0, 0x000A28),
    (0.4, 0x0047AB),
    (0.7, 0x00C2C7),
    (0.85, 0xB8FFF5),
    (1.0, 0x000A28),
  ]),
  Palette('lava', 'Lava', [
    (0.0, 0x000000),
    (0.3, 0x800000),
    (0.6, 0xFF3300),
    (0.85, 0xFFCC00),
    (1.0, 0xFFFFCC),
  ]),
  Palette('forest', 'Forest', [
    (0.0, 0x002200),
    (0.4, 0x1E7A1E),
    (0.7, 0x9ACD32),
    (0.85, 0x3CB371),
    (1.0, 0x002200),
  ]),
  Palette('neon', 'Neon', [
    (0.0, 0xFF00CC),
    (0.33, 0x3300FF),
    (0.66, 0x00FFEE),
    (1.0, 0xFF00CC),
  ]),
  Palette('ice', 'Ice', [
    (0.0, 0x000014),
    (0.5, 0x3399FF),
    (0.8, 0xCCF2FF),
    (1.0, 0xFFFFFF),
  ]),
  Palette('matrix', 'Matrix', [
    (0.0, 0x000000),
    (0.6, 0x00A01E),
    (0.9, 0x55FF55),
    (1.0, 0xDDFFDD),
  ]),
  Palette('aurora', 'Aurora', [
    (0.0, 0x020814),
    (0.25, 0x0B6E4F),
    (0.45, 0x2BFF88),
    (0.62, 0x19D3DA),
    (0.8, 0x7A3CFF),
    (1.0, 0xFF5FD2),
  ]),
  Palette('synthwave', 'Synthwave', [
    (0.0, 0x2B0B5A),
    (0.3, 0xFF2A9D),
    (0.55, 0xFF9E3D),
    (0.75, 0x00E5FF),
    (1.0, 0x2B0B5A),
  ]),
  // Hard-edged bands so random picks land on a "real" festive colour.
  Palette('christmas', 'Christmas', [
    (0.0, 0xE0101E),
    (0.2, 0xE0101E),
    (0.25, 0x0FA33A),
    (0.45, 0x0FA33A),
    (0.5, 0xFFB627),
    (0.7, 0xFFB627),
    (0.75, 0xFFF4E0),
    (0.95, 0xFFF4E0),
    (1.0, 0xE0101E),
  ]),
  Palette('festive', 'Festive', [
    (0.0, 0xFF6A00),
    (0.3, 0xFFD000),
    (0.55, 0xFF1F7A),
    (0.8, 0x8B1EFF),
    (1.0, 0xFF6A00),
  ]),
  Palette('galaxy', 'Galaxy', [
    (0.0, 0x05001A),
    (0.3, 0x3A0CA3),
    (0.5, 0x4361EE),
    (0.7, 0xF72585),
    (0.88, 0xFFD6A5),
    (1.0, 0xFFFFFF),
  ]),
  Palette('heart', 'Heart', [
    (0.0, 0x0A0002),
    (0.35, 0x5C0011),
    (0.6, 0xD00030),
    (0.8, 0xFF3366),
    (1.0, 0xFFC2D4),
  ]),
  Palette('pastel', 'Pastel', [
    (0.0, 0xFFB3BA),
    (0.25, 0xFFDFBA),
    (0.5, 0xBAFFC9),
    (0.75, 0xBAE1FF),
    (1.0, 0xFFB3BA),
  ]),
  Palette('halloween', 'Halloween', [
    (0.0, 0x120018),
    (0.35, 0x6A0DAD),
    (0.6, 0xFF6A00),
    (0.85, 0x7CFF00),
    (1.0, 0x120018),
  ]),
];

Palette paletteById(String id) =>
    palettes.firstWhere((p) => p.id == id, orElse: () => palettes.first);
