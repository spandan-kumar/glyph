import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/device/setup/setup_wifi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const ch = MethodChannel('glyph/setup_wifi');
  final calls = <MethodCall>[];

  void native(Future<Object?> Function(MethodCall) h) {
    messenger.setMockMethodCallHandler(ch, (c) {
      calls.add(c);
      return h(c);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(ch, null));

  test('not assisted below API 29 or before probe', () async {
    expect(PlatformSetupWifi().assisted, isFalse);
    final w = PlatformSetupWifi(sdk: 28);
    expect(w.assisted, isFalse);
    expect(await w.connect(), isA<SetupWifiUnsupported>());
    expect(calls, isEmpty);
  });

  test('connect passes arguments and returns the ssid', () async {
    native((_) async => 'WLED-AP');
    final w = PlatformSetupWifi(sdk: 30, requestLocation: () async => true);
    final r = await w.connect();
    expect(r, isA<SetupWifiConnected>().having((c) => c.ssid, 'ssid', 'WLED-AP'));
    expect(calls.single.arguments, {'ssid': null, 'prefix': 'WLED', 'password': 'wled1234'});
  });

  test('API 33+ asks for nearby devices first; denial skips native', () async {
    native((_) async => 'x');
    var asked = 0;
    final w = PlatformSetupWifi(sdk: 34, requestNearby: () async { asked++; return false; });
    expect(await w.connect(), isA<SetupWifiDenied>());
    expect(asked, 1);
    expect(calls, isEmpty);
    final ok = PlatformSetupWifi(sdk: 34, requestNearby: () async => true);
    expect(await ok.connect(ssid: 'Mine'), isA<SetupWifiConnected>());
  });

  test(
    'API 29-32 requests location, not nearby; denial skips native', () async {
    native((_) async => 'x');
      for (final sdk in [29, 30, 31, 32]) {
        var asked = 0;
        final w = PlatformSetupWifi(sdk: sdk, requestNearby: () async => fail('nearby'),
          requestLocation: () async {
            asked++;
            return false;
          },
        );
    expect(await w.connect(), isA<SetupWifiDenied>());
        expect(asked, 1);
        expect(calls, isEmpty);
        final ok = PlatformSetupWifi(
          sdk: sdk,
          requestLocation: () async => true,
        );
        expect(await ok.connect(), isA<SetupWifiConnected>());
        calls.clear();
      }
    },
  );

  test('API 31 uses permission_handler location permission before native connect', () async {
    const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
    final asked = <MethodCall>[];
    messenger.setMockMethodCallHandler(permissions, (call) async {
      asked.add(call);
      return {5: 0};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));
    native((_) async => 'x');
    expect(await PlatformSetupWifi(sdk: 31).connect(), isA<SetupWifiDenied>());
    expect(asked.single.method, 'requestPermissions');
    expect(asked.single.arguments, [5]);
    expect(calls, isEmpty);
  });

  test('error codes map to results', () async {
    final w = PlatformSetupWifi(sdk: 30, requestLocation: () async => true);
    for (final (code, type) in [
      ('unavailable', isA<SetupWifiUnavailable>()),
      ('cancelled', isA<SetupWifiCancelled>()),
      ('denied', isA<SetupWifiDenied>()),
      ('unsupported', isA<SetupWifiUnsupported>()),
      ('failed', isA<SetupWifiFailed>()),
    ]) {
      native((_) async => throw PlatformException(code: code));
      expect(await w.connect(), type, reason: code);
    }
  });

  test('missing plugin means unsupported; release/openSettings are safe', () async {
    final w = PlatformSetupWifi(sdk: 30,
        requestLocation: () async => true,
      ); // no handler registered
    expect(await w.connect(), isA<SetupWifiUnsupported>());
    await w.release();
    await w.openSettings();
  });

  test('release and openSettings call native', () async {
    native((_) async => null);
    final w = PlatformSetupWifi(sdk: 30, requestLocation: () async => true);
    await w.release();
    await w.openSettings();
    expect(calls.map((c) => c.method), ['release', 'openSettings']);
  });
}
