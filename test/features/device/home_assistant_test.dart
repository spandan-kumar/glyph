import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/community.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/features/device/device_manager.dart';
import 'package:glyph/features/device/widgets/home_assistant.dart';
import 'package:glyph/features/device/widgets/kept.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_wled.dart';

void main() {
  late FakeWled wled;

  setUp(() {
    wled = FakeWled();
    wled.presets['250'] = {
      'n': 'Glyph intro',
      'on': true,
      'seg': [
        {'n': 'glyph-intro.gif', 'id': 0},
      ],
    };
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([const SavedDevice(host: '192.168.29.6', name: 'Matrix').toJson()]),
      'devices.selected': '192.168.29.6',
    });
  });

  Future<DeviceManager> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = DeviceStore(clientFactory: wled.client);
    await store.load();
    final manager = DeviceManager(store)..syncHost();
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: manager,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [KeptSection(manager: manager, store: store, onPlay: (_) async {})],
            ),
          ),
        ),
      ),
    );
    await settle(tester, 800);
    return manager;
  }

  testWidgets('sheet lists stored names, hides system items, copies one', (tester) async {
    await open(tester);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(find.text('Use with Home Assistant'));
    await settle(tester, 600);
    expect(find.text('Ocean Plasma'), findsWidgets);
    // The name Home Assistant shows is the stored one, not the tidied label.
    expect(find.text('rainbow.gif'), findsOneWidget);
    expect(find.text('WLED Turn Off'), findsNothing);
    expect(find.text('Glyph intro'), findsNothing);
    expect(find.text('Open the guide'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy rainbow.gif'));
    await settle(tester, 300);
    expect(copied, ['rainbow.gif']);
    expect(find.text('Copied'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Copy rainbow.gif')).height, greaterThanOrEqualTo(48));
  });

  testWidgets('copy skips the toast where the system already confirms it', (tester) async {
    await open(tester);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    final oldToast = showCopyToast;
    showCopyToast = () async => false;
    addTearDown(() {
      showCopyToast = oldToast;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.tap(find.text('Use with Home Assistant'));
    await settle(tester, 600);
    await tester.tap(find.byTooltip('Copy rainbow.gif'));
    await settle(tester, 300);
    expect(copied, ['rainbow.gif']);
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('Open the guide launches the guide externally', (tester) async {
    await open(tester);
    final launched = <Uri>[];
    final old = Community.launcher;
    Community.launcher = (u) async {
      launched.add(u);
      return true;
    };
    addTearDown(() => Community.launcher = old);
    await tester.tap(find.text('Use with Home Assistant'));
    await settle(tester, 600);
    await tester.tap(find.text('Open the guide'));
    await settle(tester, 300);
    expect(launched.single.toString(), endsWith('/docs/HOME_ASSISTANT.md'));
  });
}

Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 8));
  }
}
