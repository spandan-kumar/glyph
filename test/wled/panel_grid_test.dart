import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/panel_grid.dart';
import 'package:glyph/wled/panel_setup.dart';

import 'panel_setup_test.dart' show cfg2D, info;

/// Port of WS2812FX::setUpMatrix (WLED 16.0.1 FX_2Dfcn.cpp) for a whole panel
/// list: the LED number at each display cell, row-major.
List<int> wledMapPanels(List<Map> panels) {
  var maxW = 1, maxH = 1;
  for (final p in panels) {
    if (p['x'] + p['w'] > maxW) maxW = p['x'] + p['w'] as int;
    if (p['y'] + p['h'] > maxH) maxH = p['y'] + p['h'] as int;
  }
  final map = List.filled(maxW * maxH, -1);
  var pix = 0;
  for (final p in panels) {
    final vert = p['v'] == true, bs = p['b'] == true, rs = p['r'] == true, ser = p['s'] == true;
    final h = vert ? p['h'] as int : p['w'] as int;
    final v = vert ? p['w'] as int : p['h'] as int;
    for (var j = 0; j < v; j++) {
      for (var i = 0; i < h; i++) {
        final y = (vert ? rs : bs) ? v - j - 1 : j;
        var x = (vert ? bs : rs) ? h - i - 1 : i;
        x = ser && j.isOdd ? h - x - 1 : x;
        final index = ((p['y'] as int) + (vert ? x : y)) * maxW + (p['x'] as int) + (vert ? y : x);
        map[index] = pix++;
      }
    }
  }
  return map;
}

/// Port of gen() from settings_2D.htm: the offsets it gives equal panels.
List<(int, int)> wledGen(
  int pansH,
  int pansV, {
  required bool pv,
  required bool pb,
  required bool pr,
  required bool ps,
  required int pw,
  required int ph,
}) {
  final h = pv ? pansV : pansH, v = pv ? pansH : pansV;
  final out = <(int, int)>[];
  for (var j = 0; j < v; j++) {
    for (var i = 0; i < h; i++) {
      final y = (pv ? pr : pb) ? v - j - 1 : j;
      var x = (pv ? pb : pr) ? h - i - 1 : i;
      x = ps && j.isOdd ? h - x - 1 : x;
      out.add(((pv ? y : x) * pw, (pv ? x : y) * ph));
    }
  }
  return out;
}

const gridSizes = [(2, 1), (1, 3), (2, 2), (3, 2), (4, 2), (2, 4)];
const panelSizes = [(2, 2), (4, 3), (3, 4), (8, 8)];

void main() {
  group('PanelGrid chain', () {
    test('panel offsets match the settings page generator for every chain', () {
      for (final (cols, rows) in gridSizes.where((s) => s.$1 > 1 && s.$2 > 1)) {
        for (final chain in PanelWiring.all) {
          final g = PanelGrid.uniform(cols: cols, rows: rows, panelW: 8, panelH: 4, chain: chain);
          final want = wledGen(
            cols,
            rows,
            pv: chain.vertical,
            pb: chain.bottomStart,
            pr: chain.rightStart,
            ps: chain.zigzag,
            pw: 8,
            ph: 4,
          );
          final got = [for (final p in g.panels()) (p['x'] as int, p['y'] as int)];
          expect(got, want, reason: '$chain ${cols}x$rows');
        }
      }
    });

    test('LED mapping equals setUpMatrix on the panel list, for every chain and wiring', () {
      for (final (cols, rows) in gridSizes) {
        for (final (pw, ph) in panelSizes.take(3)) {
          for (final chain in PanelWiring.all) {
            for (final inner in [PanelWiring.all[0], PanelWiring.all[7], PanelWiring.all[10]]) {
              final g = PanelGrid.uniform(cols: cols, rows: rows, panelW: pw, panelH: ph, chain: chain, wiring: inner);
              final map = wledMapPanels(g.panels());
              expect(map.toSet().length, g.ledCount, reason: 'permutation $g');
              for (var y = 0; y < g.height; y++) {
                for (var x = 0; x < g.width; x++) {
                  expect(g.physicalIndex(x, y), map[y * g.width + x], reason: '$g $inner at $x,$y');
                }
              }
            }
          }
        }
      }
    });

    test('per-panel wiring (turned panels) also equals setUpMatrix', () {
      const base = PanelWiring(corner: StartCorner.topLeft, zigzag: true);
      for (final (cols, rows) in gridSizes) {
        final g = PanelGrid(
          cols: cols,
          rows: rows,
          panelW: 4,
          panelH: 3,
          chain: normalizeChain(const PanelWiring(zigzag: true), cols, rows),
          wiring: [for (var k = 0; k < cols * rows; k++) k.isOdd ? base.turnedUpsideDown : base],
        );
        final map = wledMapPanels(g.panels());
        for (var y = 0; y < g.height; y++) {
          for (var x = 0; x < g.width; x++) {
            expect(g.physicalIndex(x, y), map[y * g.width + x]);
          }
        }
      }
    });

    test('positionOf inverts physicalIndex', () {
      for (final (cols, rows) in gridSizes) {
        for (final chain in PanelWiring.all) {
          final g = PanelGrid.uniform(
            cols: cols,
            rows: rows,
            panelW: 4,
            panelH: 3,
            chain: chain,
            wiring: PanelWiring.all[5],
          );
          for (var i = 0; i < g.ledCount; i++) {
            final (x, y) = g.positionOf(i);
            expect(g.physicalIndex(x, y), i, reason: '$g $i');
          }
        }
      }
    });

    test('a 4x2 snake of 2x2 panels, derived by hand', () {
      final g = PanelGrid.uniform(cols: 4, rows: 2, panelW: 2, panelH: 2, chain: const PanelWiring(zigzag: true));
      // Panels run 0 1 2 3 along the top, then 4 5 6 7 back along the bottom
      // from the right (snake): panel 4 is bottom right.
      expect(
        [for (var k = 0; k < 8; k++) g.cellOf(k)],
        [(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (2, 1), (1, 1), (0, 1)],
      );
      expect(g.panelAt(3, 1), 4);
      expect(g.physicalIndex(0, 0), 0);
      expect(g.physicalIndex(2, 0), 4); // first LED of panel 1
      expect(g.physicalIndex(7, 3), 4 * 4 + 3); // last LED of panel 4
    });

    test('one row or column normalises to the plain chain', () {
      expect(
        normalizeChain(const PanelWiring(corner: StartCorner.bottomLeft, vertical: true, zigzag: true), 3, 1),
        const PanelWiring(),
      );
      expect(
        normalizeChain(const PanelWiring(corner: StartCorner.bottomRight, zigzag: true), 1, 3),
        const PanelWiring(corner: StartCorner.bottomLeft, vertical: true),
      );
      final one = PanelGrid.single(8, 8, const PanelWiring(corner: StartCorner.topRight));
      expect(one.isSingle, isTrue);
      expect(one.panels().single, containsPair('r', true));
    });

    test('turned upside down keeps rows/columns and zig-zag and rotates the display', () {
      for (final w in PanelWiring.all) {
        final t = w.turnedUpsideDown;
        expect(t.vertical, w.vertical);
        expect(t.zigzag, w.zigzag);
        expect(t.turnedUpsideDown, w);
        for (var y = 0; y < 3; y++) {
          for (var x = 0; x < 5; x++) {
            expect(t.physicalIndex(x, y, 5, 3), w.physicalIndex(4 - x, 2 - y, 5, 3), reason: '$w');
          }
        }
      }
    });
  });

  group('limits and estimates', () {
    PanelGrid grid(int c, int r, [int w = 16, int h = 16]) => PanelGrid.uniform(cols: c, rows: r, panelW: w, panelH: h);

    test('WLED limits are explained in plain words', () {
      expect(grid(4, 2).limitProblem, isNull);
      expect(grid(3, 6).limitProblem, isNull); // 18 panels
      expect(grid(4, 5).limitProblem, tooBigWords); // 20 panels
      expect(grid(8, 8, 8, 8).limitProblem, tooBigWords); // 64 panels
      expect(grid(2, 1, 128, 128).limitProblem, tooBigWords); // 32768 LEDs
      expect(grid(2, 1, 130, 8).limitProblem, tooBigWords); // 260 wide
      expect(grid(2, 1, 1, 1).limitProblem, tooBigWords); // 2x1: WLED drops 2D
      expect(grid(1, 1, 16, 16).limitProblem, isNull);
    });

    test('power and frame rate', () {
      expect(fullWhiteAmps(2048), closeTo(122.88, 1e-9));
      expect(formatAmps(122.88), '123');
      expect(formatAmps(6.144), '6.1');
      expect(formatAmps(6), '6');
      expect(framesPerSecond(2048), 16);
      expect(framesPerSecond(1024), 32);
      expect(framesPerSecond(100), 60);
      expect(framesPerSecond(0), 60);
    });

    test('sizes read in plain words', () {
      expect(grid(3, 2).describeSize(), '3 × 2 panels of 16×16 (48×32)');
      expect(grid(1, 1).describeSize(), '16×16');
      expect(
        PanelGrid.uniform(
          cols: 4,
          rows: 2,
          panelW: 8,
          panelH: 8,
          chain: const PanelWiring(zigzag: true),
        ).describeChain(),
        'Starts top left, runs across, snakes',
      );
    });
  });

  group('reading a device', () {
    Map<String, dynamic> panel(
      int x,
      int y, {
      int w = 8,
      int h = 8,
      bool b = false,
      bool r = false,
      bool v = false,
      bool s = false,
    }) => {'b': b, 'r': r, 'v': v, 's': s, 'x': x, 'y': y, 'w': w, 'h': h};

    test('a regular grid is recognised, in any chain order it can describe', () {
      for (final chain in PanelWiring.all) {
        for (final (cols, rows) in gridSizes) {
          final g = PanelGrid.uniform(
            cols: cols,
            rows: rows,
            panelW: 8,
            panelH: 8,
            chain: chain,
            wiring: const PanelWiring(zigzag: true),
          );
          final back = PanelGrid.fromPanels([for (final p in g.panels()) Map<String, dynamic>.from(p)]);
          expect(back, g, reason: '$g');
        }
      }
    });

    test('panels with different wiring are kept', () {
      final g = PanelGrid(
        cols: 2,
        rows: 1,
        panelW: 8,
        panelH: 8,
        chain: const PanelWiring(),
        wiring: [const PanelWiring(), const PanelWiring().turnedUpsideDown],
      );
      final back = PanelGrid.fromPanels([for (final p in g.panels()) Map<String, dynamic>.from(p)])!;
      expect(back.sameWiring, isFalse);
      expect(back, g);
    });

    test('irregular layouts are not grids', () {
      expect(PanelGrid.fromPanels(const []), isNull);
      // A gap.
      expect(PanelGrid.fromPanels([panel(0, 0), panel(16, 0)]), isNull);
      // Mixed sizes.
      expect(PanelGrid.fromPanels([panel(0, 0), panel(8, 0, w: 16)]), isNull);
      // Overlap.
      expect(PanelGrid.fromPanels([panel(0, 0), panel(0, 0)]), isNull);
      // Not on the panel grid.
      expect(PanelGrid.fromPanels([panel(0, 0), panel(4, 0)]), isNull);
      // A custom order: top left, bottom right, top right, bottom left.
      expect(PanelGrid.fromPanels([panel(0, 0), panel(8, 8), panel(8, 0), panel(0, 8)]), isNull);
      // An offset single panel.
      expect(PanelGrid.fromPanels([panel(8, 0)]), isNull);
    });

    test('DeviceSetupState reads a grid and supports it; odd layouts keep the old reason', () {
      final g = PanelGrid.uniform(cols: 2, rows: 2, panelW: 8, panelH: 8, chain: const PanelWiring(zigzag: true));
      final cfg = cfg2D();
      (((cfg['hw'] as Map)['led'] as Map)['matrix'] as Map)
        ..['mpc'] = 4
        ..['panels'] = g.panels();
      final s = DeviceSetupState.fromJson(cfg: cfg, info: info(count: 256, w: 16, h: 16));
      expect(s.grid, g);
      expect(s.panelCount, 4);
      expect(s.support, SetupSupport.supported);
      expect(s.isConfigured(DisplaySetup.grid(g)), isTrue);
      expect(s.isConfigured(DisplaySetup.grid(PanelGrid.uniform(cols: 2, rows: 2, panelW: 8, panelH: 8))), isFalse);

      final odd = cfg2D(panels: 3); // three panels on top of each other
      expect(DeviceSetupState.fromJson(cfg: odd, info: info()).support, SetupSupport.multiplePanels);
    });
  });

  group('the form', () {
    test('writes every panel with offsets, sizes and flags', () {
      final g = PanelGrid(
        cols: 2,
        rows: 2,
        panelW: 16,
        panelH: 8,
        chain: const PanelWiring(zigzag: true),
        wiring: [
          const PanelWiring(corner: StartCorner.bottomLeft, zigzag: true),
          const PanelWiring(corner: StartCorner.topRight, zigzag: true),
          const PanelWiring(corner: StartCorner.bottomLeft, zigzag: true),
          const PanelWiring(corner: StartCorner.topRight, zigzag: true),
        ],
      );
      final form = panelForm(DisplaySetup.grid(g));
      expect(form['SOMP'], '1');
      expect(form['MPC'], '4');
      // Chain: (0,0) (1,0) (1,1) (0,1).
      expect([for (var i = 0; i < 4; i++) '${form['P${i}X']},${form['P${i}Y']}'], ['0,0', '16,0', '16,8', '0,8']);
      expect(form['P0B'], '1');
      expect(form['P1R'], '1');
      expect(form['P2W'], '16');
      expect(form['P3H'], '8');
      expect(form.keys.where((k) => k.endsWith('S')), ['P0S', 'P1S', 'P2S', 'P3S']);
      expect(form.length, 2 + 4 * 8 - 0);
    });

    test('a single panel is a 1x1 grid with the same form as before', () {
      final form = panelForm(const DisplaySetup(16, 8, PanelWiring(corner: StartCorner.bottomRight)));
      expect(form, {
        'SOMP': '1',
        'MPC': '1',
        'P0B': '1',
        'P0R': '1',
        'P0V': '0',
        'P0X': '0',
        'P0Y': '0',
        'P0W': '16',
        'P0H': '8',
      });
    });
  });

  group('snapshots', () {
    test('keep all panels through JSON', () {
      final g = PanelGrid.uniform(cols: 3, rows: 2, panelW: 16, panelH: 16, chain: const PanelWiring(zigzag: true));
      final cfg = cfg2D();
      (((cfg['hw'] as Map)['led'] as Map)['matrix'] as Map)
        ..['mpc'] = 6
        ..['panels'] = g.panels();
      final state = DeviceSetupState.fromJson(cfg: cfg, info: info(count: 1536, w: 48, h: 32));
      final snap = SetupSnapshot.of(state, host: '10.0.0.2');
      final back = SetupSnapshot.decode(snap.encode());
      expect(back.grid, g);
      expect(back.display, DisplaySetup.grid(g));
      expect(back.display!.ledCount, 1536);
    });

    test('a single panel stays as before and old snapshots still read', () {
      final state = DeviceSetupState.fromJson(cfg: cfg2D(), info: info());
      final snap = SetupSnapshot.of(state, host: 'h');
      expect(snap.toJson().containsKey('grid'), isFalse);
      final back = SetupSnapshot.decode(snap.encode());
      expect(back.display, const DisplaySetup(16, 8, PanelWiring()));
    });
  });
}
