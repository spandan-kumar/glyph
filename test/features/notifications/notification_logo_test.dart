import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/features/notifications/notification_logo.dart';
import 'package:glyph/features/notifications/notification_settings.dart';

void main() {
  test('logo bounce stays visible on tiny, rectangular and strip devices', () {
    final generator = NotificationLogoGenerator(NotificationLogo.fallback);
    expect(generator.liveOnly, isTrue);
    for (final (w, h) in [(1, 1), (8, 8), (16, 16), (32, 8), (60, 1)]) {
      final frame = Frame(w, h), effect = generator.create(w, h, 0);
      for (final t in [0.0, .25, 1.0, 3.75]) {
        effect.render(
          frame,
          t,
          .025,
          Params.defaultsFor(generator),
          palettes.first,
        );
        expect(frame.rgb.any((v) => v > 0), isTrue, reason: '$w x $h at $t');
      }
    }
  });
  test('quiet hours handle midnight, daytime, boundaries and all-day', () {
    final s = NotificationSettings()..quiet = true;
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 10, 7, hour, minute);
    expect(s.isQuiet(at(22)), isTrue);
    expect(s.isQuiet(at(0)), isTrue);
    expect(s.isQuiet(at(7, 59)), isTrue);
    expect(s.isQuiet(at(8)), isFalse);
    expect(s.isQuiet(at(21, 59)), isFalse);
    s.quietStart = 9 * 60;
    s.quietEnd = 17 * 60;
    expect(s.isQuiet(at(12)), isTrue);
    expect(s.isQuiet(at(17)), isFalse);
    s.quietEnd = s.quietStart;
    expect(s.isQuiet(at(4)), isTrue);
    s.quiet = false;
    expect(s.isQuiet(at(4)), isFalse);
  });
}
