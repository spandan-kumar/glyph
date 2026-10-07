import 'package:shared_preferences/shared_preferences.dart';

/// Release notes shown once after an update, keyed by version ("1.3.0").
/// Add an entry for each release worth a note; versions without one show
/// nothing. Keep each line short and in plain words.
const whatsNewNotes = <String, List<String>>{
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
