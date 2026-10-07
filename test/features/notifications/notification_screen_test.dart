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
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late NotificationController controller;
  late PlaybackController playback;
  late DeviceStore devices;
  late StreamController<Object?> bridge;
  late int openedSettings;
  late bool access;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    playback = PlaybackController();
    devices = DeviceStore();
    bridge = StreamController<Object?>.broadcast();
    openedSettings = 0;
    access = false;
    final service = NotificationService(
      supported: true,
      events: () => bridge.stream,
      invoke: (method, args) async {
        return switch (method) {
          'status' || 'configure' => {'access': access, 'connected': access},
          'apps' => [
            {'package': 'chat', 'name': 'Chat'},
            {'package': 'mail', 'name': 'Mail'},
            {'package': 'com.whatsapp', 'name': 'WhatsApp'},
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

  testWidgets('asks for access first, starts off, and nothing is chosen', (tester) async {
    await pump(tester);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Allow notification access'), findsOneWidget);
    expect(find.textContaining('never the message'), findsOneWidget);
    expect(controller.monitoring, isFalse);
    expect(controller.settings.packages, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Allow notification access'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(openedSettings, 1);
  });

  testWidgets('suggested apps come first; the main button waits for an app', (tester) async {
    access = true;
    await pump(tester);
    await tester.runAsync(() => controller.service.refresh());
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(FilledButton, 'Pick an app below first'), findsOneWidget);
    // WhatsApp is a suggestion, so it gets a tile straight away.
    await tester.ensureVisible(find.bySemanticsLabel('WhatsApp'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async => tester.tap(find.bySemanticsLabel('WhatsApp')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.settings.packages, {'com.whatsapp'});
    expect(controller.monitoring, isFalse, reason: 'choosing an app never starts alerts by itself');
    await tester.scrollUntilVisible(find.text('Turn on alerts'), -200, scrollable: find.byType(Scrollable).first);
    expect(find.widgetWithText(FilledButton, 'Turn on alerts'), findsOneWidget);
    expect(find.text('Connect a device to test'), findsOneWidget, reason: 'the test button explains what it needs');
    expect(tester.takeException(), isNull);
  });

  testWidgets('all apps: search and toggle any installed app', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.textContaining('All apps'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.textContaining('All apps'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('chat')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.settings.packages, {'chat'});
    await tester.enterText(find.byType(TextField).last, 'mail');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('chat')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mail')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.settings.packages, {'chat', 'mail'});
    expect(controller.monitoring, isFalse);
    expect(tester.takeException(), isNull);
  });
}
