import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/features/audio/audio_engine.dart';
import 'package:glyph/features/audio/visualizers.dart';

import 'fakes.dart';

int litCount(Frame f) {
  var n = 0;
  for (var i = 0; i < f.pixelCount; i++) {
    if (f.rgb[i * 3] > 8 || f.rgb[i * 3 + 1] > 8 || f.rgb[i * 3 + 2] > 8) n++;
  }
  return n;
}

AudioFeatures loud(double t, {double bands = 0.8, int beats = 0}) => AudioFeatures(
  bands: Float32List.fromList([for (var i = 0; i < 16; i++) bands * (0.6 + 0.4 * sin(t * 3 + i))]),
  wave: Float32List.fromList([for (var i = 0; i < 64; i++) 0.9 * sin(2 * pi * i / 32)]),
  level: 0.8,
  bass: 0.9,
  mid: 0.6,
  treble: 0.5,
  beatCount: beats,
  beatStrength: 0.9,
  bpm: 120,
  silent: false,
  time: t,
);

void main() {
  final probe = audioVisualizers(FixedFeed(AudioFeatures.silence));

  test('at least eight visualisers with unique ids and real palettes', () {
    expect(probe.length, greaterThanOrEqualTo(8));
    expect(probe.map((v) => v.id).toSet().length, probe.length);
    for (final v in probe) {
      expect(palettes.map((p) => p.id), contains(v.defaultPalette), reason: v.id);
      expect(v.blurb, isNotEmpty);
    }
  });

  const sizes = [(16, 16), (8, 32), (32, 8), (5, 3), (1, 1), (48, 24)];
  for (final v in probe) {
    for (final (w, h) in sizes) {
      test('${v.id} at ${w}x$h: idle when silent, reacts to sound', () {
        final feed = FixedFeed(AudioFeatures.silence);
        final g = audioVisualizers(feed).firstWhere((x) => x.id == v.id);
        final fx = g.create(w, h, 5);
        final out = Frame(w, h);
        final params = Params.defaultsFor(g);
        final pal = paletteById(g.defaultPalette);
        const dt = 1 / 40;
        var idleLit = 0;
        for (var i = 0; i < 160; i++) {
          fx.render(out, i * dt, dt, params, pal);
          if (i > 60) idleLit = max(idleLit, litCount(out));
        }
        // Silence must not mean a black matrix.
        if (w * h > 1) expect(idleLit, greaterThan(0), reason: 'black when idle');

        var liveLit = 0, beats = 0;
        for (var i = 160; i < 400; i++) {
          final t = i * dt;
          if (i % 20 == 0) beats++;
          feed.latest = loud(t, beats: beats);
          fx.render(out, t, dt, params, pal);
          if (i > 280) liveLit = max(liveLit, litCount(out));
        }
        if (w * h > 1) {
          expect(liveLit, greaterThanOrEqualTo(idleLit), reason: 'live dimmer than idle');
        }

        // Frame hiccups and a return to silence are fine too.
        feed.latest = AudioFeatures.silence;
        fx.render(out, 20, 0, params, pal);
        fx.render(out, 21, 0.1, params, pal);
      });
    }
  }

  test('spectrum bars follow band height', () {
    final feed = FixedFeed(AudioFeatures.silence);
    final g = SpectrumBars(feed);
    final fx = g.create(16, 16, 1);
    final out = Frame(16, 16);
    final bands = Float32List(16)
      ..fillRange(0, 8, 1.0)
      ..fillRange(8, 16, 0.25);
    for (var i = 0; i < 200; i++) {
      feed.latest = AudioFeatures(bands: bands, wave: Float32List(0), silent: false, time: i / 40);
      fx.render(out, i / 40, 1 / 40, Params.defaultsFor(g), paletteById('rainbow'));
    }
    int litRows(int x) => [for (var y = 0; y < 16; y++) out.get(x, y)].where((c) => c != 0).length;
    expect(litRows(2), 16);
    // A quarter-height bar plus its peak dot.
    expect(litRows(12), inInclusiveRange(4, 5));
  });

  test('beat rings and starbursts fire on beats, not on steady sound', () {
    for (final g in [
      BeatPulse(FixedFeed(AudioFeatures.silence)),
      Starburst(FixedFeed(AudioFeatures.silence)),
    ]) {
      final feed = g.feed as FixedFeed;
      final fx = g.create(16, 16, 2);
      final out = Frame(16, 16);
      final params = Params.defaultsFor(g);
      final pal = paletteById(g.defaultPalette);
      var t = 0.0;
      // Live but quiet and beatless: settle out of idle.
      for (var i = 0; i < 160; i++, t += 1 / 40) {
        feed.latest = loud(t, bands: 0.1).copyQuiet();
        fx.render(out, t, 1 / 40, params, pal);
      }
      final before = litCount(out);
      feed.latest = loud(t, bands: 0.1, beats: 1).copyQuiet();
      var after = 0;
      for (var i = 0; i < 8; i++, t += 1 / 40) {
        fx.render(out, t, 1 / 40, params, pal);
        after = max(after, litCount(out));
      }
      expect(after, greaterThan(before + 4), reason: g.id);
    }
  });
}

extension on AudioFeatures {
  /// Same snapshot with the bass/level drives turned right down.
  AudioFeatures copyQuiet() => AudioFeatures(
    bands: bands,
    wave: wave,
    level: 0.05,
    bass: 0.02,
    mid: 0.02,
    treble: 0,
    beatCount: beatCount,
    beatStrength: beatStrength,
    silent: false,
    time: time,
  );
}
