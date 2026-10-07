import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/background.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/glance/glance_model.dart';
import 'package:glyph/features/notifications/notification_logo.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/features/glance/glance_screen.dart';
import 'package:glyph/features/glance/glance_session.dart';
import 'package:glyph/features/glance/phone_show_editor.dart';
import 'package:glyph/features/glance/weather_api.dart';
import 'package:glyph/features/glance/weather_service.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device/fake_wled.dart';

void main() {
  late GlanceSession session;
  late PlaybackController playback;
  late DeviceStore devices;
  late int requests;
  late FakeWled fake;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests = 0;
    playback = PlaybackController();
    fake = FakeWled();
    devices = DeviceStore(clientFactory: fake.client);
    final api = WeatherApi(
      client: MockClient((r) async {
        requests++;
        if (r.url.host.startsWith('geocoding')) {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'name': 'Delhi',
                  'latitude': 28.6,
                  'longitude': 77.2,
                  'timezone': 'Asia/Kolkata',
                },
              ],
            }),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'current_units': {'temperature_2m': '°C'},
              'current': {
                'temperature_2m': 27,
                'weather_code': 0,
                'is_day': 1,
                'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              },
            }),
          ),
          200,
        );
      }),
    );
    session = GlanceSession(
      devices: devices,
      playback: playback,
      catalog: Catalog.parse(
        File('assets/catalog/starter.json').readAsStringSync(),
      ),
      creations: CreationsStore(),
      weather: WeatherService(api: api),
    );
  });
  tearDown(() {
    session.dispose();
    playback.dispose();
    devices.dispose();
    BackgroundStreaming.debugReset();
  });
  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(session.load);
    await tester.pumpWidget(
      AppScope(
        playback: playback,
        devices: devices,
        catalog: session.catalog,
        creations: session.creations,
        glance: session,
        child: MaterialApp(theme: buildTheme(), home: page),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'Glance is accessible at phone size and does not start weather or device playback on first open',
    (tester) async {
      await pump(tester, const GlanceScreen());
      expect(find.text('Glance'), findsOneWidget);
      expect(find.text('Add weather'), findsOneWidget);
      expect(find.text('Add counter'), findsOneWidget);
      expect(requests, 0);
      expect(playback.isPlaying, false);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Add counter'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(
        find.text('DATE · PHONE TIMEZONE'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('DATE · PHONE TIMEZONE'), findsOneWidget);
      expect(find.text('Until'), findsOneWidget);
      expect(find.text('Since'), findsOneWidget);
      expect(find.textContaining('Works offline'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, 'Launch day');
      await tester.scrollUntilVisible(
        find.text('Save card'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save card'));
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(session.store.cards.single.title, 'Launch day');
      expect(session.store.cards.single.valid, true);
      expect(requests, 0);
    },
  );
  testWidgets(
    'weather search is explicit, discloses requests and choosing a place fetches only once',
    (tester) async {
      await pump(
        tester,
        GlanceCardEditor(session: session, kind: GlanceKind.weather),
      );
      expect(requests, 0);
      expect(
        find.textContaining('No phone location permission'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'City or place name'),
        'Delhi',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(requests, 0);
      await tester.scrollUntilVisible(
        find.text('Search'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Search'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(requests, 1);
      expect(find.text('Delhi'), findsWidgets);
      await tester.runAsync(() async {
        await tester.tap(
          find.byWidgetPredicate((w) => w is Text && w.data == 'Delhi'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(requests, 2);
      await tester.scrollUntilVisible(
        find.text('Refresh weather'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Fahrenheit'), findsOneWidget);
      expect(find.textContaining('27°'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.tap(find.text('Refresh weather'));
      });
      expect(requests, 2);
    },
  );
  testWidgets(
    'phone Show editor adds library and card entries, reorders and saves durations',
    (tester) async {
      await pump(tester, PhoneShowEditor(session: session));
      await tester.runAsync(
        () => session.store.saveCard(
          GlanceCard(
            id: 'c',
            title: 'Trip',
            kind: GlanceKind.counter,
            date: DateTime(2026, 10, 9),
          ),
        ),
      );
      await tester.tap(find.text('Add item'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Add to Show'), findsOneWidget);
      expect(find.text('Trip'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Trip'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Add item'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Library'));
      await tester.pump(const Duration(milliseconds: 100));
      final first = session.catalog.items.first;
      await tester.tap(find.text(first.title));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Move up').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1. ${first.title}'), findsOneWidget);
      await tester.tap(find.byTooltip('Duration').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('30 seconds'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(
        find.text('Save Show'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save Show'));
      });
      await tester.pump(const Duration(milliseconds: 100));
      final show = session.store.shows.single;
      expect(show.entries.first.kind, ShowEntryKind.library);
      expect(show.entries.first.seconds, 30);
      expect(show.entries.last.id, 'c');
      expect(tester.takeException(), isNull);
      expect(requests, 0);
    },
  );
  for (final replace in [false, true]) {
    testWidgets(
      replace
          ? 'leaving Glance preserves a newer manual look and its stream'
          : 'leaving Glance stops only its own foreground session',
      (tester) async {
        await pump(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const GlanceScreen())),
                child: const Text('Open Glance'),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await devices.select(
            const SavedDevice(host: '127.0.0.1', name: 'Test'),
          );
          await session.store.saveCard(
            GlanceCard(
              id: 'c',
              title: 'Trip',
              kind: GlanceKind.counter,
              date: DateTime(2026, 10, 9),
            ),
          );
        });
        await tester.tap(find.text('Open Glance'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(() async {
          await tester.tap(find.text('Show on device'));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump(const Duration(milliseconds: 100));
        expect(session.playing, true);
        expect(playback.isStreaming, true);
        final manual = NotificationLogoGenerator(NotificationLogo.fallback);
        if (replace) playback.playGenerator(manual);
        fake.posts.clear();
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(playback.isPlaying, replace);
        expect(playback.isStreaming, replace);
        if (replace) {
          expect(playback.generator, same(manual));
          expect(fake.posts, isEmpty);
        } else {
          expect(fake.posts.last.$2, {'live': false});
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
