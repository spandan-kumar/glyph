import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

void main() {
  late List<http.Request> requests;
  late Map<String, Object> presetsJson;
  late Map<String, Object> stateJson;

  WledClient client() => WledClient('192.168.29.6', client: MockClient((r) async {
        requests.add(r);
        return switch (r.url.path) {
          '/presets.json' => http.Response(jsonEncode(presetsJson), 200),
          '/json/state' when r.method == 'GET' =>
            http.Response(jsonEncode(stateJson), 200),
          '/json/state' => http.Response('{"success":true}', 200),
          '/upload' => http.Response('File Uploaded!', 200),
          '/edit' => http.Response('[{"name":"pipplee.gif","type":"file","size":4000}]', 200),
          _ => http.Response('Not found', 404),
        };
      }));

  setUp(() {
    requests = [];
    presetsJson = {
      '0': {},
      '1': {'n': 'One'},
      '2': {},
      '3': {'on': true},
      '101': {'n': 'WLED Turn Off', 'on': false},
    };
    stateJson = {
      'seg': [
        {'id': 0, 'fx': 53, 'n': 'glyph_test.gif'}
      ]
    };
  });

  test('presets skip id 0 and empty slots', () async {
    final c = client();
    expect(await c.presets(), {1: 'One', 3: 'Preset 3', 101: 'WLED Turn Off'});
    expect(await c.firstFreePresetId(), 2);
  });

  test('gif segment names drop the slash and require .gif', () {
    expect(WledClient.gifSegmentName('/anim.gif'), 'anim.gif');
    expect(WledClient.gifSegmentName('Anim.GIF'), 'Anim.gif');
    expect(() => WledClient.gifSegmentName('anim.png'), throwsA(isA<WledException>()));
    expect(() => WledClient.gifSegmentName('a/b.gif'), throwsA(isA<WledException>()));
    expect(() => WledClient.gifSegmentName('${'x' * 40}.gif'),
        throwsA(isA<WledException>()));
  });

  test('upload uses multipart field "data" with the path as filename', () async {
    await client().uploadFile('glyph_test.gif', Uint8List.fromList([71, 73, 70]));
    final r = requests.single;
    expect(r.method, 'POST');
    expect(r.url.path, '/upload');
    expect(r.headers['content-type'], startsWith('multipart/form-data'));
    final body = latin1.decode(r.bodyBytes);
    expect(body, contains('name="data"'));
    expect(body, contains('filename="/glyph_test.gif"'));
  });

  test('saveGifToDevice: release, upload, then switch (leave live, play, save)', () async {
    final caps = DeviceCapabilities.detect(
        WledInfo.fromJson(jsonDecode(infoEsp32V16)), effectsEsp32V16);
    var switched = false;
    final id = await client().saveGifToDevice(
        fileName: 'glyph_test.gif',
        gif: Uint8List(2048),
        presetName: 'Glyph test',
        caps: caps,
        beforeSwitch: () async => switched = true);
    expect(id, 2);
    expect(switched, isTrue);
    final posts = [
      for (final r in requests)
        if (r.url.path == '/json/state' && r.method == 'POST') jsonDecode(r.body)
    ];
    expect(posts[0], {
      'tt': 0,
      'seg': {'id': 0, 'fx': 0}
    });
    expect(posts[1], {'live': false});
    expect(posts[2]['seg'], containsPair('n', 'glyph_test.gif'));
    expect(posts[2]['seg'], containsPair('fx', 53));
    expect(posts[3], {'psave': 2, 'n': 'Glyph test', 'ib': true, 'sb': true});
    expect(requests.where((r) => r.url.path == '/upload'), hasLength(1));
    // The matrix only leaves live mode after the file is safely uploaded.
    final upload = requests.indexWhere((r) => r.url.path == '/upload');
    final leave = requests.indexWhere((r) => r.method == 'POST' && r.body == '{"live":false}');
    expect(upload, lessThan(leave));
  });

  test('saveGifToDevice: a failed upload retries and leaves the matrix untouched', () async {
    final caps = DeviceCapabilities.detect(
        WledInfo.fromJson(jsonDecode(infoEsp32V16)), effectsEsp32V16);
    final retries = <int>[];
    var switched = false;
    final flaky = WledClient('192.168.29.6', client: MockClient((r) async {
      requests.add(r);
      return switch (r.url.path) {
        '/json/state' when r.method == 'GET' => http.Response(jsonEncode(stateJson), 200),
        '/json/state' => http.Response('{"success":true}', 200),
        '/upload' => http.Response('busy', 500),
        '/edit' => http.Response('[]', 200),
        _ => http.Response('{}', 200),
      };
    }));
    await expectLater(
      flaky.saveGifToDevice(
          fileName: 'glyph_test.gif',
          gif: Uint8List(2048),
          presetName: 'Glyph test',
          caps: caps,
          beforeSwitch: () async => switched = true,
          onRetry: retries.add),
      throwsA(isA<WledException>()),
    );
    expect(requests.where((r) => r.url.path == '/upload'), hasLength(3));
    expect(retries, [2, 3]);
    expect(switched, isFalse);
    expect(requests.any((r) => r.method == 'POST' && r.body.contains('"live"')), isFalse);
    expect(requests.any((r) => r.method == 'POST' && r.body.contains('psave')), isFalse);
  });

  test('saveGifToDevice refuses devices without GIF support or space', () async {
    final esp8266 = DeviceCapabilities.detect(
        WledInfo.fromJson(jsonDecode(infoEsp8266V014)), effectsEsp32V16);
    await expectLater(
        client().saveGifToDevice(
            fileName: 'a.gif', gif: Uint8List(10), presetName: 'a', caps: esp8266),
        throwsA(isA<WledException>()));

    final esp32 = DeviceCapabilities.detect(
        WledInfo.fromJson(jsonDecode(infoEsp32V16)), effectsEsp32V16);
    await expectLater(
        client().saveGifToDevice(
            fileName: 'a.gif',
            gif: Uint8List(esp32.freeFsBytes),
            presetName: 'a',
            caps: esp32),
        throwsA(isA<WledException>()));
    expect(requests.where((r) => r.url.path == '/upload'), isEmpty);
  });

  test('HTTP errors become WledException', () async {
    final c = WledClient('10.0.0.9',
        client: MockClient((_) async => http.Response('nope', 500)));
    await expectLater(c.info(), throwsA(isA<WledException>()));
  });
}
