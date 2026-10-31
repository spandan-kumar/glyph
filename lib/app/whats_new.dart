import 'package:shared_preferences/shared_preferences.dart';

/// Release notes shown once after an update, keyed by version ("1.3.0").
/// Add an entry for each release worth a note; versions without one show
/// nothing. Keep each line short and in plain words.
const whatsNewNotes = <String, List<String>>{
  '1.4.13': [
    'Glyph now tells you when a new version is out. Turn it off in the Glyph menu.',
    'Update automatically: Obtainium can install new versions for you.',
  ],
  '1.4.12': [
    'Safer imports: very large or long images are refused instead of slowing Glyph down.',
    'Setup says where your Wi-Fi password goes before you send it.',
    'Updated libraries and build tools.',
  ],
  '1.4.11': [
    'The library now has only original, CC0 and public-domain animations.',
    'Favourites, Rotations and recents that pointed at removed looks are skipped.',
    'Safer device connections: the settings page stays on your device.',
  ],
  '1.4.10': [
    'A shorter intro you can tap to skip.',
    'Share your creations from the new Share key, with an optional caption and link.',
    'If your device doesn’t answer, “Can’t see it?” says what to check.',
  ],
  '1.4.9': [
    'The Discord link now uses a permanent invite.',
  ],
  '1.4.8': [
    'Drawings started from a picture keep their timing and use far less memory.',
    'Search picks finish loading after the search closes.',
    'Smoother browsing: animations load a few at a time, the one you play first.',
    'Your favourites, Rotations and Saved looks carry over to tidier animation names.',
  ],
  '1.4.7': [
    'Animations load locally without waiting for thumbnail downloads.',
  ],
  '1.4.6': [
    'All leads Display, with the whole library and your creations.',
    'Search finds objects and offers typo corrections. Your Saved looks keep working after renaming.',
    'Start a drawing from a picture or GIF, with crop and colour controls.',
  ],
  '1.4.5': [
    'Animations download as you browse or play them, then stay cached for offline use.',
    'Your current look keeps playing while the next one loads. Send preserves long animation holds.',
  ],
  '1.4.4': [
    'Games tell you when your device is off and turn it on with one tap.',
  ],
  '1.4.3': [
    'Games are a full-screen gamepad: big labelled buttons where your thumbs rest.',
    'Snake: swipe or tap a side. Pong and Brick Breaker: drag anywhere on the strip.',
  ],
  '1.4.2': [
    'Share a drawing with the community: open it in Make and tap Share with the community. After a quick review, everyone with Glyph can play it.',
    'Community on Display shows drawings people shared, with their names.',
  ],
  '1.4.1': [
    '27 new animations: floating jellies, soaring birds, flames and colourful bubbles.',
  ],
  '1.4.0': [
    'Set up display: size and wiring are found with a quick light test and saved on your device. Undo anytime.',
    'Several panels? The wizard works out their order and any upside-down panels.',
    'Your device sets its clock from your phone, so routines run on time.',
    'Home Assistant can show a Saved look or Show when something happens.',
    'Glance adds forecast and air quality cards.',
  ],
  '1.3.6': [
    'Check for new animations, with optional daily checks while Glyph is open.',
    'Send keeps complete sprite sequences and scrolling messages, even on weak Wi-Fi.',
    'Background Music keeps running with the screen off and cleans up when stopped.',
    'Long text prepares without freezing the screen; tab labels fade smoothly.',
  ],
  '1.3.5': [
    'Hidden previews pause, and LED drawing and Music analysis do less work.',
    'Alerts let your phone sleep when idle and keep playback handoffs awake.',
    'Lightbox polish across Display, Make, Device and setup: clearer controls, larger touch targets and accessible labels.',
    'Decorative motion respects your phone’s reduced-motion setting.',
  ],
  '1.3.2': [
    'Send stays reachable while you browse, even with the Stage collapsed.',
    'Already on your device? Play it without uploading again. Tweaked clips keep their speed.',
    'Sharing opens Discord; Show it off appears less often.',
    'Routines hides the built-in intro and keeps your power-on look editable.',
    'Safer Sends when switching devices or replacing an animation, and safer Saved writes.',
  ],
  '1.3.1': [
    'Halloween and Diwali packs: 16 new animations, from a haunted house to sky lanterns.',
    'A Glyph menu (⋯ on every tab): Discord, share your setup, the roadmap, feedback.',
    'Send feedback fills in the details for you; errors have a Report button.',
    'Fixed: a device switched off while Now Playing ran could light up again.',
  ],
  '1.3.0': [
    'Now Playing: show what\'s playing on your phone — cover art and title — on your device.',
    'A square, LED-style look throughout the app.',
    'The dock tucks away while you scroll and comes back when you scroll up.',
    'A new icon: an amber LED-dot “g”.',
    'Fixes and polish.',
  ],
  // 'X.Y.Z': ['…'],
};

/// Decides when to show the notes: once per version, only after an update.
/// A fresh install records its version silently (onboarding covers it).
/// Someone updating from a build before this existed has no record yet;
/// [due]'s `firstRun` (they saw onboarding this launch) tells them apart.
abstract final class WhatsNew {
  static const prefsKey = 'whatsNew.lastSeen';

  /// The notes to show for [version] now, or null. Records [version] as
  /// seen either way, so it never shows twice. [firstRun] is true when the
  /// person was onboarded this launch. [notes] is for tests.
  static Future<List<String>?> due(
    String version, {
    required bool firstRun,
    Map<String, List<String>> notes = whatsNewNotes,
  }) async {
    if (version.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(prefsKey);
    if (last == version) return null;
    await prefs.setString(prefsKey, version);
    if (last == null ? firstRun : _compare(version, last) <= 0) return null;
    final lines = notes[version];
    return lines == null || lines.isEmpty ? null : lines;
  }

  /// Compares "1.10.0" and "1.9.2" numerically (build suffixes ignored).
  static int _compare(String a, String b) {
    List<int> parts(String v) => [for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? 0];
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }
}
