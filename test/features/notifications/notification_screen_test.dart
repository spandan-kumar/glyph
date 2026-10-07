import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/background.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/notifications/notification_controller.dart';
import 'package:glyph/features/notifications/notification_screen.dart';
import 'package:glyph/features/notifications/notification_service.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/design/toggle.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late NotificationController controller;
  late PlaybackController playback;
  late DeviceStore devices;
  late StreamController<Object?> bridge;
  late int openedSettings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    playback = PlaybackController();
    devices = DeviceStore();
    bridge = StreamController<Object?>.broadcast();
    openedSettings = 0;
    final service = NotificationService(
      supported: true,
      events: () => bridge.stream,
      invoke: (method, args) async {
        return switch (method) {
          'status' || 'configure' => {'access': false, 'connected': false},
          'apps' => [
            {'package': 'chat', 'name': 'Chat'},
            {'package': 'mail', 'name': 'Mail'},
          ],
          'icon' => Uint8List(3072)..fillRange(0, 3072, 180),
          'openSettings' => openedSettings++,
          _ => null,
        };
      },
    );
    controller = NotificationController(
      devices: devices,
      playback: playback,
      service: service,
      retain: (_, stop) async => true,
      release: (_) async {},
    );
  });
  tearDown(() {
    controller.dispose();
    playback.dispose();
    devices.dispose();
    bridge.close();
    BackgroundStreaming.debugReset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(controller.load);
    await tester.pumpWidget(
      AppScope(
        playback: playback,
        devices: devices,
        catalog: Catalog.parse(
          File('assets/catalog/starter.json').readAsStringSync(),
        ),
        creations: CreationsStore(),
        notifications: controller,
        child: MaterialApp(
          theme: buildTheme(),
          home: const NotificationScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows consent and defaults off at phone size', (tester) async {
    await pump(tester);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Allow notification access'), findsOneWidget);
    expect(controller.monitoring, isFalse);
    expect(controller.settings.packages, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Allow notification access'),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Allow notification access'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(openedSettings, 1);
  });

  testWidgets(
    'search and toggles select independent apps without starting monitoring',
    (tester) async {
      await pump(tester);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('chat')), 200);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Chat'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.settings.packages, {'chat'});
      expect(controller.monitoring, isFalse);
      await tester.ensureVisible(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'mail');
      await tester.pump(const Duration(milliseconds: 200));
      final appToggles = find.byType(LbToggleTile);
      expect(
        find.descendant(of: appToggles, matching: find.text('Chat')),
        findsNothing,
      );
      expect(
        find.descendant(of: appToggles, matching: find.text('Mail')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('mail')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Mail'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.settings.packages, {'chat', 'mail'});
      expect(tester.takeException(), isNull);
    },
  );
}
