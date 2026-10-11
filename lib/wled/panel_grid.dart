import 'panel_setup.dart';

/// A display made of equal panels in a regular grid, chained on one output.
/// Verified against WLED 16.0.1: `setUpMatrix` (FX_2Dfcn.cpp) numbers LEDs
/// panel by panel in list order, and the settings page's `gen()`
/// (settings_2D.htm) places equal panels with the same corner / vertical /
/// zig-zag rules one level up. No I/O here.

/// WLED builds at most this many panels (`WLED_MAX_PANELS`, const.h); the
/// settings page says 64 but set.cpp and cfg.cpp constrain to this.
const maxPanels = 18;

/// `MAX_LEDS` for an ESP32; the display must also fit 255 in each direction.
const maxDisplayLeds = 16384;
const maxDisplaySide = 255;

/// Longest the panels may be chained before the picture is held up by the
/// wire: more than this many LEDs on one output update more slowly.
const slowWireLeds = 1024;

/// Plain-words reason a layout can't be driven.
const tooBigWords = 'That\'s more lights than this device can drive.';

/// Milliamps one LED draws at full white.
const ledFullWhiteMa = 60;

/// What a display could draw at full white, in amps.
double fullWhiteAmps(int leds) => leds * ledFullWhiteMa / 1000;

/// "13" or "6.1": whole amps from 10 up, else one decimal without a ".0".
String formatAmps(double amps) {
  if (amps >= 10) return '${amps.round()}';
  final s = amps.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Frames a second a single WS281x wire can carry for [leds] LEDs (800 kHz,
/// 24 bits each), at most 60.
int framesPerSecond(int leds) => leds <= 0 ? 60 : (800000 / 24 / leds).floor().clamp(1, 60);

class PanelGrid {
  PanelGrid({
    required this.cols,
    required this.rows,
    required this.panelW,
    required this.panelH,
    this.chain = const PanelWiring(),
    required List<PanelWiring> wiring,
    List<(int, int)>? positions,
  }) : wiring = List.unmodifiable(wiring),
       positions = positions == null ? null : List.unmodifiable(positions),
       assert(wiring.length == cols * rows) {
    if (positions != null && !_validPositions(positions, cols, rows)) {
      throw ArgumentError.value(positions, 'positions', 'Must be a grid permutation');
    }
  }

  /// Every panel wired the same way.
  factory PanelGrid.uniform({
    required int cols,
    required int rows,
    required int panelW,
    required int panelH,
    PanelWiring chain = const PanelWiring(),
    PanelWiring wiring = const PanelWiring(),
  }) => PanelGrid(
    cols: cols,
    rows: rows,
    panelW: panelW,
    panelH: panelH,
    chain: normalizeChain(chain, cols, rows),
    wiring: List.filled(cols * rows, wiring),
  );

  /// One panel is a 1×1 grid.
  factory PanelGrid.single(int w, int h, PanelWiring wiring) =>
      PanelGrid.uniform(cols: 1, rows: 1, panelW: w, panelH: h, wiring: wiring);

  final int cols, rows, panelW, panelH;

  /// How the panels are chained, at panel level: the corner of the grid the
  /// first panel sits in, whether the chain runs down the columns, and
  /// whether it snakes back on every second run.
  final PanelWiring chain;

  /// Explicit grid cells in chain order, when the chain has a custom route.
  final List<(int, int)>? positions;

  /// LED wiring inside each panel, in chain order.
  final List<PanelWiring> wiring;

  int get panelCount => cols * rows;
  int get panelLeds => panelW * panelH;
  int get width => cols * panelW;
  int get height => rows * panelH;
  int get ledCount => panelCount * panelLeds;
  bool get isSingle => panelCount == 1;

  /// Whether every panel has the first one's wiring.
  bool get sameWiring => wiring.every((w) => w == wiring.first);

  /// Panels in the first run of the chain, and the number of runs.
  int get firstRunPanels => chain.runLength(cols, rows);
  int get runCount => chain.vertical ? cols : rows;

  /// Why this layout can't be driven, in plain words; null when it can.
  String? get limitProblem {
    if (panelCount > maxPanels || ledCount > maxDisplayLeds || width > maxDisplaySide || height > maxDisplaySide) {
      return tooBigWords;
    }
    // WLED drops 2D for a display one LED wide or tall (maxWidth <= 1).
    if (panelCount > 1 && (width < 2 || height < 2)) return tooBigWords;
    return null;
  }

  /// Grid cell (column, row) of the [k]-th panel in the chain.
  (int, int) cellOf(int k) => positions?[k] ?? chain.positionOf(k, cols, rows);

  /// Chain position of the panel at grid cell ([cx], [cy]).
  int panelAt(int cx, int cy) => positions?.indexOf((cx, cy)) ?? chain.physicalIndex(cx, cy, cols, rows);

  /// LED index at display column [x], row [y] (origin top-left).
  int physicalIndex(int x, int y) {
    final k = panelAt(x ~/ panelW, y ~/ panelH);
    return k * panelLeds + wiring[k].physicalIndex(x % panelW, y % panelH, panelW, panelH);
  }

  /// Display (x, y) of LED [index].
  (int, int) positionOf(int index) {
    final k = index ~/ panelLeds;
    final (cx, cy) = cellOf(k);
    final (lx, ly) = wiring[k].positionOf(index % panelLeds, panelW, panelH);
    return (cx * panelW + lx, cy * panelH + ly);
  }

  /// WLED panel entries (`hw.led.matrix.panels`) in chain order.
  List<Map<String, Object>> panels() => [
    for (var k = 0; k < panelCount; k++)
      () {
        final (cx, cy) = cellOf(k);
        final w = wiring[k];
        return <String, Object>{
          'b': w.bottomStart,
          'r': w.rightStart,
          'v': w.vertical,
          's': w.zigzag,
          'x': cx * panelW,
          'y': cy * panelH,
          'w': panelW,
          'h': panelH,
        };
      }(),
  ];

  /// "3 × 2 panels of 16×16 (48×32)".
  String describeSize() => isSingle ? '$panelW×$panelH' : '$cols × $rows panels of $panelW×$panelH ($width×$height)';

  /// "Starts top left, runs across, snakes".
  String describeChain() => positions == null ? describeChainOf(chain, cols, rows) : 'Custom panel order';

  Map<String, dynamic> toJson() => {
    'cols': cols,
    'rows': rows,
    'panelW': panelW,
    'panelH': panelH,
    'chain': chain.toJson(),
    if (positions != null)
      'positions': [
        for (final p in positions!) [p.$1, p.$2],
      ],
    'wiring': [for (final w in wiring) w.toJson()],
  };

  static PanelGrid? tryFromJson(Object? j) {
    if (j is! Map) return null;
    int? n(Object? v) => v is num ? v.toInt() : null;
    final cols = n(j['cols']), rows = n(j['rows']), pw = n(j['panelW']), ph = n(j['panelH']);
    final list = j['wiring'];
    if (cols == null || rows == null || pw == null || ph == null || cols < 1 || rows < 1 || list is! List) {
      return null;
    }
    if (list.length != cols * rows) return null;
    List<(int, int)>? positions;
    if (j.containsKey('positions')) {
      final cells = j['positions'];
      if (cells is! List) return null;
      positions = [];
      for (final cell in cells) {
        if (cell is! List || cell.length != 2 || cell[0] is! int || cell[1] is! int) return null;
        positions.add((cell[0] as int, cell[1] as int));
      }
      if (!_validPositions(positions, cols, rows)) return null;
    }
    return PanelGrid(
      cols: cols,
      rows: rows,
      panelW: pw,
      panelH: ph,
      positions: positions,
      chain: j['chain'] is Map ? PanelWiring.fromJson(j['chain'] as Map) : const PanelWiring(),
      wiring: [for (final w in list) w is Map ? PanelWiring.fromJson(w) : const PanelWiring()],
    );
  }

  /// Reads WLED's panel list (`hw.led.matrix.panels`) as a grid, or null
  /// when it isn't equal panels tiling a rectangle (mixed sizes, gaps or overlaps).
  static PanelGrid? fromPanels(List<Map<String, dynamic>> panels) {
    if (panels.isEmpty) return null;
    int? n(Object? v) => v is num ? v.toInt() : null;
    bool flag(Object? v) => v == true || (v is num && v != 0);
    final pw = n(panels.first['w']), ph = n(panels.first['h']);
    if (pw == null || ph == null || pw < 1 || ph < 1) return null;
    final cells = <(int, int)>[];
    final seen = <(int, int)>{};
    var cols = 0, rows = 0;
    for (final p in panels) {
      final x = n(p['x']) ?? 0, y = n(p['y']) ?? 0;
      if (n(p['w']) != pw || n(p['h']) != ph || x < 0 || y < 0 || x % pw != 0 || y % ph != 0) return null;
      final cell = (x ~/ pw, y ~/ ph);
      if (!seen.add(cell)) return null;
      cells.add(cell);
      if (cell.$1 + 1 > cols) cols = cell.$1 + 1;
      if (cell.$2 + 1 > rows) rows = cell.$2 + 1;
    }
    if (cells.length != cols * rows) return null;
    PanelWiring? found;
    for (final candidate in _chains(cols, rows)) {
      var ok = true;
      for (var k = 0; k < cells.length && ok; k++) {
        ok = candidate.positionOf(k, cols, rows) == cells[k];
      }
      if (ok) {
        found = candidate;
        break;
      }
    }
    return PanelGrid(
      cols: cols,
      rows: rows,
      panelW: pw,
      panelH: ph,
      chain: found ?? const PanelWiring(),
      positions: found == null ? cells : null,
      wiring: [
        for (final p in panels)
          PanelWiring.fromFlags(
            bottomStart: flag(p['b']),
            rightStart: flag(p['r']),
            vertical: flag(p['v']),
            serpentine: flag(p['s']),
          ),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PanelGrid &&
      other.cols == cols &&
      other.rows == rows &&
      other.panelW == panelW &&
      other.panelH == panelH &&
      _sameList(
        [for (var k = 0; k < panelCount; k++) other.cellOf(k)],
        [for (var k = 0; k < panelCount; k++) cellOf(k)],
      ) &&
      _sameList(other.wiring, wiring);

  @override
  int get hashCode => Object.hash(
    cols,
    rows,
    panelW,
    panelH,
    Object.hashAll([for (var k = 0; k < panelCount; k++) cellOf(k)]),
    Object.hashAll(wiring),
  );

  @override
  String toString() => 'PanelGrid($cols×$rows of $panelW×$panelH, ${describeChain()})';
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A chain on a [cols]×[rows] grid in its simplest form: with one row the
/// chain can only run across and with one column only down, the top and
/// bottom (or left and right) start are the same, and there is no second
/// run to snake into. Equal chains then compare equal.
PanelWiring normalizeChain(PanelWiring c, int cols, int rows) {
  if (cols == 1 && rows == 1) return const PanelWiring();
  if (rows == 1) return PanelWiring(corner: StartCorner.of(bottom: false, right: c.corner.isRight));
  if (cols == 1) {
    return PanelWiring(corner: StartCorner.of(bottom: c.corner.isBottom, right: false), vertical: true);
  }
  return c;
}

/// Every distinct chain for a [cols]×[rows] grid.
List<PanelWiring> _chains(int cols, int rows) =>
    {for (final w in PanelWiring.all) normalizeChain(w, cols, rows)}.toList();

/// "Starts top left, runs across, snakes" (or "goes straight on").
String describeChainOf(PanelWiring chain, int cols, int rows) {
  final runs = chain.vertical ? cols : rows;
  final tail = runs < 2 ? '' : (chain.zigzag ? ', snakes' : ', same side each time');
  return 'Starts ${chain.corner.label}, runs ${chain.vertical ? 'down' : 'across'}$tail';
}

extension PanelWiringTurn on PanelWiring {
  /// The same wiring for a panel turned upside down: the start corner is
  /// opposite; rows and columns and zig-zag stay as they were.
  PanelWiring get turnedUpsideDown => PanelWiring(
    corner: StartCorner.of(bottom: !corner.isBottom, right: !corner.isRight),
    vertical: vertical,
    zigzag: zigzag,
  );
}

bool _validPositions(List<(int, int)> cells, int cols, int rows) =>
    cells.length == cols * rows &&
    cells.toSet().length == cells.length &&
    cells.every((c) => c.$1 >= 0 && c.$1 < cols && c.$2 >= 0 && c.$2 < rows);
