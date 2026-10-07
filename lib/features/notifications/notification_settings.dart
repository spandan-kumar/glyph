import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettings {
  Set<String> packages = {};
  bool quiet = false;
  int quietStart = 22 * 60, quietEnd = 8 * 60;

  bool isQuiet(DateTime now) {
    if (!quiet) return false;
    final minute = now.hour * 60 + now.minute;
    if (quietStart == quietEnd) return true;
    return quietStart < quietEnd
        ? minute >= quietStart && minute < quietEnd
        : minute >= quietStart || minute < quietEnd;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    packages = (p.getStringList('notifications.apps') ?? []).toSet();
    quiet = p.getBool('notifications.quiet') ?? false;
    quietStart = (p.getInt('notifications.quietStart') ?? quietStart).clamp(
      0,
      1439,
    );
    quietEnd = (p.getInt('notifications.quietEnd') ?? quietEnd).clamp(0, 1439);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('notifications.apps', packages.toList());
    await p.setBool('notifications.quiet', quiet);
    await p.setInt('notifications.quietStart', quietStart);
    await p.setInt('notifications.quietEnd', quietEnd);
  }
}
