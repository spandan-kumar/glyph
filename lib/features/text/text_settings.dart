/// Everything the text studio can tweak, for text, clock and countdown.
/// Mutable for the editor; generators take a [copy].
class TextSettings {
  TextSettings({
    this.text = 'Hello!',
    this.font = 'classic',
    this.large = true,
    this.colorMode = 'solid',
    this.color = 0x3DDCFF,
    this.palette = 'rainbow',
    this.speed = 0.4,
    this.direction = 'left',
    this.background = '',
    this.bgDim = 0.35,
    this.effect = 'none',
    this.hour24 = true,
    this.seconds = false,
    this.blink = true,
    this.date = true,
    this.analog = false,
    this.target,
    this.durationSec = 300,
    this.useDuration = true,
    this.doneText = 'Time!',
  });

  String text;

  /// 'tiny' | 'classic' | 'bold'
  String font;

  /// Scale glyphs up on tall matrices.
  bool large;

  /// 'solid' | 'gradient' | 'rainbow' (per letter) | 'animated'
  String colorMode;
  int color;
  String palette;

  /// 0..1, mapped to pixels per second by [pixelsPerSecond].
  double speed;

  /// 'left' | 'right' | 'up' | 'static'
  String direction;

  /// Library generator id drawn behind the text; empty for none.
  String background;
  double bgDim;

  /// 'none' | 'outline' | 'shadow'
  String effect;

  bool hour24;
  bool seconds;
  bool blink;
  bool date;
  bool analog;

  /// Countdown goal when [useDuration] is false.
  DateTime? target;
  int durationSec;
  bool useDuration;
  String doneText;

  double get pixelsPerSecond => 3 + speed.clamp(0.0, 1.0) * 37;

  TextSettings copy() => TextSettings.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'text': text,
        'font': font,
        'large': large,
        'colorMode': colorMode,
        'color': color,
        'palette': palette,
        'speed': speed,
        'direction': direction,
        'background': background,
        'bgDim': bgDim,
        'effect': effect,
        'hour24': hour24,
        'seconds': seconds,
        'blink': blink,
        'date': date,
        'analog': analog,
        if (target != null) 'target': target!.toIso8601String(),
        'durationSec': durationSec,
        'useDuration': useDuration,
        'doneText': doneText,
      };

  factory TextSettings.fromJson(Map<String, dynamic> j) {
    final d = TextSettings();
    T pick<T>(String k, T fallback) {
      final v = j[k];
      if (v is T) return v;
      if (fallback is double && v is num) return v.toDouble() as T;
      if (fallback is int && v is num) return v.toInt() as T;
      return fallback;
    }

    final t = j['target'];
    return TextSettings(
      text: pick('text', d.text),
      font: pick('font', d.font),
      large: pick('large', d.large),
      colorMode: pick('colorMode', d.colorMode),
      color: pick('color', d.color),
      palette: pick('palette', d.palette),
      speed: pick('speed', d.speed),
      direction: pick('direction', d.direction),
      background: pick('background', d.background),
      bgDim: pick('bgDim', d.bgDim),
      effect: pick('effect', d.effect),
      hour24: pick('hour24', d.hour24),
      seconds: pick('seconds', d.seconds),
      blink: pick('blink', d.blink),
      date: pick('date', d.date),
      analog: pick('analog', d.analog),
      target: t is String ? DateTime.tryParse(t) : null,
      durationSec: pick('durationSec', d.durationSec),
      useDuration: pick('useDuration', d.useDuration),
      doneText: pick('doneText', d.doneText),
    );
  }
}
