import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/device/setup/setup_controller.dart';
import 'package:glyph/features/device/setup/setup_wifi.dart';
import 'package:glyph/ui/onboarding/search_step.dart';
import 'package:glyph/wled/discovery.dart';

import '../../features/device/setup/fake_setup_device.dart';
import '../../features/device/setup/fake_setup_wifi.dart';
import '../../features/device/setup/setup_rig.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final haptics = <String>[];
  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
        return null;
      },
    );
  });

  Future<void> tapText(WidgetTester tester, String text, {int ms = 500}) async {
    await tester.tap(find.text(text).first);
    await settle(tester, ms);
  }

  group('connect', () {
    testWidgets('"Yes" goes to the search, Back returns; "No" goes to Join', (tester) async {
      final rig = await SetupRig.create(
        tester,
        entry: SetupEntry.newDevice,
        services: SetupServices(
          discover: () => Stream.value(const DiscoveredDevice(name: 'Desk', host: deviceHost, mac: '48e729a39308')),
          scan: () => const Stream.empty(),
        ),
      );
      await rig.pump(tester);
      expect(find.text('Is your device on your Wi-Fi?'), findsOneWidget);
      expect(find.text('Yes, it\'s on my Wi-Fi'), findsOneWidget);
      expect(find.text('Find it on your network'), findsOneWidget);
      expect(find.text('No, it\'s new'), findsOneWidget);
      expect(find.text('Connect to it and add it to your Wi-Fi'), findsOneWidget);
      expect(find.byTooltip('Close'), findsNothing, reason: 'Close starts at Check');

      await tapText(tester, 'Yes, it\'s on my Wi-Fi');
      expect(find.text('Looking for your device'), findsOneWidget);
      expect(find.text('Desk'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(find.text('Is your device on your Wi-Fi?'), findsOneWidget);

      await tapText(tester, 'No, it\'s new');
      expect(find.text('Connect to your device'), findsOneWidget);
      expect(find.text('Plug it in. It makes its own Wi-Fi network, usually called WLED-AP.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      rig.playback.pause();
    });

    testWidgets('a device found on the network goes to Check and then Size', (tester) async {
      final rig = await SetupRig.create(
        tester,
        entry: SetupEntry.newDevice,
        device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false),
        services: SetupServices(
          discover: () => Stream.value(const DiscoveredDevice(name: 'Desk', host: deviceHost, mac: '48e729a39308')),
          scan: () => const Stream.empty(),
        ),
      );
      await rig.pump(tester);
      await tapText(tester, 'Yes, it\'s on my Wi-Fi');
      await tapText(tester, 'Desk', ms: 1200);
      expect(rig.devices.selected?.host, deviceHost);
      await chooseOnePanel(tester);
      expect(find.text('How big is your display?'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      rig.playback.pause();
    });
  });

  group('join', () {
    Future<SetupRig> joinRig(WidgetTester tester, {FakeSetupWifi? wifi, Duration? findTimeout}) async {
      final rig = await SetupRig.create(
        tester,
        entry: SetupEntry.newDevice,
        device: FakeSetupDevice(width: 8, height: 8, ledCount: 64, matrix: false),
        wifi: wifi,
        findTimeout: findTimeout ?? const Duration(seconds: 5),
        services: SetupServices(
          discover: () =>
              Stream.value(const DiscoveredDevice(name: 'WLED-AP-9308', host: deviceHost, mac: '48:E7:29:A3:93:08')),
          scan: () => const Stream.empty(),
        ),
      );
      await rig.pump(tester);
      return rig;
    }

    testWidgets('assisted: Connect, pick a network, Join, found by its MAC', (tester) async {
      final rig = await joinRig(tester);
      await tapText(tester, 'No, it\'s new');
      await tapText(tester, 'Connect', ms: 800);
      expect(rig.wifi.connects, hasLength(1));
      expect(rig.wifi.connects.single.prefix, 'WLED');
      expect(find.text('Which Wi-Fi should it join?'), findsOneWidget);
      // Strongest first, open network has no lock.
      final order = ['Home', 'Cafe', 'Neighbour'];
      final ys = [for (final s in order) tester.getTopLeft(find.text(s)).dy];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.text('Other network'), findsOneWidget);
      expect(find.textContaining('2.4 GHz'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Join')).onPressed, isNull);

      await tapText(tester, 'Home');
      await tester.enterText(find.byType(TextField).last, 'hunter22');
      await settle(tester, 100);
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await settle(tester, 1500);

      // The device was given the network and restarted; the setup network
      // was released before the search; the device was found by MAC.
      final cfg = rig.ap.writes.firstWhere((w) => w.$1 == 'POST /json/cfg').$2 as Map;
      expect(cfg['nw'], {
        'ins': [
          {'ssid': 'Home', 'psk': 'hunter22', 'bssid': '000000000000'},
        ],
      });
      expect((cfg['if'] as Map)['ntp'], containsPair('en', true));
      expect(rig.ap.writes.last.$1, 'POST /json/state');
      expect(rig.ap.writes.last.$2, {'rb': true});
      expect(rig.wifi.releases, greaterThanOrEqualTo(1));
      expect(rig.devices.selected?.host, deviceHost);
      await chooseOnePanel(tester);
      expect(find.text('How big is your display?'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(haptics, contains('HapticFeedbackType.lightImpact'));
      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      expect(tester.takeException(), isNull);
      rig.playback.pause();
    });

    testWidgets('guided fallback when assisted is unavailable', (tester) async {
      final rig = await joinRig(tester, wifi: FakeSetupWifi(assisted: false));
      await tapText(tester, 'No, it\'s new');
      expect(find.text('Join it in Wi-Fi settings'), findsOneWidget);
      expect(find.text('1. Open Wi-Fi settings'), findsOneWidget);
      expect(find.text('2. Join WLED-AP. The password is wled1234.'), findsOneWidget);
      expect(find.text('3. Come back to Glyph.'), findsOneWidget);
      expect(find.text('Waiting for your device…'), findsOneWidget);
      expect(find.text('Use Wi-Fi settings instead'), findsNothing);
      await tapText(tester, 'Open Wi-Fi settings');
      expect(rig.wifi.settingsOpened, 1);
      // The app notices the device and moves on by itself.
      await settle(tester, 1200);
      expect(find.text('Which Wi-Fi should it join?'), findsOneWidget);
      // A network with no internet is skipped by Android's default route.
      expect(rig.wifi.binds, greaterThan(0));
      rig.playback.pause();
    });

    testWidgets('guided on iOS: no settings button, "I\'ve joined it" checks at once', (tester) async {
      final rig = await joinRig(
        tester,
        wifi: FakeSetupWifi(assisted: false, canOpenWifiSettings: false),
      );
      rig.ap.reachable = false;
      await tapText(tester, 'No, it\'s new');
      expect(find.text('1. Open the Settings app, then Wi-Fi.'), findsOneWidget);
      expect(find.text('2. Join WLED-AP. The password is wled1234.'), findsOneWidget);
      expect(find.text('3. Come back to Glyph.'), findsOneWidget);
      expect(find.text('Open Wi-Fi settings'), findsNothing);
      expect(find.text('Still looking for your device…'), findsNothing);
      await tapText(tester, 'I\'ve joined it');
      expect(find.text('Still looking for your device…'), findsOneWidget);
      expect(rig.wifi.settingsOpened, 0);
      rig.ap.reachable = true;
      await tapText(tester, 'I\'ve joined it', ms: 800);
      expect(find.text('Which Wi-Fi should it join?'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('assisted can be set aside for the guided steps', (tester) async {
      final rig = await joinRig(tester);
      await tapText(tester, 'No, it\'s new');
      await tapText(tester, 'Use Wi-Fi settings instead');
      expect(find.text('Join it in Wi-Fi settings'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('a renamed setup network is asked for by name', (tester) async {
      final rig = await joinRig(tester);
      await tapText(tester, 'No, it\'s new');
      await tapText(tester, 'Renamed its network?');
      await tester.enterText(find.byType(TextField).first, 'MyLamp');
      await tester.enterText(find.byType(TextField).last, 'secret99');
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await settle(tester, 800);
      expect(rig.wifi.connects.single.ssid, 'MyLamp');
      expect(rig.wifi.connects.single.password, 'secret99');
      rig.playback.pause();
    });

    testWidgets('a cancelled or unavailable system dialog stays on Join with words', (tester) async {
      final wifi = FakeSetupWifi(result: const SetupWifiUnavailable());
      final rig = await joinRig(tester, wifi: wifi);
      await tapText(tester, 'No, it\'s new');
      await tapText(tester, 'Connect');
      expect(find.text('Connect to your device'), findsOneWidget);
      expect(find.textContaining('Couldn\'t connect to its Wi-Fi network'), findsOneWidget);
      // A device that was set up before shows its network only briefly:
      // Wi-Fi settings (which keeps retrying) leads, Connect becomes Try again.
      expect(find.widgetWithText(FilledButton, 'Use Wi-Fi settings instead'), findsOneWidget);
      wifi.result = const SetupWifiCancelled();
      await tapText(tester, 'Try again');
      expect(find.textContaining('Couldn\'t connect to its Wi-Fi network'), findsNothing);
      wifi.result = const SetupWifiDenied();
      await tapText(tester, 'Connect');
      expect(find.text('Join it in Wi-Fi settings'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('joining fails: causes and the way on', (tester) async {
      final rig = await joinRig(tester, findTimeout: const Duration(seconds: 3));
      // A different MAC, so the search never finds this device.
      rig.controller.setupMac = 'ffffffffffff';
      await tapText(tester, 'No, it\'s new');
      await tapText(tester, 'Connect', ms: 800);
      rig.controller.setupMac = 'ffffffffffff';
      await tapText(tester, 'Home');
      await tester.enterText(find.byType(TextField).last, 'hunter22');
      await settle(tester, 100);
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await settle(tester, 800);
      expect(find.text('Joining Home'), findsOneWidget);
      expect(find.text('Sent the Wi-Fi details'), findsOneWidget);
      expect(find.text('Looking for it on your Wi-Fi…'), findsOneWidget);
      await settle(tester, 3500);
      expect(find.text('Couldn\'t find it on Home'), findsOneWidget);
      expect(find.textContaining('The password may be wrong'), findsOneWidget);
      expect(find.text('It may be too far from your router.'), findsOneWidget);
      expect(find.text('Your Wi-Fi may be 5 GHz only.'), findsOneWidget);
      expect(find.text('Enter its address'), findsOneWidget);
      await tapText(tester, 'Try again');
      expect(find.text('Connect to your device'), findsOneWidget);
      rig.playback.pause();
    });

    testWidgets('Back while looking cancels the search', (tester) async {
      final rig = await joinRig(tester);
      rig.controller.setupMac = 'ffffffffffff';
      await tapText(tester, 'No, it\'s new');
      await tapText(tester, 'Connect', ms: 800);
      rig.controller.setupMac = 'ffffffffffff';
      await tapText(tester, 'Home');
      await tester.enterText(find.byType(TextField).last, 'pw123456');
      await settle(tester, 100);
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await settle(tester, 800);
      expect(find.text('Looking for it on your Wi-Fi…'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester, 600);
      expect(find.text('Connect to your device'), findsOneWidget);
      // The late timeout does nothing.
      await settle(tester, 6000);
      expect(find.text('Connect to your device'), findsOneWidget);
      expect(find.textContaining('Couldn\'t find it on'), findsNothing);
      rig.playback.pause();
    });
  });
}
