import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/layout.dart';
import 'package:glyph/wled/panel_setup.dart';

/// Port of WS2812FX::setUpMatrix (WLED 16.0.1 FX_2Dfcn.cpp) for one panel at
/// offset 0: LED number at each logical cell, row-major.
List<int> wledMap(int w, int h, PanelWiring wiring) {
  final b = wiring.bottomStart, r = wiring.rightStart;
  final v = wiring.vertical, s = wiring.zigzag;
  final map = List.filled(w * h, -1);
  final hh = v ? h : w, vv = v ? w : h;
  var pix = 0;
  for (var j = 0; j < vv; j++) {
    for (var i = 0; i < hh; i++) {
      final y = (v ? r : b) ? vv - j - 1 : j;
      var x = (v ? b : r) ? hh - i - 1 : i;
      x = s && j.isOdd ? hh - x - 1 : x;
      final index = (v ? x : y) * w + (v ? y : x);
      map[index] = pix++;
    }
  }
  return map;
}

List<List<int>> table(PanelWiring wiring, int w, int h) => [
      for (var y = 0; y < h; y++)
        [for (var x = 0; x < w; x++) wiring.physicalIndex(x, y, w, h)],
    ];

const sizes = [(4, 4), (8, 8), (4, 3), (3, 4), (8, 2), (2, 8), (5, 7), (16, 8)];

Map<String, dynamic> cfg2D({
  Map<String, dynamic> panel = const {'b': false, 'r': false, 'v': false, 's': false, 'x': 0, 'y': 0, 'w': 16, 'h': 8},
  int panels = 1,
  List<Map<String, dynamic>>? ins,
  bool rlm = true,
  int offset = 0,
  int maxpwr = 0,
}) =>
    {
      'hw': {
        'led': {
          'total': 128,
          'maxpwr': maxpwr,
          'matrix': {
            'mpc': panels,
            'panels': [for (var i = 0; i < panels; i++) panel],
          },
          'ins': ins ?? [out()],
        },
      },
      'if': {
        'live': {'rlm': rlm, 'offset': offset},
      },
    };

Map<String, dynamic> out({int type = 22, int len = 128}) => {
      'start': 0, 'len': len, 'pin': [16], 'order': 1, 'rev': false, 'skip': 0,
      'type': type, 'ref': false, 'rgbwm': 255, 'freq': 0, 'maxpwr': 0, 'ledma': 55, 'drv': 0, 'text': '',
    };

Map<String, dynamic> info({int count = 128, int? w = 16, int? h = 8, List maps = const [{'id': 0}]}) => {
      'ver': '16.0.1', 'name': 'Desk', 'mac': '48e729a39308',
      'leds': {'count': count, if (w != null) 'matrix': {'w': w, 'h': h}},
      'maps': maps,
    };

void main() {
  group('PanelWiring', () {
    test('mapping matches WLED setUpMatrix for all 16 wirings and many sizes', () {
      for (final wiring in PanelWiring.all) {
        for (final (w, h) in sizes) {
          final map = wledMap(w, h, wiring);
          expect(map.toSet().length, w * h, reason: '$wiring ${w}x$h is a permutation');
          for (var y = 0; y < h; y++) {
            for (var x = 0; x < w; x++) {
              expect(wiring.physicalIndex(x, y, w, h), map[y * w + x],
                  reason: '$wiring ${w}x$h at $x,$y');
            }
          }
        }
      }
    });

    test('4x3 tables derived by hand from the C++ loop', () {
      expect(table(const PanelWiring(), 4, 3), [
        [0, 1, 2, 3],
        [4, 5, 6, 7],
        [8, 9, 10, 11],
      ]);
      expect(table(const PanelWiring(corner: StartCorner.bottomLeft), 4, 3), [
        [8, 9, 10, 11],
        [4, 5, 6, 7],
        [0, 1, 2, 3],
      ]);
      expect(table(const PanelWiring(corner: StartCorner.topRight, zigzag: true), 4, 3), [
        [3, 2, 1, 0],
        [4, 5, 6, 7],
        [11, 10, 9, 8],
      ]);
      expect(
          table(const PanelWiring(corner: StartCorner.bottomRight, vertical: true, zigzag: true), 4, 3),
          [
            [9, 8, 3, 2],
            [10, 7, 4, 1],
            [11, 6, 5, 0],
          ]);
      expect(table(const PanelWiring(vertical: true), 4, 3), [
        [0, 3, 6, 9],
        [1, 4, 7, 10],
        [2, 5, 8, 11],
      ]);
    });

    test('positionOf inverts physicalIndex', () {
      for (final wiring in PanelWiring.all) {
        for (final (w, h) in sizes) {
          for (var i = 0; i < w * h; i++) {
            final (x, y) = wiring.positionOf(i, w, h);
            expect(wiring.physicalIndex(x, y, w, h), i, reason: '$wiring ${w}x$h LED $i');
          }
        }
      }
    });

    test('fromAnswers recovers every wiring from simulated test answers', () {
      for (final wiring in PanelWiring.all) {
        for (final (w, h) in sizes) {
          final (x0, y0) = wiring.positionOf(0, w, h);
          final corner = StartCorner.of(bottom: y0 == h - 1, right: x0 == w - 1);
          final (x1, y1) = wiring.positionOf(1, w, h);
          final alongWidth = y1 == y0 && x1 != x0;
          final run = alongWidth ? w : h;
          final (x2, y2) = wiring.positionOf(run, w, h);
          final farEnd = alongWidth ? x2 != x0 : y2 != y0;
          final guessed = PanelWiring.fromAnswers(
            corner: corner,
            firstRunAlongWidth: alongWidth,
            secondRunStartsAtFarEnd: farEnd,
          );
          expect(guessed, wiring, reason: '$wiring ${w}x$h');
          expect(guessed.runLength(w, h), run);
        }
      }
    });

    test('describe, equality and json', () {
      const w = PanelWiring(corner: StartCorner.topLeft, zigzag: true);
      expect(w.describe(), 'Starts top left, rows, zig-zag');
      expect(const PanelWiring(corner: StartCorner.bottomRight, vertical: true).describe(),
          'Starts bottom right, columns, straight');
      expect(PanelWiring.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map), w);
      expect(PanelWiring.all.toSet().length, 16);
    });
  });

  group('forms and limits', () {
    test('serpentine is absent when off and present when on', () {
      final off = panelForm(const DisplaySetup(16, 8, PanelWiring(corner: StartCorner.bottomRight)));
      expect(off, {
        'SOMP': '1', 'MPC': '1', 'P0B': '1', 'P0R': '1', 'P0V': '0',
        'P0X': '0', 'P0Y': '0', 'P0W': '16', 'P0H': '8',
      });
      expect(off.containsKey('P0S'), isFalse);
      final on = panelForm(const DisplaySetup(8, 32, PanelWiring(vertical: true, zigzag: true)));
      expect(on['P0S'], 'on');
      expect(on['P0V'], '1');
      expect(on['P0W'], '8');
      expect(on['P0H'], '32');
      expect(stripForm(), {'SOMP': '0'});
    });

    test('recommendedLimitMa', () {
      expect(recommendedLimitMa(1, null), 850);
      expect(recommendedLimitMa(2, null), 1700);
      expect(recommendedLimitMa(5, 0), 4250);
      expect(recommendedLimitMa(3, null), 2550);
      expect(recommendedLimitMa(10, null), 8500);
      expect(recommendedLimitMa(2, 1000), 1000, reason: 'a stricter limit stays');
      expect(recommendedLimitMa(2, 5000), 1700);
      expect(recommendedLimitMa(0.01, null), 50, reason: 'never 0, which means unlimited');
    });
  });

  group('DeviceSetupState', () {
    test('parses a 2D device', () {
      final s = DeviceSetupState.fromJson(
        cfg: cfg2D(panel: {'b': true, 'r': 0, 'v': 1, 's': true, 'x': 0, 'y': 0, 'w': 16, 'h': 8}, maxpwr: 1500),
        info: info(),
      );
      expect(s.isMatrix, isTrue);
      expect((s.width, s.height), (16, 8));
      expect(s.wiring, const PanelWiring(corner: StartCorner.bottomLeft, vertical: true, zigzag: true));
      expect(s.panelCount, 1);
      expect(s.ledCount, 128);
      expect(s.outputs.single['len'], 128);
      expect(s.realtimeMaps, isTrue);
      expect(s.currentLimitMa, 1500);
      expect((s.mac, s.name, s.version), ('48e729a39308', 'Desk', '16.0.1'));
      expect(s.pinLocked, isFalse);
      expect(s.support, SetupSupport.supported);
    });

    test('parses a plain strip', () {
      final cfg = cfg2D()..['hw']['led'].remove('matrix');
      final s = DeviceSetupState.fromJson(cfg: cfg, info: info(w: null, h: null));
      expect(s.isMatrix, isFalse);
      expect(s.width, isNull);
      expect(s.wiring, isNull);
      expect(s.support, SetupSupport.supported);
      expect(s.isConfigured(const DisplaySetup(16, 8, PanelWiring())), isFalse);
    });

    test('reasons a device is unsupported', () {
      SetupSupport of(Map<String, dynamic> cfg, [Map<String, dynamic>? i]) =>
          DeviceSetupState.fromJson(cfg: cfg, info: i ?? info()).support;
      expect(of(cfg2D(panels: 2)), SetupSupport.multiplePanels);
      expect(of(cfg2D(ins: [out(), out()])), SetupSupport.multipleOutputs);
      expect(of(cfg2D(ins: [out(type: 80)])), SetupSupport.unsupportedOutput, reason: 'network');
      expect(of(cfg2D(ins: [out(type: 43)])), SetupSupport.unsupportedOutput, reason: 'PWM');
      expect(of(cfg2D(ins: [out(type: 65)])), SetupSupport.unsupportedOutput, reason: 'HUB75');
      expect(of(cfg2D(ins: [out(type: 51)])), SetupSupport.supported, reason: 'APA102');
      expect(of(cfg2D(), info(maps: [{'id': 0}, {'id': 2, 'n': 'x'}])), SetupSupport.customMap);
      expect(of(cfg2D(offset: 5)), SetupSupport.realtimeOffset);
      expect(of({'if': {}}), SetupSupport.noTwoD);
    });

    test('a locked device defers the support decision', () {
      final s = DeviceSetupState.lockedFromInfo(info());
      expect(s.pinLocked, isTrue);
      expect(s.mac, '48e729a39308');
      expect(s.ledCount, 128);
      expect(s.support, SetupSupport.supported);
    });

    test('isConfigured needs size, wiring and the realtime map', () {
      const want = DisplaySetup(16, 8, PanelWiring(zigzag: true));
      DeviceSetupState state({bool rlm = true, bool s = true, int w = 16}) => DeviceSetupState.fromJson(
            cfg: cfg2D(panel: {'b': false, 'r': false, 'v': false, 's': s, 'w': w, 'h': 8}, rlm: rlm),
            info: info(w: w),
          );
      expect(state().isConfigured(want), isTrue);
      expect(state(rlm: false).isConfigured(want), isFalse);
      expect(state(s: false).isConfigured(want), isFalse);
      expect(state(w: 8).isConfigured(want), isFalse);
    });
  });

  test('SetupSnapshot round-trips through json', () {
    final snap = SetupSnapshot(
      mac: 'aabbccddeeff',
      host: '192.168.1.5',
      isMatrix: true,
      width: 16,
      height: 8,
      wiring: const PanelWiring(corner: StartCorner.bottomRight, zigzag: true),
      ledCount: 128,
      outputEntry: out(),
      realtimeMaps: false,
      currentLimitMa: 900,
      appLayout: const MatrixLayout(rotation: 1, flipX: true),
      takenAt: DateTime.utc(2026, 10, 10, 9),
    );
    final back = SetupSnapshot.decode(snap.encode());
    expect(back.toJson(), snap.toJson());
    expect(back.wiring, snap.wiring);
    expect(back.appLayout, snap.appLayout);
    expect(back.display, const DisplaySetup(16, 8, PanelWiring(corner: StartCorner.bottomRight, zigzag: true)));
    expect(back.outputEntry['ledma'], 55);
    expect(back.takenAt, snap.takenAt);

    final strip = SetupSnapshot(
        mac: 'a', host: 'h', isMatrix: false, ledCount: 60, outputEntry: const {}, realtimeMaps: true, takenAt: DateTime.utc(2026));
    final b2 = SetupSnapshot.decode(strip.encode());
    expect(b2.display, isNull);
    expect(b2.currentLimitMa, isNull);
  });
}
