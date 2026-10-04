import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/features/now_playing/cover_art.dart';
import 'package:glyph/features/now_playing/now_playing.dart';
import 'package:glyph/features/now_playing/now_playing_generator.dart';
import 'package:glyph/features/text/fonts.dart';

class _Feed implements NowPlayingFeed {
  @override
  NowPlaying? current;
}

/// A [size]² cover filled with [color].
Uint8List solid(int color, [int size = 8]) {
  final b = Uint8List(size * size * 3);
  for (var i = 0; i < b.length; i += 3) {
    b[i] = (color >> 16) & 0xFF;
    b[i + 1] = (color >> 8) & 0xFF;
    b[i + 2] = color & 0xFF;
  }
  return b;
}

final t0 = DateTime(2026, 10, 4, 12);

NowPlaying song({
  String title = 'Song',
  int color = 0x2040FF,
  int positionMs = 0,
  int durationMs = 100000,
  bool playing = true,
  bool art = true,
}) =>
    NowPlaying(
      title: title,
      artist: 'Band',
      durationMs: durationMs,
      positionMs: positionMs,
      at: t0,
      playing: playing,
      art: art ? solid(color) : null,
      artSize: art ? 8 : 0,
    );

int brightness(int c) => ((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF);

void main() {
  late _Feed feed;
  late DateTime now;
  late NowPlayingGenerator gen;
  final pal = palettes.first;
  final p = Params({});

  setUp(() {
    feed = _Feed();
    now = t0;
    gen = NowPlayingGenerator(feed, style: NowPlayingStyle(title: false), clock: () => now);
  });

  Frame run(EffectInstance fx, {double from = 0, double seconds = 0.1, int w = 16, int h = 16}) {
    final f = Frame(w, h);
    for (var t = from; t <= from + seconds; t += 1 / 40) {
      fx.render(f, t, 1 / 40, p, pal);
    }
    return f;
  }

  test('is live only, so it can never be sent to the device', () {
    expect(gen.liveOnly, isTrue);
  });

  test('shows the cover with a progress bar along the bottom', () {
    feed.current = song(positionMs: 25000); // a quarter through
    final f = run(gen.create(16, 16, 1));
    final bar = [for (var x = 0; x < 16; x++) brightness(f.get(x, 15))];
    // Elapsed part bright, the rest a faint track.
    expect(bar[0], greaterThan(bar[10] * 3));
    expect(bar[3], greaterThan(bar[10] * 3));
    expect(bar[10], greaterThan(0));
    // The cover itself fills the rest, blue.
    final c = f.get(8, 8);
    expect(c & 0xFF, greaterThan((c >> 16) & 0xFF));
  });

  test('the bar follows the clock between updates', () {
    feed.current = song(positionMs: 0, durationMs: 16000);
    final fx = gen.create(16, 16, 1);
    final before = run(fx);
    now = t0.add(const Duration(seconds: 8));
    final after = run(fx, from: 1);
    int lit(Frame f) => [for (var x = 0; x < 16; x++) f.get(x, 15)]
        .where((c) => brightness(c) > brightness(before.get(15, 15)) * 2)
        .length;
    expect(lit(before), lessThanOrEqualTo(1));
    expect(lit(after), inInclusiveRange(7, 9));
  });

  test('playing: the newest LED blinks; paused: the bar holds still', () {
    List<int> barAt(EffectInstance fx, double t) {
      final f = Frame(16, 16);
      fx.render(f, t, 1 / 40, p, pal);
      return [for (var x = 0; x < 16; x++) f.get(x, 15)];
    }

    feed.current = song(positionMs: 25500); // the head is LED 4
    final fx = gen.create(16, 16, 1);
    final on = barAt(fx, 10.2), off = barAt(fx, 10.8);
    for (var x = 0; x < 16; x++) {
      if (x == 4) {
        expect(on[x], isNot(off[x]), reason: 'the head blinks');
      } else {
        expect(on[x], off[x], reason: 'LED $x stays put');
      }
    }

    feed.current = song(positionMs: 25500, playing: false);
    final paused = gen.create(16, 16, 1);
    expect(barAt(paused, 10.2), barAt(paused, 10.8));
  });

  test('no bar when switched off or the length is unknown', () {
    feed.current = song(positionMs: 90000, color: 0x000000);
    gen.style.bar = false;
    expect([for (var x = 0; x < 16; x++) brightness(run(gen.create(16, 16, 1)).get(x, 15))].every((b) => b == 0),
        isTrue);
    gen.style.bar = true;
    feed.current = song(durationMs: 0, color: 0x000000);
    expect([for (var x = 0; x < 16; x++) brightness(run(gen.create(16, 16, 1)).get(x, 15))].every((b) => b == 0),
        isTrue);
  });

  test('dims while paused', () {
    feed.current = song();
    final playing = run(gen.create(16, 16, 1), seconds: 1);
    feed.current = song(playing: false);
    final paused = run(gen.create(16, 16, 1), seconds: 1.5);
    expect(brightness(paused.get(8, 8)), lessThan(brightness(playing.get(8, 8)) * 0.5));
  });

  test('cross-fades to the next cover', () {
    feed.current = song(title: 'A', color: 0xFF2020);
    final fx = gen.create(16, 16, 1);
    run(fx, seconds: 1);
    feed.current = song(title: 'B', color: 0x2020FF);
    final mid = run(fx, from: 1.1, seconds: 0.35);
    final c = mid.get(8, 8);
    expect((c >> 16) & 0xFF, greaterThan(20), reason: 'still part red');
    expect(c & 0xFF, greaterThan(20), reason: 'already part blue');
    final end = run(fx, from: 1.5, seconds: 1);
    expect((end.get(8, 8) >> 16) & 0xFF, lessThan(end.get(8, 8) & 0xFF));
  });

  test('scrolls the song name over the cover when a song starts, then clears', () {
    gen.style.title = true;
    feed.current = song(color: 0x103010);
    final fx = gen.create(16, 16, 1);
    var sawWhite = false;
    final f = Frame(16, 16);
    for (var t = 0.0; t < 2; t += 1 / 40) {
      fx.render(f, t, 1 / 40, p, pal);
      for (var i = 0; i < 16 * 15; i++) {
        if (f.get(i % 16, i ~/ 16) == 0xFFFFFF) sawWhite = true;
      }
    }
    expect(sawWhite, isTrue);
    for (var t = 2.0; t < 12; t += 1 / 40) {
      fx.render(f, t, 1 / 40, p, pal);
    }
    for (var i = 0; i < 16 * 15; i++) {
      expect(f.get(i % 16, i ~/ 16), isNot(0xFFFFFF));
    }
  });

  test('wide panels put the cover left and the name beside it', () {
    feed.current = song(color: 0x2040FF);
    final f = run(gen.create(32, 16, 1), w: 32, h: 16);
    expect(brightness(f.get(8, 8)), greaterThan(0));
    final right = [
      for (var y = 0; y < 15; y++)
        for (var x = 17; x < 32; x++) f.get(x, y)
    ];
    expect(right.any((c) => c != 0), isTrue);
  });

  test('songs without a cover get their own colours', () {
    feed.current = song(art: false, title: 'Untitled');
    final f = run(gen.create(16, 16, 1));
    expect(brightness(f.get(4, 4)), greaterThan(0));
  });

  test('nothing playing shows breathing notes', () {
    final f = run(gen.create(16, 16, 1));
    final lit = [for (var i = 0; i < 256; i++) f.get(i % 16, i ~/ 16)].where((c) => c != 0).length;
    expect(lit, inInclusiveRange(10, 40));
  });

  test('names keep only what the font can draw', () {
    expect(cleanForFont('Don’t Stop — Live', classicFont), "Don't Stop - Live");
    expect(cleanForFont('Kesariya केसरिया', classicFont), 'Kesariya');
    expect(cleanForFont('🎵 Hi  there', classicFont), 'Hi there');
  });

  group('cover tuning', () {
    test('shrinks to the panel and picks the dominant colour', () {
      final art = solid(0xE03030, 32);
      // A small blue corner shouldn't win.
      for (var y = 0; y < 6; y++) {
        for (var x = 0; x < 6; x++) {
          final i = (y * 32 + x) * 3;
          art[i] = 0x20;
          art[i + 1] = 0x40;
          art[i + 2] = 0xFF;
        }
      }
      final c = prepareCover(art, 32, 16);
      expect(c.frame.width, 16);
      expect((c.accent >> 16) & 0xFF, 255);
      expect(c.accent & 0xFF, lessThan(120));
    });

    test('greyscale covers get a soft white accent; near-black turns off', () {
      final c = prepareCover(solid(0x808080, 16), 16, 16);
      expect(c.accent, 0xD8D8E0);
      final dark = prepareCover(solid(0x080808, 16), 16, 16);
      expect(dark.frame.get(3, 3), 0);
    });

    test('vivid adds saturation', () {
      final dull = prepareCover(solid(0x806060, 8), 8, 8, vivid: 0).frame.get(2, 2);
      final vivid = prepareCover(solid(0x806060, 8), 8, 8, vivid: 1).frame.get(2, 2);
      int spread(int c) => ((c >> 16) & 0xFF) - (c & 0xFF);
      expect(spread(vivid), greaterThan(spread(dull)));
    });
  });

  group('NowPlaying', () {
    test('reads the bridge event and extrapolates the position', () {
      final np = NowPlaying.fromMap({
        'access': true,
        'title': 'Song',
        'artist': 'Band',
        'app': 'Spotify',
        'durationMs': 200000,
        'positionMs': 60000,
        'atMs': t0.millisecondsSinceEpoch,
        'speed': 1.0,
        'playing': true,
        'art': solid(0xFF0000, 4),
        'artSize': 4,
      })!;
      expect(np.app, 'Spotify');
      expect(np.positionAt(t0.add(const Duration(seconds: 10))), 70000);
      expect(np.progressAt(t0.add(const Duration(days: 1))), 1.0);
      expect(np.artSize, 4);
    });

    test('paused stays put; unknown length has no progress; bad art is dropped', () {
      final np = NowPlaying.fromMap({
        'title': 'Radio',
        'positionMs': 5000,
        'atMs': t0.millisecondsSinceEpoch,
        'playing': false,
        'art': Uint8List(10),
        'artSize': 64,
      })!;
      expect(np.positionAt(t0.add(const Duration(minutes: 1))), 5000);
      expect(np.progressAt(t0), isNull);
      expect(np.art, isNull);
      expect(NowPlaying.fromMap({'access': true}), isNull);
      expect(NowPlaying.fromMap({'title': 'A', 'app': 'com.spotify.music'})!.app, '');
      expect(NowPlaying.fromMap({'title': 'A', 'app': 'YouTube Music'})!.app, 'YouTube Music');
    });

    test('formats times', () {
      expect(formatTrackTime(187000), '3:07');
      expect(formatTrackTime(3723000), '1:02:03');
    });
  });
}
