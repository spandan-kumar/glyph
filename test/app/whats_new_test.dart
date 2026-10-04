import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/whats_new.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const notes = {
    '1.3.0': ['Now Playing'],
    '1.4.0': ['Something else'],
  };

  Future<String?> lastSeen() async => (await SharedPreferences.getInstance()).getString(WhatsNew.prefsKey);

  test('fresh install: records the version silently', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await WhatsNew.due('1.3.0', firstRun: true, notes: notes), isNull);
    expect(await lastSeen(), '1.3.0');
    expect(await WhatsNew.due('1.3.0', firstRun: false, notes: notes), isNull);
  });

  test('update from a build before notes existed shows them once', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await WhatsNew.due('1.3.0', firstRun: false, notes: notes), ['Now Playing']);
    expect(await WhatsNew.due('1.3.0', firstRun: false, notes: notes), isNull);
  });

  test('shows once per new version, never for the same or an older one', () async {
    SharedPreferences.setMockInitialValues({WhatsNew.prefsKey: '1.3.0'});
    expect(await WhatsNew.due('1.3.0', firstRun: false, notes: notes), isNull);
    expect(await WhatsNew.due('1.4.0', firstRun: false, notes: notes), ['Something else']);
    expect(await WhatsNew.due('1.4.0', firstRun: false, notes: notes), isNull);
    expect(await lastSeen(), '1.4.0');
    // A downgrade records but doesn't show.
    expect(await WhatsNew.due('1.3.0', firstRun: false, notes: notes), isNull);
  });

  test('no notes for this version: nothing to show, still recorded', () async {
    SharedPreferences.setMockInitialValues({WhatsNew.prefsKey: '1.3.0'});
    expect(await WhatsNew.due('1.3.1', firstRun: false, notes: notes), isNull);
    expect(await lastSeen(), '1.3.1');
  });

  test('compares numerically, not as text', () async {
    SharedPreferences.setMockInitialValues({WhatsNew.prefsKey: '1.9.0'});
    expect(await WhatsNew.due('1.10.0', firstRun: false, notes: {'1.10.0': ['ten']}), ['ten']);
  });

  test('bundled notes start with 1.3.0', () {
    expect(whatsNewNotes['1.3.0'], isNotEmpty);
  });
}
