import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/features/device/device_manager.dart';
import 'package:glyph/features/device/widgets/controls.dart';
import 'package:glyph/features/device/widgets/kept.dart';
import 'package:glyph/features/device/widgets/routines.dart';
import 'package:glyph/features/device/widgets/shows.dart';
import 'package:glyph/features/device/widgets/storage.dart';
import 'package:glyph/ui/design/knob.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/wled/schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_wled.dart';

void main() {
  late FakeWled wled;

  setUp(() {
    wled = FakeWled();
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([const SavedDevice(host: '192.168.29.6', name: 'Matrix').toJson()]),
      'devices.selected': '192.168.29.6',
    });
  });

  Future<(DeviceStore, DeviceManager)> pump(
    WidgetTester tester,
    Widget Function(DeviceStore, DeviceManager) build,
  ) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
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
            listenable: Listenable.merge([store, manager]),
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [build(store, manager)],
            ),
          ),
        ),
      ),
    );
    await settle(tester, 800);
    return (store, manager);
  }

  test('routine sentences read naturally', () {
    expect(
      describeRoutine(const WledTimer(presetId: 1, hour: 7, weekdays: WledTimer.weekdaysOnly), 'Sunrise'),
      'Weekdays at 7:00 → Sunrise',
    );
    expect(
      describeRoutine(const WledTimer(presetId: 1, hour: WledTimer.sunsetHour), 'Fireplace'),
      'Every day at sunset → Fireplace',
    );
    expect(
      describeRoutine(
        const WledTimer(presetId: 1, hour: WledTimer.everyHourValue, minute: 5, weekdays: WledTimer.weekend),
        'Clock',
      ),
      'Weekends, every hour at :05 → Clock',
    );
  });

  testWidgets('Routines: toggle saves, tap opens the editor', (tester) async {
    await pump(tester, (_, m) => RoutinesSection(manager: m));
    expect(find.text('Mon, Wed, Fri at 3:07 → something removed'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await settle(tester, 800);
    final cfg = wled.posts.lastWhere((p) => p.$1 == '/json/cfg').$2;
    expect((cfg['timers'] as Map)['ins'], hasLength(3));
    expect(((cfg['timers'] as Map)['ins'] as List).first['en'], 1);

    await tester.tap(find.text('Every hour at :15 → something removed'));
    await settle(tester, 600);
    expect(find.text('Edit routine'), findsOneWidget);
    expect(find.text('Pick what to play'), findsOneWidget, reason: 'its kept item is gone');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shows: card, and a new show in the editor', (tester) async {
    await pump(tester, (s, m) => ShowsSection(manager: m, store: s, onPlay: (_) async {}));
    expect(find.text('glyph_test_list'), findsOneWidget);
    expect(find.textContaining('one after another'), findsOneWidget);
    await tester.tap(find.text('New show'));
    await settle(tester, 600);
    expect(find.text('New show'), findsWidgets);
    await tester.tap(find.text('Add'));
    await settle(tester, 600);
    await tester.tap(find.text('Ocean Plasma').last);
    await settle(tester, 600);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester, 1600);
    final save = wled.posts.firstWhere((p) => p.$2.containsKey('playlist'));
    expect((save.$2['playlist'] as Map)['ps'], [1]);
    expect(save.$2['n'], 'My show');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saved: tiles play, menu offers rename', (tester) async {
    final played = <int>[];
    await pump(tester, (s, m) => KeptSection(manager: m, store: s, onPlay: (id) async => played.add(id)));
    expect(find.text('Ocean Plasma'), findsOneWidget);
    // File-style names read as words.
    expect(find.text('Pipplee'), findsOneWidget);
    expect(find.text('WLED Turn Off'), findsNothing);
    await tester.tap(find.text('Ocean Plasma'));
    await settle(tester);
    expect(played, [1]);
    await tester.longPress(find.text('Pipplee'));
    await settle(tester);
    expect(find.text('Plays when your device powers on.'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Pip the dancer');
    await tester.tap(find.text('Save'));
    await settle(tester, 1200);
    expect(wled.posts.any((p) => p.$2['n'] == 'Pip the dancer'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Storage: plain-words bar and the file page', (tester) async {
    await pump(tester, (s, m) => StorageSection(manager: m, store: s));
    expect(find.text('98 KB of 983 KB used'), findsOneWidget);
    expect(find.textContaining('is used by old files that nothing plays anymore. Tap to free it up.'), findsOneWidget);
    expect(find.textContaining('taken by'), findsNothing);
    await tester.tap(find.text('98 KB of 983 KB used'));
    await settle(tester, 600);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.textContaining('your device\'s own memory'), findsOneWidget);
    expect(find.text('duck.gif'), findsOneWidget);
    expect(find.textContaining('Animation for Ocean Plasma'), findsOneWidget);
    expect(find.textContaining('An old animation nothing plays anymore'), findsWidgets);
    await tester.drag(find.text('duck.gif'), const Offset(0, -600));
    await settle(tester);
    // Every other file says what it is.
    expect(find.textContaining('Your device\'s settings · Your device needs this'), findsOneWidget);
    expect(find.textContaining('An extra tool for its web page'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Controls: power, brightness knob, night light', (tester) async {
    final (store, _) = await pump(tester, (s, _) => HardwareControls(store: s));
    expect(store.isOn, isTrue);
    await tester.tap(find.byKey(const ValueKey('power')));
    await settle(tester);
    expect(wled.posts.last.$2, {'on': false});

    await tester.drag(find.byType(Knob), const Offset(0, -60));
    await settle(tester);
    expect(store.brightness, greaterThan(128));
    expect(wled.posts.last.$2.keys, contains('bri'));

    await tester.tap(find.byKey(const ValueKey('nightlight')));
    await settle(tester, 600);
    expect(find.text('Night light'), findsWidgets);
    expect(find.text('Switch your device on first.'), findsOneWidget);
    await tester.tap(find.text('Sunrise'));
    await settle(tester);
    await tester.tap(find.text('Start'));
    await settle(tester, 600);
    final nl = wled.posts.last.$2['nl'] as Map;
    expect(nl['on'], true);
    expect(nl['mode'], 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Storage: free up deletes only the files nothing plays', (tester) async {
    await pump(tester, (s, m) => StorageSection(manager: m, store: s));
    await tester.tap(find.text('98 KB of 983 KB used'));
    await settle(tester, 600);
    final button = find.textContaining('Free up');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await settle(tester);
    expect(find.textContaining('Everything you\'ve saved keeps playing'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Free up'));
    await settle(tester, 1600);
    expect(wled.deleted.toSet(), {'/duck.gif', '/goose.gif', '/mypaint.gif'});
    expect(tester.takeException(), isNull);
  });
}

Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 8));
  }
}
