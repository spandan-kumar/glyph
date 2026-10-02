import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../wled/wled_client.dart';
import 'text_settings.dart';

// WLED's own "Scrolling Text" effect (wled00/FX.cpp mode_2Dscrollingtext,
// v16.0.1). It renders on the controller, so clock tokens keep showing live
// time without the phone. Parameters, per the source:
//   n   segment name = text; tokens #HH #MM #SS #TIME #HHMM #DATE #DDMM #MMDD
//       #DD #MO #MON #MONL #DAY #DDDD #YY #YYYY, a trailing 0 (#HH0) pads
//       with zeros. 12/24h follows the controller's time setting (useAMPM).
//       Max 64 chars on ESP32, 32 on ESP8266 (WLED_MAX_SEGNAME_LEN).
//   sx  speed: one pixel every map(sx, 0..255, 250..50) ms
//   ix  Y offset, 128 = centred; when the text fits, 0/255 scroll it up/down
//   c1  trail (0 = none)
//   c2  font, map(c2, 0..255, 0..4): tom-thumb 6px, TinyUnicode 8px,
//       console 6x8, c64esque 9px, 5x12
//   c3  rotation, map(c3, 0..31, -2..2); 16 = upright
//   o1  gradient (palette, or colour 1→3 with palette 0)
//   o2  custom .wbf font from the filesystem
//   o3  reverse (scroll left-to-right)
//   pal 0 = solid colour 1; any other palette cycles over time

/// Native fonts and their pixel heights, by c2 value.
const nativeFonts = <(int c2, int height)>[(0, 6), (64, 8), (128, 8), (192, 9), (255, 12)];

/// Closest WLED palette (by name, looked up at runtime) for each Glyph palette.
const nativePaletteNames = <String, List<String>>{
  'rainbow': ['Rainbow'],
  'sunset': ['Sunset', 'Sunset 2'],
  'ocean': ['Ocean'],
  'lava': ['Lava'],
  'forest': ['Forest'],
  'neon': ['Candy', 'Magenta'],
  'ice': ['Icefire', 'Breeze'],
  'matrix': ['Toxy Reaf', 'Forest'],
  'aurora': ['Aurora', 'Aurora 2'],
  'synthwave': ['Retro Clown', 'Candy'],
  'christmas': ['Jul'],
  'festive': ['Party'],
  'galaxy': ['Tiamat', 'Atlantica'],
  'heart': ['Pink Candy', 'Red & Blue'],
  'pastel': ['Pastel'],
  'halloween': ['Orangery', 'Autumn'],
};

int? nativeEffectId(List<String> effects) {
  final i = effects.indexWhere((e) => e.trim().toLowerCase() == 'scrolling text');
  return i < 0 ? null : i;
}

int nativePaletteId(String glyphPalette, List<String> wledPalettes) {
  for (final name in [...?nativePaletteNames[glyphPalette], 'Rainbow']) {
    final i = wledPalettes.indexWhere((p) => p.toLowerCase() == name.toLowerCase());
    if (i >= 0) return i;
  }
  return 0;
}

/// Segment name for the effect: the message, or time tokens for a clock.
String nativeText(TextSettings s, String mode, {int maxLength = 64}) {
  var t = switch (mode) {
    'clock' => [
        s.hour24 ? '#HH0:#MM0' : '#HH:#MM0',
        if (s.seconds) ':#SS0',
        if (s.date) ' #DAY #DD #MON',
      ].join(),
    _ => s.text.replaceAll('\n', ' ').trim(),
  };
  if (t.length > maxLength) t = t.substring(0, maxLength);
  return t;
}

/// Speed in Glyph px/s → WLED sx (WLED tops out at 20 px/s).
int nativeSpeed(double pixelsPerSecond) {
  final ms = (1000 / pixelsPerSecond).clamp(50.0, 250.0);
  return ((250 - ms) * 255 / 200).round().clamp(0, 255);
}

/// Biggest native font no taller than [rows], nudged by the chosen style.
int nativeFont(TextSettings s, int rows) {
  final wanted = switch (s.font) {
    'tiny' => 6,
    'bold' => s.large ? 12 : 9,
    _ => s.large && rows >= 24 ? 12 : 8,
  };
  var best = nativeFonts.first.$1;
  for (final (c2, height) in nativeFonts) {
    if (height <= rows && height <= wanted) best = c2;
  }
  // Prefer console 6x8 over TinyUnicode for the classic look.
  if (best == 64) best = 128;
  return best;
}

List<int> _rgb(int c) => [(c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF];

/// The segment-0 state that shows [s] with the native effect.
Map<String, dynamic> nativeSegment({
  required TextSettings s,
  required String mode,
  required int effectId,
  required List<String> wledPalettes,
  required int rows,
  int maxNameLength = 64,
}) {
  final solid = s.colorMode == 'solid';
  final up = mode == 'text' && s.direction == 'up';
  return {
    'id': 0,
    'on': true,
    'frz': false,
    'fx': effectId,
    'n': nativeText(s, mode, maxLength: maxNameLength),
    'sx': nativeSpeed(s.pixelsPerSecond),
    'ix': up ? 0 : 128,
    'c1': 0,
    'c2': nativeFont(s, rows),
    'c3': 16,
    'o1': s.colorMode == 'gradient',
    'o2': false,
    'o3': mode == 'text' && s.direction == 'right',
    'pal': solid ? 0 : nativePaletteId(s.colorMode == 'rainbow' ? 'rainbow' : s.palette, wledPalettes),
    'col': [_rgb(s.color), [0, 0, 0], _rgb(s.color)],
  };
}

/// Palette names from /json/pal (index = palette id); empty on failure.
Future<List<String>> fetchWledPalettes(String host) async {
  try {
    final h = ':'.allMatches(host).length > 1 && !host.startsWith('[') ? '[$host]' : host;
    final res = await http.get(Uri.parse('http://$h/json/pal')).timeout(WledClient.timeout);
    final j = jsonDecode(res.body);
    return j is List ? [for (final p in j) '$p'] : const [];
  } catch (_) {
    return const [];
  }
}

/// Shows [s] with WLED's Scrolling Text on segment 0 and saves it as a new
/// preset. Returns the preset id. Throws [WledException] when the effect is
/// missing.
Future<int> saveNativeText(
  WledClient client, {
  required TextSettings s,
  required String mode,
  required String presetName,
  required int rows,
  required bool isEsp8266,
}) async {
  final fx = nativeEffectId(await client.effects());
  if (fx == null) throw WledException('This WLED build has no Scrolling Text effect');
  final pals = await fetchWledPalettes(client.host);
  await client.setState({
    'on': true,
    'seg': nativeSegment(
      s: s,
      mode: mode,
      effectId: fx,
      wledPalettes: pals,
      rows: rows,
      maxNameLength: isEsp8266 ? 32 : 64,
    ),
  });
  return client.saveCurrentAsPreset(presetName);
}
