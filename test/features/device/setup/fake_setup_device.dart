import 'dart:convert';

import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory WLED for the setup wizard: serves `/json/cfg`, `/json/info`
/// (derived from the config) and applies `/settings/2D` forms, config
/// patches and the `pin`/`rb` state keys. Records every write in [writes].
class FakeSetupDevice {
  FakeSetupDevice({
    this.mac = '48e729a39308',
    int width = 16,
    int height = 8,
    bool matrix = true,
    this.ledCount = 128,
    this.pin,
    this.customMap = false,
    this.mapFiles = const [],
    int playingFx = 0,
    String? playingName,
    List<Map<String, dynamic>>? panels,
  }) {
    state = {
      'on': true,
      'bri': 128,
      'ps': -1,
      'pl': -1,
      'seg': <Map<String, dynamic>>[
        {'id': 0, 'fx': playingFx, 'n': ?playingName, 'start': 0, 'stop': 16}
      ],
    };
    cfg = {
      'hw': {
        'led': {
          'maxpwr': 1000,
          if (matrix)
            'matrix': {
              'mpc': panels?.length ?? 1,
              'panels': panels ??
                  [
                    {'b': false, 'r': false, 'v': false, 's': false, 'x': 0, 'y': 0, 'w': width, 'h': height}
                  ]
            },
          'ins': [
            {
              'start': 0, 'len': ledCount, 'pin': [16], 'order': 1, 'rev': false, 'skip': 0,
              'type': 22, 'ref': false, 'rgbwm': 255, 'freq': 0, 'maxpwr': 0, 'ledma': 55, 'drv': 0, 'text': '',
            }
          ],
        }
      },
      'if': <String, dynamic>{
        'live': {'en': true, 'rlm': true, 'offset': 0, 'timeout': 25, 'no-gc': true}
      },
    };
  }

  final String mac;
  int ledCount;
  final String? pin;

  /// Reports a custom LED map in `/json/info`.
  final bool customMap;
  final List<String> mapFiles;
  Future<void> Function(http.Request)? beforeRequest;
  void Function(http.Request)? afterRequest;
  int clientsClosed = 0;
  late Map<String, dynamic> cfg;
  bool unlocked = false;

  /// Unix seconds pushed to `/json/state` "time", and `if.ntp` config writes.
  final clockSets = <int>[];
  final ntpWrites = <Map<String, dynamic>>[];

  /// `/json/state`: segment 0 falls back to Solid on every layout write, like
  /// WLED's makeAutoSegments.
  late Map<String, dynamic> state;

  /// Preset id to the effect it plays.
  final presets = <int, int>{};

  Map get seg0 => (state['seg'] as List).first as Map;
  int get fx => seg0['fx'] as int;

  /// When true every request fails like an unreachable device.
  bool offline = false;

  /// When true the device ignores layout forms (to test verification).
  bool ignoreLayout = false;

  /// "METHOD /path" with the decoded body (JSON map or form map).
  final writes = <(String, Object?)>[];
  final gets = <String>[];

  bool get _locked => pin != null && !unlocked;
  Map get _led => (cfg['hw'] as Map)['led'] as Map;
  Map get _live => (cfg['if'] as Map)['live'] as Map;
  Map? get panel => (_led['matrix'] as Map?)?['panels'][0] as Map?;

  /// Every panel the device has, in chain order (empty for a strip).
  List<Map> get panels => [
    for (final p in ((_led['matrix'] as Map?)?['panels'] as List? ?? const [])) p as Map,
  ];
  int get rlmValue => _live['rlm'] == true ? 1 : 0;
  int? get limit => _led['maxpwr'] as int?;
  int get length => ((_led['ins'] as List).first as Map)['len'] as int;

  WledClient client(String host, {Future<void> Function(Duration)? delay}) =>
      WledClient(host, delay: delay ?? (_) async {}, client: _SetupHttpClient((r) async {
          await beforeRequest?.call(r);
          final response = await _handle(r);
          afterRequest?.call(r);
          return response;
        }, () => clientsClosed++),
      );

  Map<String, dynamic> get info {
    final p = panel;
    return {
      'ver': '16.0.1', 'name': 'Desk', 'mac': mac, 'brand': 'WLED', 'arch': 'esp32',
      'leds': {
        'count': length,
        if (p != null)
          'matrix': {
            'w': panels.map((q) => (q['x'] as int) + (q['w'] as int)).reduce((a, b) => a > b ? a : b),
            'h': panels.map((q) => (q['y'] as int) + (q['h'] as int)).reduce((a, b) => a > b ? a : b),
          },
      },
      'maps': [
        {'id': 0},
        if (customMap) {'id': 1, 'n': 'Panel'},
      ],
      'fxcount': 1, 'ip': '192.168.1.50',
      'fs': {'u': 100, 't': 1000},
    };
  }

  Future<http.Response> _handle(http.Request r) async {
    if (offline) throw http.ClientException('offline');
    final path = r.url.path;
    if (r.method == 'GET') {
      gets.add(path);
      switch (path) {
        case '/edit':
          return http.Response(
            jsonEncode([
              for (final file in mapFiles)
                {'type': 'file', 'name': file, 'size': 42},
            ]),
            200,
          );
        case '/json/info':
          return http.Response(jsonEncode(info), 200);
        case '/json/cfg':
          return http.Response(jsonEncode(cfg), 200);
        case '/cfg.json':
          return http.Response(jsonEncode(cfg), 200);
        case '/json/state':
          return http.Response(jsonEncode(state), 200);
        case '/json/eff':
          return http.Response('["Solid"]', 200);
      }
      return http.Response('not found', 404);
    }
    if (path == '/settings/2D') {
      final form = Uri.splitQueryString(r.body);
      writes.add(('POST $path', form));
      if (_locked) return http.Response('denied', 401);
      if (ignoreLayout) return http.Response('<html></html>', 200);
      _recreateSegments();
      if (form['SOMP'] == '1') {
        // Like set.cpp: read panels until the first missing P{i}B, at most 18.
        final count = int.parse(form['MPC']!).clamp(1, 18);
        _led['matrix'] = {
          'mpc': count,
          'panels': [
            for (var i = 0; i < count && form.containsKey('P${i}B'); i++)
              {
                'b': form['P${i}B'] == '1', 'r': form['P${i}R'] == '1', 'v': form['P${i}V'] == '1',
                's': form.containsKey('P${i}S'), 'x': int.parse(form['P${i}X']!), 'y': int.parse(form['P${i}Y']!),
                'w': int.parse(form['P${i}W']!), 'h': int.parse(form['P${i}H']!),
              },
          ]
        };
      } else {
        _led.remove('matrix');
      }
      return http.Response('<html></html>', 200);
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    // The app sets the device time as part of setup; recorded apart from `writes`.
    if (path == '/json/state' && body.length == 1 && body.containsKey('time')) {
      clockSets.add((body['time'] as num).toInt());
      return http.Response('{"success":true}', 200);
    }
    if (path == '/json/cfg' && body.length == 1 && (body['if'] as Map?)?.length == 1 &&
        (body['if'] as Map)['ntp'] is Map) {
      if (_locked) return http.Response('denied', 401);
      _merge(cfg, body);
      ntpWrites.add(Map<String, dynamic>.from((body['if'] as Map)['ntp'] as Map));
      return http.Response('{"success":true}', 200);
    }
    writes.add(('POST $path', body));
    if (path == '/json/state') {
      if (body.containsKey('pin')) unlocked = body['pin'] == pin;
      for (final k in ['on', 'bri', 'mainseg']) {
        if (body.containsKey(k)) state[k] = body[k];
      }
      final ps = body['ps'];
      if (ps is int && ps >= 0) {
        state['ps'] = ps;
        seg0['fx'] = presets[ps] ?? 0;
      }
      if (body['pl'] is int) state['pl'] = body['pl'];
      if (body['pd'] is int) state['ps'] = body['pd'];
      final segs = body['seg'];
      if (segs is List && segs.isNotEmpty && segs.first is Map) {
        for (final value in segs.whereType<Map>()) {
          final patch = value.cast<String, dynamic>();
          final current = (state['seg'] as List)
              .whereType<Map>()
              .where((s) => s['id'] == patch['id'])
              .firstOrNull;
          if (current != null) {
            current.addAll(patch);
          } else {
            (state['seg'] as List).add(Map<String, dynamic>.from(patch));
          }
        }
      }
      return http.Response('{"success":true}', 200);
    }
    if (path == '/json/cfg') {
      if (_locked) return http.Response('denied', 401);
      _merge(cfg, body);
      if ((body['hw'] as Map?)?['led'] is Map && ((body['hw'] as Map)['led'] as Map).containsKey('ins')) {
        _recreateSegments();
      }
      return http.Response('{"success":true}', 200);
    }
    return http.Response('not found', 404);
  }

  void _recreateSegments() {
    state['seg'] = <Map<String, dynamic>>[
      {'id': 0, 'fx': 0, 'start': 0, 'stop': 16}
    ];
    state['ps'] = -1;
    state['pl'] = -1;
  }

  static void _merge(Map target, Map patch) {
    patch.forEach((k, v) {
      if (v is Map && target[k] is Map) {
        _merge(target[k] as Map, v);
      } else {
        target[k] = v;
      }
    });
  }
}

class _SetupHttpClient extends MockClient {
  _SetupHttpClient(super.handler, this.onClose);
  final void Function() onClose;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (closed) throw http.ClientException('closed');
    return super.send(request);
  }

  @override
  void close() {
    closed = true;
    onClose();
    super.close();
  }
}
