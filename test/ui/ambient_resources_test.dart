import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/ui/design/ambient.dart';

import '../app/playback_resources_test.dart' show CountingGenerator;

void main() {
  testWidgets(
    'ambient colour settles for a frozen frame and stops while backgrounded',
    (tester) async {
      final p = PlaybackController()
        ..playGenerator(CountingGenerator())
        ..pause();
      final ambient = AmbientController(p);
      var notifications = 0;
      ambient.addListener(() => notifications++);
      await tester.pump(const Duration(seconds: 6));
      expect(notifications, greaterThan(0));
      final settled = notifications;
      await tester.pump(const Duration(seconds: 2));
      expect(notifications, settled);
      ambient.didChangeAppLifecycleState(AppLifecycleState.paused);
      p.frame.fill(0x0000ff);
      p.frameTick.value++;
      await tester.pump(const Duration(seconds: 2));
      expect(notifications, settled);
      ambient.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 500));
      expect(notifications, greaterThan(settled));
      ambient.dispose();
      p.dispose();
      await tester.pump();
    },
  );
}
