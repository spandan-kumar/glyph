import 'dart:math' as math;

import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../text/fonts.dart';
import 'cover_art.dart';
import 'now_playing.dart';

/// How Now Playing looks. Mutable: the screen edits it and running
/// instances pick the change up on their next frame.
class NowPlayingStyle {
  NowPlayingStyle({this.bar = true, this.title = true, this.vivid = 0.5});

  /// A one-row progress bar along the bottom, in the cover's colour.
  bool bar;

  /// Scroll the song's name across the cover when a new one starts.
  bool title;

  /// Extra colour for the cover, 0..1.
  double vivid;
}

/// The cover of whatever's playing on the phone, with a progress bar.
///
/// Square-ish matrices show the cover full size and scroll the song's name
/// over it when the track changes; wide ones (≥ 1.5:1) put the cover on the
/// left and keep the name scrolling beside it. Covers cross-fade between
/// tracks and dim while paused.
class NowPlayingGenerator extends Generator {
  NowPlayingGenerator(this.feed, {NowPlayingStyle? style, DateTime Function()? clock})
      : style = style ?? NowPlayingStyle(),
        clock = clock ?? DateTime.now;

  final NowPlayingFeed feed;
  final NowPlayingStyle style;
  final DateTime Function() clock;

  @override
  String get id => 'now_playing';
  @override
  String get name => 'Now Playing';

  // Covers follow the phone live; sending would also fill the device's
  // storage with a GIF per song.
  @override
  bool get liveOnly => true;

  @override
  EffectInstance create(int width, int height, int seed) => _NowPlayingInstance(this, width, height);
}

class _NowPlayingInstance extends EffectInstance {
  _NowPlayingInstance(this.g, this.w, this.h)
      : wide = w >= h * 1.5,
        s = math.max(1, math.min(w, h)),
        font = math.min(w, h) >= 12 ? classicFont : tinyFont {
    artX = wide ? 0 : (w - s) ~/ 2;
    artY = wide ? 0 : (h - s) ~/ 2;
    layer = Frame(s, s);
  }

  static const _scroll = 14.0; // pixels per second
  static const _fade = 0.8; // cover cross-fade, seconds
  static const _gap = 8; // pixels between repeats of a looping name

  final NowPlayingGenerator g;
  final int w, h, s;
  final bool wide;
  final BitmapFont font;
  late final int artX, artY;
  late final Frame layer;

  CoverArt? _cover;
  int _coverId = 0;
  double _coverVivid = -1;
  Frame? _prev;
  double _fadeAt = -1;

  String? _track;
  String _text = '';
  int _textW = 0;
  double _titleAt = -1e9;
  double _dim = 1;

  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    out.fill(0);
    final np = g.feed.current;
    if (np == null) {
      _track = null;
      _idle(out, t);
      return;
    }
    if (np.trackKey != _track) {
      if (_track != null) {
        _prev = layer.copy();
        _fadeAt = t;
      }
      _track = np.trackKey;
      _titleAt = t;
      _text = cleanForFont(np.artist.isEmpty ? np.title : '${np.title} - ${np.artist}', font);
      _textW = font.measure(_text);
    }
    _updateCover(np);
    final cover = _cover!;

    // The cover, cross-faded from the previous track's.
    final fade = _fadeAt < 0 ? 1.0 : ((t - _fadeAt) / _fade).clamp(0.0, 1.0);
    final prev = _prev;
    if (prev == null || fade >= 1) {
      layer.rgb.setAll(0, cover.frame.rgb);
      _prev = null;
    } else {
      final e = _ease(fade);
      for (var i = 0; i < layer.rgb.length; i++) {
        layer.rgb[i] = (prev.rgb[i] + (cover.frame.rgb[i] - prev.rgb[i]) * e).round();
      }
    }

    // Paused: settle to a dim cover rather than snapping.
    _dim += ((np.playing ? 1.0 : 0.35) - _dim) * math.min(1.0, dt * 5);

    // On square panels the name scrolls over the cover, which steps back.
    var shade = 1.0, nameX = 0.0;
    final showName = g.style.title && !wide && _text.isNotEmpty;
    if (showName) {
      final run = t - _titleAt;
      final dur = (w + _textW) / _scroll + 0.6;
      if (run < dur) {
        final k = math.min(math.min(run, dur - run) / 0.3, 1.0).clamp(0.0, 1.0);
        shade = 1 - 0.75 * k;
        nameX = w - (run - 0.3) * _scroll;
      } else {
        nameX = double.nan;
      }
    }
    _blit(out, layer, artX, artY, _dim * shade);

    final y = ((h - font.capHeight) / 2).floor() - (g.style.bar && h >= 10 ? 1 : 0);
    if (showName && !nameX.isNaN) {
      drawText(out, font, _text, nameX.floor(), y, 0xFFFFFF, 0, w);
    } else if (wide && _text.isNotEmpty) {
      // Wide panels: the name keeps looping beside the cover.
      final x0 = s + 1, span = w - x0;
      final color = scaleColor(cover.accent, 0.4 + 0.6 * _dim);
      if (_textW <= span) {
        drawText(out, font, _text, x0 + (span - _textW) ~/ 2, y, color, x0, w);
      } else {
        final loop = _textW + _gap;
        final off = (t * _scroll) % loop;
        for (var k = 0; k < 2; k++) {
          drawText(out, font, _text, (x0 + span ~/ 3 - off + k * loop).floor(), y, color, x0, w);
        }
      }
    }

    final progress = np.progressAt(g.clock());
    if (g.style.bar && progress != null) _bar(out, progress, cover.accent, np.playing, t);
  }

  void _updateCover(NowPlaying np) {
    final id = np.art != null ? np.artId : -np.title.hashCode.abs() - 1;
    if (id == _coverId && g.style.vivid == _coverVivid && _cover != null) return;
    _coverId = id;
    _coverVivid = g.style.vivid;
    _cover = np.art != null
        ? prepareCover(np.art!, np.artSize, s, vivid: g.style.vivid)
        : placeholderCover(np.title, s);
  }

  /// Elapsed in the cover's colour on a faint track. While playing the
  /// newest LED blinks, like a cursor; paused, the whole bar holds still
  /// with the newest LED part-lit by how far into it the song is.
  void _bar(Frame out, double progress, int accent, bool playing, double t) {
    final y = h - 1;
    final track = scaleColor(accent, 0.22);
    final filled = progress.clamp(0.0, 1.0) * w;
    final head = filled.floor();
    for (var x = 0; x < w; x++) {
      int c;
      if (x < head) {
        c = accent;
      } else if (x == head) {
        c = playing ? (t % 1.0 < 0.55 ? accent : track) : lerpColor(track, accent, filled - head);
      } else {
        c = track;
      }
      out.set(x, y, c);
    }
  }

  /// Nothing playing: a pair of notes breathing in the middle.
  void _idle(Frame out, double t) {
    final k = 0.25 + 0.45 * (0.5 + 0.5 * math.sin(t * 1.6));
    final c = scaleColor(0xB4C0FF, k);
    final ox = (w - _note[0].length) ~/ 2, oy = (h - _note.length) ~/ 2;
    for (var y = 0; y < _note.length; y++) {
      for (var x = 0; x < _note[y].length; x++) {
        if (_note[y][x] == '#') out.set(ox + x, oy + y, c);
      }
    }
  }

  static const _note = [
    '..######',
    '..#....#',
    '..#....#',
    '..#....#',
    '###..###',
    '###..###',
  ];
}

double _ease(double u) => u * u * (3 - 2 * u);

void _blit(Frame out, Frame src, int ox, int oy, double k) {
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final i = (y * src.width + x) * 3;
      out.set(ox + x, oy + y,
          rgb((src.rgb[i] * k).round(), (src.rgb[i + 1] * k).round(), (src.rgb[i + 2] * k).round()));
    }
  }
}

/// Draws [text] with its left edge at [x], clipped to columns
/// [clipL]..[clipR).
void drawText(Frame out, BitmapFont font, String text, int x, int y, int color, int clipL, int clipR) {
  var cx = x;
  for (final r in text.runes) {
    final gl = font.glyph(r);
    if (cx > clipR) break;
    if (cx + gl.width >= clipL) {
      for (var gy = 0; gy < gl.rows.length; gy++) {
        for (var gx = 0; gx < gl.width; gx++) {
          final px = cx + gx;
          if (px >= clipL && px < clipR && gl.on(gx, gy)) out.set(px, y + gy, color);
        }
      }
    }
    cx += gl.width + font.spacing;
  }
}

/// [text] with only what [font] can draw: curly quotes and dashes become
/// plain ones, letters fall back to capitals, anything else (other scripts,
/// emoji) is dropped rather than shown as '?'.
String cleanForFont(String text, BitmapFont font) {
  final b = StringBuffer();
  var space = false;
  for (var r in text.runes) {
    r = switch (r) {
      0x2018 || 0x2019 || 0x02BC => 0x27,
      0x201C || 0x201D => 0x22,
      0x2013 || 0x2014 || 0x2015 => 0x2D,
      _ => r,
    };
    final isSpace = r == 0x20 || r == 0x09 || r == 0xA0;
    final drawable = font.has(r) || (r >= 0x61 && r <= 0x7A && font.has(r - 32));
    if (isSpace || !drawable) {
      space = b.isNotEmpty;
      continue;
    }
    if (space) b.write(' ');
    space = false;
    b.writeCharCode(r);
  }
  return b.toString();
}
