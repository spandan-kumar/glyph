import 'dart:convert';

import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../wled/fixtures.dart';
import '../../wled/manage_fixtures.dart';

/// In-memory WLED 16 built from real-device fixtures, served through
/// package:http's MockClient. Records every POST.
class FakeWled {
  FakeWled() {
    presets = {
      ...jsonDecode(presetsV16) as Map<String, dynamic>,
      '201': jsonDecode(storedPlaylistV16),
    };
    state = jsonDecode(stateV16) as Map<String, dynamic>;
    cfg = jsonDecode(cfgV16) as Map<String, dynamic>;
    cfg['timers'] = {'ins': jsonDecode(timersBackV16)};
  }

  late Map<String, dynamic> presets;
  late Map<String, dynamic> state;
  late Map<String, dynamic> cfg;
  final posts = <(String path, Map<String, dynamic> body)>[];
  bool offline = false;

  /// 1×1 GIF.
  static final gif = base64Decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7');

  WledClient client(String host) => WledClient(host, client: MockClient(_handle));

  Future<http.Response> _handle(http.Request r) async {
    if (offline) throw http.ClientException('offline');
    final path = r.url.path;
    if (r.method == 'POST') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
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
    return switch (path) {
      '/json/info' => http.Response(infoEsp32V16, 200),
      '/json/eff' => http.Response(jsonEncode(effectsEsp32V16), 200),
      '/json/state' => http.Response(jsonEncode(state), 200),
      '/json/cfg' || '/cfg.json' => http.Response(jsonEncode(cfg), 200),
      '/presets.json' => http.Response(jsonEncode(presets), 200),
      '/edit' => http.Response(filesV16, 200),
      _ when path.endsWith('.gif') => http.Response.bytes(gif, 200),
      _ => http.Response('Not found', 404),
    };
  }
}
