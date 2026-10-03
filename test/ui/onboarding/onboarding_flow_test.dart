import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/onboarding/onboarding_flow.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/discovery.dart';
import 'package:glyph/wled/layout.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/device/fake_wled.dart';
import '../../wled/fixtures.dart';

void main() {
  late FakeWled wled;
  late Catalog catalog;

  setUp(() {
    wled = FakeWled();
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
  });

  Future<(DeviceStore, PlaybackController)> pump(
    WidgetTester tester, {
    required VoidCallback onDone,
    SetupServices services = const SetupServices(),
  }) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final devices = DeviceStore(clientFactory: wled.client);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    final creations = CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph'));
    await tester.pumpWidget(
      AppScope(
        playback: playback,
        devices: devices,
        catalog: catalog,
        creations: creations,
        child: MaterialApp(
          theme: buildTheme(),
          home: OnboardingFlow(onDone: onDone, services: services),
        ),
      ),
    );
    await settle(tester);
    return (devices, playback);
  }

  testWidgets('welcome → just looking around finishes without a matrix', (tester) async {
    var done = 0;
    final (devices, playback) = await pump(tester, onDone: () => done++);
    await settle(tester, 1800); // the wordmark sweep
    expect(find.text('Your matrix, alive.'), findsOneWidget);
    expect(find.text('Find my matrix'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Just looking around'));
    await settle(tester);
    expect(done, 1);
    expect(await OnboardingFlow.isDone(), isTrue);
    expect(devices.saved, isEmpty);
    playback.pause();
  });

  testWidgets('find → hello → guided fix → first vibe', (tester) async {
    var done = 0;
    final services = SetupServices(
      discover: () => Stream.value(const DiscoveredDevice(name: 'Desk matrix', host: '192.168.29.6')),
      scan: () => const Stream.empty(),
    );
    final (devices, playback) = await pump(tester, onDone: () => done++, services: services);

    await tester.tap(find.text('Find my matrix'));
    await settle(tester);
    expect(find.text('Looking for your matrix'), findsOneWidget);
    expect(find.text('Desk matrix'), findsOneWidget);
    expect(find.text('192.168.29.6'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Connect → the matrix waves.
    await tester.tap(find.text('Desk matrix'));
    await settle(tester, 800);
    expect(devices.isConnected, isTrue);
    expect(devices.selected!.host, '192.168.29.6');
    expect(find.text('Look up.'), findsOneWidget);
    expect(find.text('That\'s you saying hi.'), findsOneWidget);
    expect(playback.generator, isA<ClipGenerator>());
    expect(playback.generator!.name, 'Hello');
    expect(tester.takeException(), isNull);

    // Something looks off → arrow question → the arrow pointed right.
    await tester.tap(find.text('Something looks off'));
    await settle(tester);
    expect(find.text('Which way is the arrow pointing on your matrix?'), findsOneWidget);
    expect(playback.generator!.name, 'Arrow');
    await tester.tap(find.bySemanticsLabel('Right'));
    await settle(tester);
    expect(devices.selected!.layout, const MatrixLayout(rotation: 3));
    expect(find.text('Does it look mirrored?'), findsOneWidget);
    expect(playback.generator!.name, 'Letter L');

    // …and it was backwards too.
    await tester.tap(find.text('Yes, it\'s backwards'));
    await settle(tester);
    expect(devices.selected!.layout, const MatrixLayout(rotation: 3, flipX: true));
    expect(find.text('Look up.'), findsOneWidget);
    expect(find.text('TURNED THE RIGHT WAY'), findsOneWidget);
    expect(playback.generator!.name, 'Hello');

    // It's waving → first vibe.
    await tester.tap(find.text('It\'s waving'));
    await settle(tester);
    expect(find.text('Pick a first vibe'), findsOneWidget);
    expect(find.text('Calm'), findsOneWidget);
    expect(find.text('Party'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Calm'));
    await settle(tester);
    expect(done, 1);
    expect(await OnboardingFlow.isDone(), isTrue);
    expect(playback.item?.category, 'Chill');
    playback.pause();
  });

  testWidgets('can\'t see it → typed address connects', (tester) async {
    final probed = <String>[];
    final services = SetupServices(
      discover: () => const Stream.empty(),
      scan: () => const Stream.empty(),
      probe: (host) {
        probed.add(host);
        return probeHost(
          host,
          client: MockClient((r) async => r.url.host == '192.168.29.6'
              ? http.Response(infoEsp32V16, 200)
              : http.Response('nope', 404)),
        );
      },
    );
    final (devices, playback) = await pump(tester, onDone: () {}, services: services);
    await tester.tap(find.text('Find my matrix'));
    await settle(tester);

    // After a few quiet seconds the help opens up by itself.
    await settle(tester, 6400);
    expect(find.text('Type its address'), findsOneWidget);
    expect(find.textContaining('same Wi-Fi'), findsWidgets);
    await tester.tap(find.text('Type its address'));
    await settle(tester);

    // A wrong address explains itself; the right one connects.
    await tester.enterText(find.byType(TextField), '10.0.0.9');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await settle(tester);
    expect(find.textContaining('Nothing answered at 10.0.0.9'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '192.168.29.6');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await settle(tester, 800);
    expect(probed, ['10.0.0.9', '192.168.29.6']);
    expect(devices.selected?.host, '192.168.29.6');
    expect(find.text('Look up.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Back goes to the search again.
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('Looking for your matrix'), findsOneWidget);
    playback.pause();
  });
}

/// Fixed-duration pumps: previews and the radar tick forever.
Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 8));
  }
}
