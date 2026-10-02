import 'layout.dart';

/// Parsed /json/info. Every field is optional on some firmware: ESP8266 and
/// older builds omit `matrix`, `fs`, `flash` or `wifi.signal`.
class WledInfo {
  const WledInfo({
    required this.name,
    required this.version,
    required this.arch,
    required this.brand,
    required this.ledCount,
    this.matrixWidth,
    this.matrixHeight,
    this.fsUsedKb,
    this.fsTotalKb,
    this.flashMb,
    this.rssi,
    this.signal,
    required this.fxCount,
    required this.ip,
    required this.mac,
    required this.isLive,
    required this.liveSource,
    this.isRgbw = false,
    this.freeHeap,
    this.raw = const {},
  });

  final String name;
  final String version;
  final String arch;
  final String brand;
  final int ledCount;
  final int? matrixWidth;
  final int? matrixHeight;
  final int? fsUsedKb;
  final int? fsTotalKb;
  final int? flashMb;
  final int? rssi;
  final int? signal;
  final int fxCount;
  final String ip;
  final String mac;
  final bool isLive;

  /// Realtime protocol in use (`lm`), e.g. "DDP"; empty when not live.
  final String liveSource;
  final bool isRgbw;
  final int? freeHeap;
  final Map<String, dynamic> raw;

  bool get isEsp8266 => arch.toLowerCase().contains('8266');
  bool get isWled => brand.toUpperCase() == 'WLED';
  bool get hasMatrix =>
      (matrixWidth ?? 0) > 0 && (matrixHeight ?? 0) > 0;

  /// Numeric (major, minor, patch) from e.g. "16.0.1" or "0.14.4-b1".
  (int, int, int) get versionParts {
    final m = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(version);
    int g(int i) => int.tryParse(m?.group(i) ?? '') ?? 0;
    return (g(1), g(2), g(3));
  }

  bool versionAtLeast(int major, [int minor = 0, int patch = 0]) {
    final (a, b, c) = versionParts;
    if (a != major) return a > major;
    if (b != minor) return b > minor;
    return c >= patch;
  }

  factory WledInfo.fromJson(Map<String, dynamic> j) {
    final leds = _map(j['leds']);
    final matrix = _map(leds['matrix']);
    final fs = _map(j['fs']);
    final wifi = _map(j['wifi']);
    return WledInfo(
      name: _str(j['name'], 'WLED'),
      version: _str(j['ver']),
      arch: _str(j['arch']),
      brand: _str(j['brand']),
      ledCount: _int(leds['count']) ?? 0,
      matrixWidth: _int(matrix['w']),
      matrixHeight: _int(matrix['h']),
      fsUsedKb: _int(fs['u']),
      fsTotalKb: _int(fs['t']),
      flashMb: _int(j['flash']),
      rssi: _int(wifi['rssi']),
      signal: _int(wifi['signal']),
      fxCount: _int(j['fxcount']) ?? 0,
      ip: _str(j['ip']),
      mac: _str(j['mac']),
      isLive: j['live'] == true,
      liveSource: _str(j['lm']),
      isRgbw: leds['rgbw'] == true,
      freeHeap: _int(j['freeheap']),
      raw: j,
    );
  }
}

/// What this particular device can do, detected rather than assumed.
class DeviceCapabilities {
  const DeviceCapabilities({
    required this.canStream,
    required this.canPlayGifs,
    required this.imageEffectId,
    required this.freeFsBytes,
    required this.is2D,
    required this.width,
    required this.height,
    required this.ledCount,
    required this.isEsp8266,
  });

  /// Headroom kept free on the device filesystem (presets, cfg rewrites).
  static const fsSafetyMarginBytes = 32 * 1024;

  final bool canStream;
  final bool canPlayGifs;
  final int? imageEffectId;
  final int freeFsBytes;
  final bool is2D;

  /// Matrix size to render at; for a 1D strip this is ledCount × 1.
  final int width;
  final int height;
  final int ledCount;
  final bool isEsp8266;

  /// Frame rate the device can comfortably take over Wi‑Fi.
  int get suggestedFps => isEsp8266 ? 30 : 40;

  bool fitsFile(int bytes) => bytes + fsSafetyMarginBytes <= freeFsBytes;

  /// [effects] is /json/eff (index = effect id). GIF playback needs the
  /// "Image" effect (WLED 16+) backed by WLED_ENABLE_GIF, which only the
  /// ESP32 family builds enable; ESP8266 lists "Image" but falls back to a
  /// static colour (wled00/FX.cpp mode_image, platformio.ini).
  /// [realtimeEnabled] is cfg `if.live.en` when known.
  static DeviceCapabilities detect(WledInfo info, List<String> effects,
      {bool? realtimeEnabled}) {
    final idx = effects.indexWhere((e) => e.trim().toLowerCase() == 'image');
    final imageId = idx < 0 ? null : idx;
    final used = info.fsUsedKb, total = info.fsTotalKb;
    final free = used != null && total != null && total > used
        ? (total - used) * 1024
        : 0;
    final is2D = info.hasMatrix;
    return DeviceCapabilities(
      canStream: info.ledCount > 0 && realtimeEnabled != false,
      canPlayGifs: !info.isEsp8266 && imageId != null,
      imageEffectId: imageId,
      freeFsBytes: free,
      is2D: is2D,
      width: is2D ? info.matrixWidth! : info.ledCount,
      height: is2D ? info.matrixHeight! : 1,
      ledCount: info.ledCount,
      isEsp8266: info.isEsp8266,
    );
  }
}

/// A device the user has added, persisted by the app.
class SavedDevice {
  const SavedDevice(
      {required this.host,
      required this.name,
      this.layout = MatrixLayout.identity,
      this.mac});

  final String host;
  final String name;
  final MatrixLayout layout;

  /// Stable identity across DHCP address changes, when known.
  final String? mac;

  SavedDevice copyWith(
          {String? host, String? name, MatrixLayout? layout, String? mac}) =>
      SavedDevice(
        host: host ?? this.host,
        name: name ?? this.name,
        layout: layout ?? this.layout,
        mac: mac ?? this.mac,
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        'name': name,
        'layout': layout.toJson(),
        if (mac != null) 'mac': mac,
      };

  factory SavedDevice.fromJson(Map<String, dynamic> j) => SavedDevice(
        host: _str(j['host']),
        name: _str(j['name'], _str(j['host'])),
        layout: j['layout'] is Map
            ? MatrixLayout.fromJson(j['layout'] as Map)
            : MatrixLayout.identity,
        mac: j['mac'] as String?,
      );
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const {};

int? _int(Object? v) => v is num ? v.toInt() : null;

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
