import 'dart:convert';

import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../wled/fixtures.dart';
import '../../wled/manage_fixtures.dart';

/// In-memory WLED 16 built from real-device fixtures, served through
/// package:http's MockClient. Records every POST and every GET path.
class FakeWled {
  FakeWled() {
    presets = {
      ...jsonDecode(presetsV16) as Map<String, dynamic>,
      '201': jsonDecode(storedPlaylistV16),
    };
    state = jsonDecode(stateV16) as Map<String, dynamic>;
    cfg = jsonDecode(cfgV16) as Map<String, dynamic>;
    cfg['timers'] = {'ins': jsonDecode(timersBackV16)};
    files = (jsonDecode(filesV16) as List).cast<Map<String, dynamic>>();
  }

  /// The device's file listing; deletes remove entries.
  late List<Map<String, dynamic>> files;

  /// Per-file GIF contents ("/duck.gif" → bytes); others get [gif].
  final gifs = <String, List<int>>{};

  /// Power-on preset (cfg def.ps).
  int get bootPreset => ((cfg['def'] as Map?)?['ps'] as num?)?.toInt() ?? 0;

  /// The one file of a multipart upload: its name and bytes.
  static (String, List<int>) _multipart(http.Request r) {
    final boundary = RegExp(r'boundary=(.+)$').firstMatch(r.headers['content-type'] ?? '')!.group(1)!;
    final text = latin1.decode(r.bodyBytes);
    final part = text.split('--$boundary')[1];
    final name = RegExp(r'filename="([^"]*)"').firstMatch(part)!.group(1)!;
    final start = part.indexOf('\r\n\r\n') + 4;
    final data = part.substring(start, part.length - 2); // drop the closing CRLF
    return (name.startsWith('/') ? name : '/$name', latin1.encode(data));
  }

  late Map<String, dynamic> presets;
  late Map<String, dynamic> state;
  late Map<String, dynamic> cfg;
  final posts = <(String path, Map<String, dynamic> body)>[];
  final gets = <String>[];

  /// Paths uploaded through POST /upload, in order.
  final uploads = <String>[];

  /// Files removed through /edit?func=delete.
  final deleted = <String>[];
  bool offline = false;

  /// 1×1 GIF.
  static final gif = base64Decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7');

  WledClient client(String host) => WledClient(host, client: MockClient(_handle));

  Future<http.Response> _handle(http.Request r) async {
    if (offline) throw http.ClientException('offline');
    final path = r.url.path;
    if (r.method == 'POST' && path == '/upload') {
      final (name, bytes) = _multipart(r);
      uploads.add(name);
      files.removeWhere((f) => '/${f['name']}' == name);
      files.add({'name': name.substring(1), 'type': 'file', 'size': bytes.length});
      if (name == '/presets.json') {
        presets = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
      } else {
        gifs[name] = bytes;
      }
      return http.Response('File Uploaded!', 200);
    }
    if (r.method == 'POST') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      // Power-on preset changes (cfg.cpp: def.ps).
      if (path == '/json/cfg' && body['def'] is Map) {
        cfg['def'] = {...(cfg['def'] as Map? ?? const {}), ...(body['def'] as Map)};
      }
      posts.add((path, body));
      if (path == '/json/state') {
        for (final k in ['on', 'bri']) {
          if (body.containsKey(k)) state[k] = body[k];
        }
        if (body['ps'] is int) state['ps'] = body['ps'];
        final pdel = body['pdel'];
        if (pdel is int) presets.remove('$pdel');
      }
      return http.Response('{"success":true}', 200);
    }
    gets.add(path);
    if (path == '/edit' && r.url.queryParameters['func'] == 'delete') {
      final p = r.url.queryParameters['path'] ?? '';
      deleted.add(p);
      files.removeWhere((f) => '/${f['name']}' == p);
      return http.Response('deleted', 200);
    }
    return switch (path) {
      '/json/info' => http.Response(infoEsp32V16, 200),
      '/json/eff' => http.Response(jsonEncode(effectsEsp32V16), 200),
      '/json/state' => http.Response(jsonEncode(state), 200),
      '/json/cfg' || '/cfg.json' => http.Response(jsonEncode(cfg), 200),
      '/presets.json' => http.Response(jsonEncode(presets), 200),
      '/edit' => http.Response(jsonEncode(files), 200),
      _ when path.endsWith('.gif') => files.any((f) => '/${f['name']}' == path)
          ? http.Response.bytes(gifs[path] ?? gif, 200)
          : http.Response('Not found', 404),
      _ => http.Response('Not found', 404),
    };
  }
}
