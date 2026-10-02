import 'package:shared_preferences/shared_preferences.dart';

/// Best score per game (and per option set, e.g. Snake with walls).
abstract final class HighScores {
  static String key(String gameId, [Set<String> options = const {}]) =>
      (['games.best.$gameId', ...(options.toList()..sort())]).join('.');

  static Future<int> get(String key) async =>
      (await SharedPreferences.getInstance()).getInt(key) ?? 0;

  /// Stores [score] if it beats the record; returns true when it did.
  static Future<bool> submit(String key, int score) async {
    final prefs = await SharedPreferences.getInstance();
    if (score <= (prefs.getInt(key) ?? 0)) return false;
    await prefs.setInt(key, score);
    return true;
  }
}
