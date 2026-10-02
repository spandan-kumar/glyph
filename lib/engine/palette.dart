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
  // ---- Appended palettes (library v2). Never reorder: items reference ids.
  Palette('candy', 'Candy', [
    (0.0, 0xFF4FA3),
    (0.3, 0xFFB2E0),
    (0.55, 0x7FE7FF),
    (0.8, 0xB18CFF),
    (1.0, 0xFF4FA3),
  ]),
  Palette('ember', 'Ember', [
    (0.0, 0x000000),
    (0.4, 0x5A0A00),
    (0.7, 0xD9480F),
    (0.9, 0xFF9F1C),
    (1.0, 0xFFE8A3),
  ]),
  Palette('gold', 'Gold', [
    (0.0, 0x140A00),
    (0.4, 0x7A4A00),
    (0.7, 0xE0A100),
    (0.9, 0xFFE27A),
    (1.0, 0xFFFBE6),
  ]),
  Palette('mint', 'Mint', [
    (0.0, 0x00261C),
    (0.4, 0x00A878),
    (0.7, 0x7CF5C8),
    (0.9, 0xE6FFF6),
    (1.0, 0x00261C),
  ]),
  Palette('cyberpunk', 'Cyberpunk', [
    (0.0, 0x0D0221),
    (0.3, 0xFF124F),
    (0.5, 0xFF00A0),
    (0.75, 0x00F0FF),
    (1.0, 0x0D0221),
  ]),
  Palette('toxic', 'Toxic', [
    (0.0, 0x001400),
    (0.4, 0x3DFF00),
    (0.7, 0xD4FF00),
    (0.85, 0x00FFA2),
    (1.0, 0x001400),
  ]),
  Palette('twilight', 'Twilight', [
    (0.0, 0x07051A),
    (0.35, 0x2E1F6B),
    (0.6, 0x8A4FFF),
    (0.82, 0xFF8BD1),
    (1.0, 0x07051A),
  ]),
  Palette('sakura', 'Sakura', [
    (0.0, 0x2A0A1F),
    (0.4, 0xE85A9B),
    (0.7, 0xFFB7D5),
    (0.9, 0xFFF0F6),
    (1.0, 0x2A0A1F),
  ]),
  Palette('autumn', 'Autumn', [
    (0.0, 0x3B0D00),
    (0.3, 0xB23A00),
    (0.55, 0xF28C28),
    (0.8, 0xFFD166),
    (1.0, 0x3B0D00),
  ]),
  Palette('tropical', 'Tropical', [
    (0.0, 0x00B4D8),
    (0.3, 0x06D6A0),
    (0.55, 0xFFD166),
    (0.8, 0xFF6B6B),
    (1.0, 0x00B4D8),
  ]),
  Palette('deepsea', 'Deep Sea', [
    (0.0, 0x000208),
    (0.45, 0x001F4D),
    (0.75, 0x006D77),
    (0.92, 0x83F0E8),
    (1.0, 0x000208),
  ]),
  Palette('desert', 'Desert', [
    (0.0, 0x2B1300),
    (0.35, 0xA0522D),
    (0.65, 0xE9A15B),
    (0.88, 0xFFE0B2),
    (1.0, 0x2B1300),
  ]),
  Palette('royal', 'Royal', [
    (0.0, 0x0A0033),
    (0.4, 0x3F1DCB),
    (0.7, 0xB58BFF),
    (0.88, 0xFFD54A),
    (1.0, 0x0A0033),
  ]),
  Palette('arctic', 'Arctic', [
    (0.0, 0x001018),
    (0.4, 0x00A6C8),
    (0.75, 0xA8F2FF),
    (1.0, 0xFFFFFF),
  ]),
  Palette('bubblegum', 'Bubblegum', [
    (0.0, 0xFF5CA8),
    (0.5, 0x5CE1FF),
    (1.0, 0xFF5CA8),
  ]),
  Palette('fireice', 'Fire & Ice', [
    (0.0, 0x00103A),
    (0.25, 0x00A2FF),
    (0.5, 0xFFFFFF),
    (0.75, 0xFF6A00),
    (1.0, 0x3A0000),
  ]),
  Palette('mono', 'Moonlight', [
    (0.0, 0x000000),
    (0.6, 0x7A8AA0),
    (1.0, 0xFFFFFF),
  ]),
  Palette('blood', 'Crimson', [
    (0.0, 0x000000),
    (0.5, 0x8A0010),
    (0.85, 0xFF1A2E),
    (1.0, 0xFFC2C2),
  ]),
  Palette('spring', 'Spring', [
    (0.0, 0x7BD389),
    (0.3, 0xFFF07C),
    (0.55, 0xFF9FBE),
    (0.8, 0xA0C4FF),
    (1.0, 0x7BD389),
  ]),
  Palette('diwali', 'Diwali', [
    (0.0, 0xFF6F00),
    (0.3, 0xFFC400),
    (0.55, 0xD5006D),
    (0.8, 0x7B1FA2),
    (1.0, 0xFF6F00),
  ]),
  Palette('emerald', 'Emerald', [
    (0.0, 0x001A0E),
    (0.45, 0x00875A),
    (0.75, 0x3EE89F),
    (0.92, 0xFFE9A8),
    (1.0, 0x001A0E),
  ]),
  Palette('sapphire', 'Sapphire', [
    (0.0, 0x000822),
    (0.4, 0x0B3D91),
    (0.7, 0x4C8DFF),
    (0.9, 0xD6E6FF),
    (1.0, 0x000822),
  ]),
  Palette('vaporwave', 'Vaporwave', [
    (0.0, 0xFF71CE),
    (0.33, 0x01CDFE),
    (0.66, 0x05FFA1),
    (0.85, 0xB967FF),
    (1.0, 0xFF71CE),
  ]),
  Palette('peach', 'Peach', [
    (0.0, 0x3D1408),
    (0.4, 0xFF7F50),
    (0.7, 0xFFB38A),
    (0.9, 0xFFE5D1),
    (1.0, 0x3D1408),
  ]),
  Palette('cmy', 'Print', [
    (0.0, 0x00C8FF),
    (0.33, 0xFF00B4),
    (0.66, 0xFFE600),
    (1.0, 0x00C8FF),
  ]),
  Palette('copper', 'Copper', [
    (0.0, 0x120500),
    (0.4, 0x7C3A12),
    (0.7, 0xD9824A),
    (0.9, 0xFFD3A8),
    (1.0, 0x120500),
  ]),
];

Palette paletteById(String id) =>
    palettes.firstWhere((p) => p.id == id, orElse: () => palettes.first);
