import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/community.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/features/device/boot_intro.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/device/fake_wled.dart';

void main() {
  const env = AppEnv(version: '1.3.0', build: '5', phone: 'Google Pixel 7', os: 'Android 14 (SDK 34)');

  const connected = Diagnostics(
    env: env,
    deviceCount: 2,
    connected: true,
    wledVersion: '16.0.1',
    arch: 'esp32',
    ledCount: 256,
    width: 16,
    height: 16,
    freeKb: 900,
    streaming: true,
  );

  tearDown(LastError.clear);

  test('bug report uses the issue form field ids', () {
    final uri = Community.feedback(connected);
    expect(uri.host, 'github.com');
    expect(uri.path, '/spandan-kumar/glyph/issues/new');
    final q = uri.queryParameters;
    expect(q['template'], 'bug.yml');
    expect(q['labels'], 'bug,community');
    expect(q['app_version'], '1.3.0 (5)');
    expect(q['phone'], 'Google Pixel 7, Android 14 (SDK 34)');
    expect(q['wled_version'], '16.0.1');
    expect(q['panel'], '16×16');
    expect(q['diagnostics'], connected.text);
    expect(q.containsKey('what_happened'), isFalse, reason: 'left for the person');
    expect(connected.text, contains('Streaming: yes'));
    expect(connected.text, contains('WLED 16.0.1 · esp32 · 256 LEDs · 16×16 · 900 KB free'));
  });

  test('values are percent-encoded: spaces are %20, not +', () {
    final s = Community.feedback(connected).toString();
    expect(s, contains('phone=Google%20Pixel%207'));
    expect(s, contains('panel=16%C3%9716'));
    expect(s, isNot(contains('+')));
    expect(s, isNot(contains(' ')));
  });

  test('no device: firmware and panel are left blank for the person', () {
    const d = Diagnostics(env: env);
    final q = Community.feedback(d).queryParameters;
    expect(q.containsKey('wled_version'), isFalse);
    expect(q.containsKey('panel'), isFalse);
    expect(q['diagnostics'], contains('Device: not connected'));
  });

  test('other links: idea, animation, display, show-and-tell, roadmap', () {
    final idea = Community.idea(connected).queryParameters;
    expect(idea, {'template': 'feedback.yml', 'labels': 'feedback,community', 'app_version': '1.3.0 (5)'});
    final anim = Community.animationRequest(connected).queryParameters;
    expect(anim, {'template': 'animation_request.yml', 'labels': 'animation-request,community', 'panel': '16×16'});
    expect(Community.displayRequest().queryParameters, {'template': 'display_request.yml'});
    expect('${Community.showAndTell}', 'https://github.com/spandan-kumar/glyph/discussions/categories/show-and-tell');
    expect('${Community.roadmap}', 'https://github.com/users/spandan-kumar/projects/4');
  });

  test('a huge last error is cut so the URL stays under the limit', () {
    LastError.record('Ünïcode ✓ ${'x y ' * 5000}');
    final d = Diagnostics(env: env, lastError: LastError.message, deviceCount: 1);
    // LastError caps itself; push past that with a long phone string too.
    final long = Diagnostics(
      env: AppEnv(version: '1.3.0', phone: 'P' * 100),
      lastError: '✓ ' * 4000,
    );
    for (final x in [d, long]) {
      final uri = Community.feedback(x);
      expect(uri.toString().length, lessThanOrEqualTo(Community.maxUrlLength));
      expect(uri.queryParameters['template'], 'bug.yml');
    }
    expect(Community.feedback(long).queryParameters['diagnostics'], endsWith('(cut to fit)'));
  });

  test('fitEncoded keeps text that fits and never splits a surrogate pair', () {
    expect(Community.fitEncoded('short', 100), 'short');
    final cut = Community.fitEncoded('🙂' * 200, 300);
    expect(Uri.encodeComponent(cut).length, lessThanOrEqualTo(300));
    expect(() => Uri.encodeComponent(cut), returnsNormally);
  });

  test('scrubPersonal removes addresses, URLs, MACs and hostnames', () {
    final s = scrubPersonal(
      'SocketException: refused, address = 192.168.29.6, port = 80 '
      'uri=http://192.168.29.6/json/state host wled-abc.local mac aa:bb:cc:dd:ee:ff fe80::1 '
      '2001:db8:0:0:0:0:0:1 a0b1c2d3e4f5 in Living Room',
      extra: ['Living Room'],
    );
    for (final leak in ['192.168', 'http', '.local', 'aa:bb', 'fe80', '2001:db8', 'a0b1c2d3e4f5', 'Living Room']) {
      expect(s, isNot(contains(leak)), reason: leak);
    }
    expect(s, contains('SocketException'));
  });

  test('captured diagnostics never carry IPs, hostnames or device names', () async {
    BootIntro.autoInstall = false;
    addTearDown(BootIntro.resetForTest);
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([
        const SavedDevice(host: '192.168.29.6', name: 'Kitchen Panel').toJson(),
        const SavedDevice(host: 'glyph-shelf.local', name: 'Shelf').toJson(),
      ]),
      'devices.selected': '192.168.29.6',
    });
    final wled = FakeWled();
    final devices = DeviceStore(clientFactory: wled.client);
    await devices.load();
    await devices.refresh();
    expect(devices.isConnected, isTrue);
    final info = devices.info!;
    LastError.record('Couldn\'t reach 192.168.29.6 (Kitchen Panel) at http://glyph-shelf.local/json');

    final d = Diagnostics.capture(env, devices, streaming: false, now: DateTime.now());
    final url = Community.feedback(d).toString();
    final decoded = Uri.decodeFull(url);
    // The fake is named "WLED", which also (rightly) appears as the firmware.
    for (final leak in ['192.168', 'glyph-shelf', 'Kitchen Panel', 'Shelf', info.mac, info.ip]) {
      if (leak.isEmpty) continue;
      expect(decoded, isNot(contains(leak)), reason: leak);
    }
    expect(d.deviceCount, 2);
    expect(d.text, contains('WLED ${info.version}'));
    expect(d.text, contains('Last error: Couldn'));
    devices.dispose();
  });
}
