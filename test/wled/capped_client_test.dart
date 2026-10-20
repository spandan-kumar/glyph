import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/capped_client.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  /// A reply of [chunks] × [chunkSize] bytes, optionally announcing its length.
  /// [cancelled] completes if the reader stops listening early.
  MockClient streaming(int chunks, int chunkSize,
      {bool announce = false, Completer<void>? cancelled}) {
    return MockClient.streaming((request, _) async {
      final body = StreamController<List<int>>(
        onCancel: () => cancelled?.complete(),
      );
      unawaited(() async {
        for (var i = 0; i < chunks && !body.isClosed; i++) {
          await Future<void>.delayed(Duration.zero);
          if (!body.hasListener) break;
          body.add(List.filled(chunkSize, 0x20));
        }
        await body.close();
      }());
      return http.StreamedResponse(body.stream, 200,
          contentLength: announce ? chunks * chunkSize : null);
    });
  }

  test('passes replies within the limit through unchanged', () async {
    final client = CappedClient(streaming(4, 25), 100);
    final res = await client.get(Uri.parse('http://device/json/state'));
    expect(res.bodyBytes, hasLength(100));
  });

  test('refuses a reply that announces a larger length', () async {
    final client = CappedClient(streaming(4, 30, announce: true), 100);
    await expectLater(client.get(Uri.parse('http://device/x')),
        throwsA(isA<http.ClientException>()));
  });

  test('cuts off an unannounced reply once it passes the limit', () async {
    final cancelled = Completer<void>();
    final client = CappedClient(streaming(1000, 30, cancelled: cancelled), 100);
    await expectLater(client.get(Uri.parse('http://device/x')),
        throwsA(isA<http.ClientException>()));
    await cancelled.future.timeout(const Duration(seconds: 1));
  });

  test('WledClient turns an oversized reply into a WledException', () async {
    final huge = WledClient.maxResponseBytes + 1;
    final wled = WledClient('device', client: MockClient.streaming((request, _) async {
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200, contentLength: huge);
    }));
    await expectLater(wled.state(), throwsA(isA<WledException>()));
  });
}
