import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/cant_see_it.dart';
import 'package:glyph/ui/onboarding/onboarding_flow.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/device/fake_wled.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a first vibe the device misses is still said after onboarding, with a way to fix it',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final wled = FakeWled()..offline = true;
    final devices = DeviceStore(clientFactory: wled.client);
    await tester.runAsync(() => devices.addAndSelect('10.0.0.9', 'Desk'));
    expect(devices.selected, isNotNull);
    expect(devices.isConnected, isFalse);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    final dir = Directory.systemTemp.createTempSync('glyph');
    addTearDown(() => dir.deleteSync(recursive: true));
    final done = ValueNotifier(false);
    await tester.pumpWidget(AppScope(
      playback: playback,
      devices: devices,
      catalog: Catalog.parse(File('assets/catalog/starter.json').readAsStringSync()),
      creations: CreationsStore(directory: () async => dir),
      child: MaterialApp(
        theme: buildTheme(),
        // Onboarding is replaced by the app the moment a vibe is picked.
        home: ValueListenableBuilder(
          valueListenable: done,
          builder: (context, d, _) => d
              ? const Scaffold(body: Center(child: Text('Display')))
              : Scaffold(body: VibeStep(onDone: () => done.value = true)),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Calm'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Display'), findsOneWidget);
    expect(find.text('Your device didn’t answer, so this is only on your phone.'), findsOneWidget);
    // Still there after the old five-second toast would have gone.
    await tester.pump(const Duration(seconds: 6));
    expect(find.text(cantSeeItLabel), findsOneWidget);

    await tester.tap(find.text(cantSeeItLabel));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Check my device'), findsOneWidget);
    expect(find.text('Send a report'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
  });
}
