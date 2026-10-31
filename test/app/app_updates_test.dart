import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/app_updates.dart';
import 'package:glyph/app/community.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  const latest = 'https://github.com/spandan-kumar/glyph/releases/tag/v1.4.0';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 31, 12);
  });

  AppUpdates create(http.Client client, {String version = '1.3.0'}) =>
      AppUpdates(client: client, now: () => now, version: () async => version);

  http.Response release(
    String tag, {
    bool draft = false,
    bool prerelease = false,
    String? url,
  }) => http.Response(
    jsonEncode({
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'html_url': url ?? latest,
    }),
    200,
  );

  test(
    'newer release is cached with a trusted URL and minimal request headers',
    () async {
      late http.Request request;
      final updates = create(
        MockClient((r) async {
          request = r;
          return release('v1.4.0');
        }),
      );
      addTearDown(updates.dispose);
      await updates.check();
      expect(updates.hasUpdate, isTrue);
      expect(updates.latestVersion, '1.4.0');
      expect(updates.latestUrl.toString(), latest);
      expect(request.url.toString(), AppUpdates.endpoint);
      // Header names are case-insensitive; compare them that way.
      expect(
        {for (final e in request.headers.entries) e.key.toLowerCase(): e.value},
        {'accept': 'application/vnd.github+json', 'user-agent': 'Glyph'},
      );
    },
  );

  test('same and older releases are ignored', () async {
    for (final tag in ['v1.3.0', 'v1.2.9']) {
      final updates = create(MockClient((_) async => release(tag)));
      await updates.check();
      expect(updates.hasUpdate, isFalse, reason: tag);
      updates.dispose();
    }
  });

  test(
    'draft, prerelease, malformed tags and foreign URLs are handled safely',
    () async {
      for (final response in [
        release('v1.4.0', draft: true),
        release('v1.4.0', prerelease: true),
        release('release-1.4', url: latest),
      ]) {
        // Each response gets a fresh daily check, so none is throttled away.
        now = now.add(const Duration(hours: 25));
        final updates = create(MockClient((_) async => response));
        await updates.check();
        expect(updates.hasUpdate, isFalse);
        updates.dispose();
      }
      now = now.add(const Duration(hours: 25));
      final updates = create(
        MockClient(
          (_) async => release('v1.4.0', url: 'https://evil.example/x'),
        ),
      );
      await updates.check();
      expect(updates.latestUrl, Community.latestRelease);
      updates.dispose();
    },
  );

  test('records a failed attempt and throttles for 24 hours', () async {
    var calls = 0;
    final updates = create(
      MockClient((_) async {
        calls++;
        return release('v1.4.0');
      }),
    );
    await updates.check();
    await updates.check();
    expect(calls, 1);
    now = now.add(const Duration(hours: 24));
    await updates.check();
    expect(calls, 2);
    updates.dispose();
  });

  test('disabled checks make no request and clear the notice', () async {
    SharedPreferences.setMockInitialValues({
      AppUpdates.latestKey: '1.4.0',
      AppUpdates.latestUrlKey: latest,
    });
    var calls = 0;
    final updates = create(
      MockClient((_) async {
        calls++;
        return release('v1.5.0');
      }),
    );
    await updates.load();
    expect(updates.hasUpdate, isTrue);
    await updates.setEnabled(false);
    await updates.check();
    expect(calls, 0);
    expect(updates.hasUpdate, isFalse);
    updates.dispose();
  });

  test('drops cached release when app version catches up', () async {
    SharedPreferences.setMockInitialValues({
      AppUpdates.latestKey: '1.4.0',
      AppUpdates.latestUrlKey: latest,
    });
    final updates = create(
      MockClient((_) async => release('v1.5.0')),
      version: '1.4.0',
    );
    await updates.load();
    expect(updates.hasUpdate, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString(AppUpdates.latestKey),
      isNull,
    );
    updates.dispose();
  });

  test('announces once per version', () async {
    final updates = create(MockClient((_) async => release('v1.4.0')));
    await updates.check();
    expect(updates.takeAnnouncement(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(updates.takeAnnouncement(), isFalse);
    updates.dispose();
  });

  test('oversized and garbage replies fail silently', () async {
    for (final body in [
      '{',
      List.filled(AppUpdates.maxResponseBytes + 1, 'x').join(),
    ]) {
      final updates = create(MockClient((_) async => http.Response(body, 200)));
      await updates.check();
      expect(updates.hasUpdate, isFalse);
      updates.dispose();
    }
    final offline = create(
      MockClient((_) async => throw const SocketException('offline')),
    );
    await offline.check();
    expect(offline.hasUpdate, isFalse);
    offline.dispose();
  });
}
