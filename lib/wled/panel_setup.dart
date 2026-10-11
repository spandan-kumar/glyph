import 'dart:convert';

import 'layout.dart';
import 'panel_grid.dart';

/// Pure logic for the device setup wizard: how a single panel is wired, how
/// WLED describes that in its config, and what the app needs to remember to
/// undo a setup. Verified against WLED 16.0.1 (FX_2Dfcn.cpp setUpMatrix,
/// cfg.cpp, set.cpp); no I/O here, see the setup methods on `WledClient`.

/// The corner of the display where LED 0 sits, as seen from the front.
enum StartCorner {
  topLeft('top left'),
  topRight('top right'),
  bottomLeft('bottom left'),
  bottomRight('bottom right');

  const StartCorner(this.label);
  final String label;

  bool get isBottom => this == bottomLeft || this == bottomRight;
  bool get isRight => this == topRight || this == bottomRight;

  static StartCorner of({required bool bottom, required bool right}) =>
      switch ((bottom, right)) {
        (false, false) => topLeft,
        (false, true) => topRight,
        (true, false) => bottomLeft,
        (true, true) => bottomRight,
      };
}

/// How the LEDs of one panel run: where LED 0 is, whether the first run goes
/// along the rows or down the columns, and whether every second run turns
/// back (zig-zag) or starts again on the same side (straight).
///
/// This is WLED's single-panel mapping at offset 0: `b` bottomStart, `r`
/// rightStart, `v` vertical, `s` serpentine.
class PanelWiring {
  const PanelWiring({
    this.corner = StartCorner.topLeft,
    this.vertical = false,
    this.zigzag = false,
  });

  final StartCorner corner;

  /// LEDs run down the columns (along the height) instead of along the rows.
  final bool vertical;

  /// Every second run goes back the other way.
  final bool zigzag;

  /// All 16 wirings.
  static final all = [
    for (final c in StartCorner.values)
      for (final v in const [false, true])
        for (final z in const [false, true])
          PanelWiring(corner: c, vertical: v, zigzag: z),
  ];

  bool get bottomStart => corner.isBottom;
  bool get rightStart => corner.isRight;

  /// WLED panel flags (`b`, `r`, `v`, `s`) to wiring.
  factory PanelWiring.fromFlags({
    required bool bottomStart,
    required bool rightStart,
    required bool vertical,
    required bool serpentine,
  }) =>
      PanelWiring(
        corner: StartCorner.of(bottom: bottomStart, right: rightStart),
        vertical: vertical,
        zigzag: serpentine,
      );

  /// Works the wiring out from three observations of a test:
  /// 1. [corner]: where LED 0 lit up.
  /// 2. [firstRunAlongWidth]: the chase from LED 0 moved along the width
  ///    (rows) rather than along the height (columns).
  /// 3. [secondRunStartsAtFarEnd]: the LED after the first full run lit at
  ///    the far end of that run (it turned back: zig-zag) rather than on the
  ///    same side as LED 0 (straight).
  factory PanelWiring.fromAnswers({
    required StartCorner corner,
    required bool firstRunAlongWidth,
    required bool secondRunStartsAtFarEnd,
  }) =>
      PanelWiring(
        corner: corner,
        vertical: !firstRunAlongWidth,
        zigzag: secondRunStartsAtFarEnd,
      );

  /// LEDs in one run on a [w]×[h] display.
  int runLength(int w, int h) => vertical ? h : w;

  /// LED index at logical column [x], row [y] (origin top-left).
  int physicalIndex(int x, int y, int w, int h) {
    if (!vertical) {
      final run = bottomStart ? h - 1 - y : y;
      final along = zigzag && run.isOdd ? w - 1 - x : x;
      return run * w + (rightStart ? w - 1 - along : along);
    }
    final run = rightStart ? w - 1 - x : x;
    final along = zigzag && run.isOdd ? h - 1 - y : y;
    return run * h + (bottomStart ? h - 1 - along : along);
  }

  /// Logical (x, y) of LED [index] on a [w]×[h] display.
  (int, int) positionOf(int index, int w, int h) {
    if (!vertical) {
      final run = index ~/ w, i = index % w;
      final flipped = rightStart ? w - 1 - i : i;
      final x = zigzag && run.isOdd ? w - 1 - flipped : flipped;
      return (x, bottomStart ? h - 1 - run : run);
    }
    final run = index ~/ h, i = index % h;
    final flipped = bottomStart ? h - 1 - i : i;
    final y = zigzag && run.isOdd ? h - 1 - flipped : flipped;
    return (rightStart ? w - 1 - run : run, y);
  }

  /// Plain words, e.g. "Starts top left, rows, zig-zag".
  String describe() =>
      'Starts ${corner.label}, ${vertical ? 'columns' : 'rows'}, '
      '${zigzag ? 'zig-zag' : 'straight'}';

  Map<String, dynamic> toJson() =>
      {'corner': corner.name, 'vertical': vertical, 'zigzag': zigzag};

  factory PanelWiring.fromJson(Map json) => PanelWiring(
        corner: StartCorner.values.asNameMap()['${json['corner']}'] ??
            StartCorner.topLeft,
        vertical: json['vertical'] == true,
        zigzag: json['zigzag'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is PanelWiring &&
      other.corner == corner &&
      other.vertical == vertical &&
      other.zigzag == zigzag;

  @override
  int get hashCode => Object.hash(corner, vertical, zigzag);

  @override
  String toString() => 'PanelWiring(${describe()})';
}

/// A display Glyph is asked to set up: one panel, [width]×[height], wired as
/// [wiring], or a grid of panels ([DisplaySetup.grid]). A single panel is a
/// 1×1 grid; [width], [height] and [ledCount] always describe the whole
/// display and [wiring] the first panel.
class DisplaySetup {
  const DisplaySetup(this.width, this.height, this.wiring) : _grid = null;

  DisplaySetup.grid(PanelGrid g)
    : width = g.width,
      height = g.height,
      wiring = g.wiring.first,
      _grid = g;

  final int width;
  final int height;
  final PanelWiring wiring;
  final PanelGrid? _grid;

  /// The panels, even for a single one.
  PanelGrid get grid => _grid ?? PanelGrid.single(width, height, wiring);

  int get ledCount => width * height;

  @override
  bool operator ==(Object other) => other is DisplaySetup && other.grid == grid;

  @override
  int get hashCode => grid.hashCode;

  @override
  String toString() => _grid != null && !_grid.isSingle
      ? 'DisplaySetup($_grid)'
      : 'DisplaySetup(${width}x$height, ${wiring.describe()})';
}

/// Why a device can't be set up by the wizard (it can still be fixed with the
/// orientation controls).
enum SetupSupport {
  supported,

  /// Several panels that aren't equal panels in a simple grid.
  multiplePanels,

  /// More than one LED output.
  multipleOutputs,

  /// The output is virtual, network, HUB75, PWM/relay, or missing.
  unsupportedOutput,

  /// A custom LED map (ledmap*.json) is installed.
  customMap,

  /// Realtime pixels are shifted (`if.live.offset`).
  realtimeOffset,

  /// No LED hardware config (2D support compiled out, or unreadable).
  noTwoD,
}

/// What the wizard needs to know about a device, parsed from `/json/cfg` and
/// `/json/info`.
class DeviceSetupState {
  const DeviceSetupState({
    this.isMatrix = false,
    this.width,
    this.height,
    this.wiring,
    this.grid,
    this.panelCount = 0,
    this.ledCount = 0,
    this.outputs = const [],
    this.realtimeMaps = true,
    this.realtimeOffset = 0,
    this.currentLimitMa,
    this.hasCustomMap = false,
    this.pinLocked = false,
    this.hasLedConfig = true,
    this.mac = '',
    this.name = '',
    this.version = '',
  });

  /// The config was refused (HTTP 401): only the info fields are known.
  const DeviceSetupState.locked({
    this.ledCount = 0,
    this.width,
    this.height,
    this.mac = '',
    this.name = '',
    this.version = '',
  })  : isMatrix = false,
        wiring = null,
        grid = null,
        panelCount = 0,
        outputs = const [],
        realtimeMaps = true,
        realtimeOffset = 0,
        currentLimitMa = null,
        hasCustomMap = false,
        pinLocked = true,
        hasLedConfig = true;

  final bool isMatrix;

  /// Matrix size from `/json/info` (else the first panel); null for a strip.
  final int? width;
  final int? height;

  /// Wiring of the first panel; null when not a matrix.
  final PanelWiring? wiring;

  /// The panels as a regular grid (a single panel is 1×1); null when not a
  /// matrix, or when the panels aren't a simple grid.
  final PanelGrid? grid;
  final int panelCount;
  final int ledCount;

  /// `hw.led.ins` as sent by the device, untouched.
  final List<Map<String, dynamic>> outputs;

  /// `if.live.rlm`: whether streamed pixels go through WLED's LED map.
  final bool realtimeMaps;
  final int realtimeOffset;

  /// `hw.led.maxpwr` in mA; 0 means no limit, null unknown.
  final int? currentLimitMa;
  final bool hasCustomMap;
  final bool pinLocked;

  /// `hw.led` was present in the config.
  final bool hasLedConfig;
  final String mac;
  final String name;
  final String version;

  /// Parses [cfg] (`/json/cfg`) and [info] (`/json/info`).
  factory DeviceSetupState.fromJson({
    required Map<String, dynamic> cfg,
    required Map<String, dynamic> info,
    Iterable<String> files = const [],
  }) {
    final led = _map(_map(cfg['hw'])['led']);
    final matrix = _map(led['matrix']);
    final panels = [for (final p in _list(matrix['panels'])) _map(p)];
    final panel0 = panels.isEmpty ? const <String, dynamic>{} : panels.first;
    final live = _map(_map(cfg['if'])['live']);
    final leds = _map(info['leds']);
    final im = _map(leds['matrix']);
    final isMatrix = led['matrix'] is Map;
    int? size(Object? infoV, String key) {
      final v = _int(infoV) ?? (isMatrix ? _int(panel0[key]) : null);
      return v != null && v > 0 ? v : null;
    }

    return DeviceSetupState(
      isMatrix: isMatrix,
      width: size(im['w'], 'w'),
      height: size(im['h'], 'h'),
      wiring: isMatrix && panels.isNotEmpty
          ? PanelWiring.fromFlags(
              bottomStart: _flag(panel0['b']),
              rightStart: _flag(panel0['r']),
              vertical: _flag(panel0['v']),
              serpentine: _flag(panel0['s']),
            )
          : null,
      grid: isMatrix ? PanelGrid.fromPanels(panels) : null,
      panelCount: isMatrix ? (panels.isEmpty ? 1 : panels.length) : 0,
      ledCount: _int(leds['count']) ?? 0,
      outputs: [
        for (final o in _list(led['ins']))
          if (o is Map) Map<String, dynamic>.from(o),
      ],
      realtimeMaps: live['rlm'] != false,
      realtimeOffset: _int(live['offset']) ?? 0,
      currentLimitMa: _int(led['maxpwr']),
      hasCustomMap: files.any((f) => RegExp(r'^/?ledmap[0-9]*\.json$').hasMatch(f)) || [
        for (final m in _list(info['maps']))
          if (m is Map && (_int(m['id']) ?? 0) > 0) m
      ].isNotEmpty,
      hasLedConfig: led.isNotEmpty,
      mac: _str(info['mac']),
      name: _str(info['name']),
      version: _str(info['ver']),
    );
  }

  /// The info-only fields of a PIN-locked device.
  factory DeviceSetupState.lockedFromInfo(Map<String, dynamic> info) {
    final leds = _map(info['leds']), im = _map(leds['matrix']);
    return DeviceSetupState.locked(
      ledCount: _int(leds['count']) ?? 0,
      width: _int(im['w']),
      height: _int(im['h']),
      mac: _str(info['mac']),
      name: _str(info['name']),
      version: _str(info['ver']),
    );
  }

  /// Whether the wizard can drive this device. A locked device reports
  /// [SetupSupport.supported]: ask for the PIN first, then read again.
  SetupSupport get support {
    if (pinLocked) return SetupSupport.supported;
    if (!hasLedConfig) return SetupSupport.noTwoD;
    if (outputs.length > 1) return SetupSupport.multipleOutputs;
    if (outputs.isEmpty || !_supportedOutputType(_int(outputs.first['type']))) {
      return SetupSupport.unsupportedOutput;
    }
    if (panelCount > 1 && grid == null) return SetupSupport.multiplePanels;
    if (hasCustomMap) return SetupSupport.customMap;
    if (realtimeOffset != 0) return SetupSupport.realtimeOffset;
    return SetupSupport.supported;
  }

  /// The device already shows [s]: 2D on with these panels, and streamed
  /// pixels going through the map.
  bool isConfigured(DisplaySetup s) =>
      isMatrix && grid != null && grid == s.grid && width == s.width && height == s.height && realtimeMaps;
}

/// Digital strips (WS281x family, 16–39) and two-wire strips (48–63) only.
bool _supportedOutputType(int? type) =>
    type != null && ((type >= 16 && type <= 39) || (type >= 48 && type <= 63));

/// Form fields for `POST /settings/2D` that make the device the panels of
/// [s]: always the whole layout, every panel with its offset, width and
/// height. WLED reads serpentine by presence, so `P{i}S` is left out when
/// off.
Map<String, String> panelForm(DisplaySetup s) {
  final panels = s.grid.panels();
  return {
    'SOMP': '1',
    'MPC': '${panels.length}',
    for (final (i, p) in panels.indexed) ...{
      'P${i}B': p['b'] == true ? '1' : '0',
      'P${i}R': p['r'] == true ? '1' : '0',
      'P${i}V': p['v'] == true ? '1' : '0',
      if (p['s'] == true) 'P${i}S': 'on',
      'P${i}X': '${p['x']}',
      'P${i}Y': '${p['y']}',
      'P${i}W': '${p['w']}',
      'P${i}H': '${p['h']}',
    },
  };
}

/// Form fields that turn 2D off (a plain strip).
Map<String, String> stripForm() => {'SOMP': '0'};

/// Brightness limit in mA for a [supplyAmps] power supply: 85 % of the
/// supply, rounded down to 50 mA (WLED already reserves ~100 mA for the
/// controller). A lower, non-zero [currentMa] is kept as it is stricter.
int recommendedLimitMa(double supplyAmps, int? currentMa) {
  final v = ((supplyAmps * 1000 * 0.85) ~/ 50 * 50).clamp(50, 1 << 20);
  return currentMa != null && currentMa > 0 && currentMa < v ? currentMa : v;
}

/// What Glyph saves before changing a device so the change can be undone.
class SetupSnapshot {
  const SetupSnapshot({
    required this.mac,
    required this.host,
    required this.isMatrix,
    this.width,
    this.height,
    this.wiring,
    this.grid,
    required this.ledCount,
    required this.outputEntry,
    required this.realtimeMaps,
    this.currentLimitMa,
    this.appLayout = MatrixLayout.identity,
    required this.takenAt,
    this.playback,
    this.needsRestore = false,
  });

  /// Snapshot of [state] (which must be readable) taken now.
  factory SetupSnapshot.of(
    DeviceSetupState state, {
    required String host,
    MatrixLayout appLayout = MatrixLayout.identity,
    DateTime? takenAt,
    Map<String, dynamic>? playback,
  }) =>
      SetupSnapshot(
        mac: state.mac,
        host: host,
        isMatrix: state.isMatrix,
        width: state.width,
        height: state.height,
        wiring: state.wiring,
        grid: state.grid != null && !state.grid!.isSingle ? state.grid : null,
        ledCount: state.ledCount,
        outputEntry:
            state.outputs.isEmpty ? const {} : Map.of(state.outputs.first),
        realtimeMaps: state.realtimeMaps,
        currentLimitMa: state.currentLimitMa,
        appLayout: appLayout,
        takenAt: takenAt ?? DateTime.now(),
        playback: playback,
      );

  final String mac;
  final String host;
  final bool isMatrix;
  final int? width;
  final int? height;
  final PanelWiring? wiring;

  /// All panels when the device had several; null for a single panel.
  final PanelGrid? grid;
  final int ledCount;

  /// The complete first `hw.led.ins` entry (empty when unknown).
  final Map<String, dynamic> outputEntry;
  final bool realtimeMaps;
  final int? currentLimitMa;
  final MatrixLayout appLayout;
  final DateTime takenAt;

  /// `/json/state` as it was before the first layout write. WLED recreates
  /// its segments on a layout change (back to Solid), so this is what
  /// playback is restored from. Null when it could not be read.
  final Map<String, dynamic>? playback;

  /// A temporary test setting could not yet be restored.
  final bool needsRestore;

  SetupSnapshot withNeedsRestore(bool value) =>
      SetupSnapshot.fromJson({...toJson(), 'needsRestore': value});

  /// The display this snapshot had, when it was a matrix.
  DisplaySetup? get display => !isMatrix
      ? null
      : grid != null
      ? DisplaySetup.grid(grid!)
      : width != null && height != null && wiring != null
      ? DisplaySetup(width!, height!, wiring!)
      : null;

  Map<String, dynamic> toJson() => {
        'mac': mac,
        'host': host,
        'isMatrix': isMatrix,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (wiring != null) 'wiring': wiring!.toJson(),
        if (grid != null) 'grid': grid!.toJson(),
        'ledCount': ledCount,
        'outputEntry': outputEntry,
        'realtimeMaps': realtimeMaps,
        if (currentLimitMa != null) 'currentLimitMa': currentLimitMa,
        'appLayout': appLayout.toJson(),
        'takenAt': takenAt.toIso8601String(),
        'needsRestore': needsRestore,
        if (playback != null) 'playback': playback,
      };

  factory SetupSnapshot.fromJson(Map json) => SetupSnapshot(
        needsRestore: json['needsRestore'] == true,
        mac: '${json['mac'] ?? ''}',
        host: '${json['host'] ?? ''}',
        isMatrix: json['isMatrix'] == true,
        width: _int(json['width']),
        height: _int(json['height']),
        wiring: json['wiring'] is Map
            ? PanelWiring.fromJson(json['wiring'] as Map)
            : null,
        grid: PanelGrid.tryFromJson(json['grid']),
        ledCount: _int(json['ledCount']) ?? 0,
        outputEntry: json['outputEntry'] is Map
            ? Map<String, dynamic>.from(json['outputEntry'] as Map)
            : const {},
        realtimeMaps: json['realtimeMaps'] != false,
        currentLimitMa: _int(json['currentLimitMa']),
        appLayout: json['appLayout'] is Map
            ? MatrixLayout.fromJson(json['appLayout'] as Map)
            : MatrixLayout.identity,
        takenAt: DateTime.tryParse('${json['takenAt']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        playback: json['playback'] is Map
            ? Map<String, dynamic>.from(json['playback'] as Map)
            : null,
      );

  String encode() => jsonEncode(toJson());

  factory SetupSnapshot.decode(String s) =>
      SetupSnapshot.fromJson(jsonDecode(s) as Map);
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const {};

List<Object?> _list(Object? v) => v is List ? v : const [];

int? _int(Object? v) => v is num ? v.toInt() : null;

String _str(Object? v) => v is String ? v : '';

/// WLED writes flags as booleans in cfg but the config reader accepts 0/1.
bool _flag(Object? v) => v == true || (v is num && v != 0);
