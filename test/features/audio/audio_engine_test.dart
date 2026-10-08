import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/audio/audio_engine.dart';

import 'fakes.dart';

const sr = 44100;

List<double> sine(double hz, double amp, double seconds, {double phase = 0}) => [
  for (var i = 0; i < (seconds * sr).round(); i++) amp * sin(2 * pi * hz * i / sr + phase),
];

List<double> noise(double amp, double seconds, [int seed = 1]) {
  final r = Random(seed);
  return [for (var i = 0; i < (seconds * sr).round(); i++) amp * (r.nextDouble() * 2 - 1)];
}

/// Pink-ish noise (Paul Kellet's filter), closer to music than white noise.
List<double> pink(double amp, double seconds) {
  final white = noise(1, seconds, 3);
  var b0 = 0.0, b1 = 0.0, b2 = 0.0;
  return [
    for (final w in white)
      () {
        b0 = 0.99765 * b0 + w * 0.0990460;
        b1 = 0.96300 * b1 + w * 0.2965164;
        b2 = 0.57000 * b2 + w * 1.0526913;
        return amp * (b0 + b1 + b2 + w * 0.1848) / 3;
      }(),
  ];
}

/// Kick drum: a pitch-dropping sine burst with a fast decay.
List<double> kicks(double bpm, double seconds, {double amp = 0.7, double bed = 0.004}) {
  final out = noise(bed, seconds, 9);
  final period = 60 / bpm;
  for (var t0 = 0.5; t0 < seconds - 0.2; t0 += period) {
    final s0 = (t0 * sr).round();
    var ph = 0.0;
    for (var i = 0; i < (0.25 * sr).round() && s0 + i < out.length; i++) {
      final t = i / sr;
      final f = 50 + 100 * exp(-t / 0.03);
      ph += 2 * pi * f / sr;
      out[s0 + i] += amp * exp(-t / 0.08) * sin(ph);
    }
  }
  return out;
}

/// Feeds hop-sized chunks, like a mic stream, and records beat times.
List<double> feed(AudioEngine e, List<double> samples, {int chunk = 512}) {
  final beats = <double>[];
  var lastBeat = e.latest.beatCount;
  for (var i = 0; i < samples.length; i += chunk) {
    e.addSamples(samples.sublist(i, min(i + chunk, samples.length)));
    if (e.latest.beatCount > lastBeat) beats.add(e.latest.time);
    lastBeat = e.latest.beatCount;
  }
  return beats;
}

int argmax(Float32List a) {
  var best = 0;
  for (var i = 1; i < a.length; i++) {
    if (a[i] > a[best]) best = i;
  }
  return best;
}

void main() {
  test('small PCM chunks publish only fresh analyses at output cadence', () {
    final e = AudioEngine();
    addTearDown(e.dispose);
    var updates = 0;
    e.features.addListener(() => updates++);
    feed(e, sine(1000, 0.5, 1), chunk: 256);
    expect(updates, 43);
    expect(e.latest.dominantHz, closeTo(1000, 10));
  });
  test('a 1 kHz sine peaks in the band that covers 1 kHz', () {
    final e = AudioEngine(bandCount: 16);
    feed(e, sine(1000, 0.5, 1));
    final f = e.latest;
    expect(f.bands.length, 16);
    expect(argmax(f.bands), e.bandOf(1000));
    expect(f.bands[argmax(f.bands)], greaterThan(0.9));
    // Far-away bands stay dark.
    expect(f.bands[0], lessThan(0.2));
    expect(f.dominantHz, closeTo(1000, 10));
    expect(f.silent, isFalse);
  });

  test('low and high tones land in low and high bands at any band count', () {
    for (final n in [8, 16, 32]) {
      final e = AudioEngine(bandCount: n);
      feed(e, sine(80, 0.5, 0.8));
      final low = argmax(e.latest.bands);
      // Bass bands narrower than an FFT bin share its main lobe.
      expect(low, closeTo(e.bandOf(80), n > 16 ? 1 : 0), reason: '$n bands');
      feed(e, sine(5000, 0.5, 0.8));
      final high = argmax(e.latest.bands);
      expect(high, e.bandOf(5000), reason: '$n bands');
      expect(high, greaterThan(low));
    }
  });

  test('bass-heavy range spreads the low end over more bands', () {
    final full = AudioEngine()..range = 1;
    final bass = AudioEngine()..range = 0;
    expect(bass.bandOf(500), greaterThan(full.bandOf(500)));
    expect(bass.bandOf(10000), -1);
  });

  test('gain control makes quiet and loud rooms look alike', () {
    final quiet = AudioEngine(), loud = AudioEngine();
    feed(quiet, sine(440, 0.02, 1.5));
    feed(loud, sine(440, 0.8, 1.5));
    final q = quiet.latest, l = loud.latest;
    expect(q.bands[argmax(q.bands)], closeTo(l.bands[argmax(l.bands)], 0.1));
    expect(q.level, greaterThan(0.7));
    expect(l.level, greaterThan(0.7));
    // The raw input meter still tells them apart.
    expect(l.inputDb - q.inputDb, closeTo(32, 1.5));
  });

  test('gain control recovers after a loud passage', () {
    final e = AudioEngine();
    feed(e, sine(440, 0.9, 1));
    feed(e, sine(440, 0.05, 0.3));
    final ducked = e.latest.bands[argmax(e.latest.bands)];
    feed(e, sine(440, 0.05, 8));
    final recovered = e.latest.bands[argmax(e.latest.bands)];
    expect(recovered, greaterThan(ducked));
    expect(recovered, greaterThan(0.9));
  });

  test('silence goes quiet: no bands, no beats, flagged silent', () {
    final e = AudioEngine();
    feed(e, sine(440, 0.5, 0.5));
    // Cutting a tone off is itself a click; only the silence after counts.
    final beats = feed(e, List.filled(sr * 2, 0.0)).where((t) => t > 0.8);
    final f = e.latest;
    expect(f.silent, isTrue);
    expect(f.bands.every((b) => b < 0.05), isTrue);
    expect(f.level, lessThan(0.05));
    expect(f.dominantHz, 0);
    expect(beats, isEmpty);
  });

  test('pink noise lights most bands without a stream of fake beats', () {
    final e = AudioEngine(bandCount: 16);
    final beats = feed(e, pink(0.3, 4));
    final f = e.latest;
    expect(f.silent, isFalse);
    expect(f.bands.where((b) => b > 0.4).length, greaterThan(10));
    expect(beats.length, lessThan(4));
  });

  test('kick drums are detected on time and give the tempo', () {
    final e = AudioEngine();
    const bpm = 120.0;
    final beats = feed(e, kicks(bpm, 6.2));
    final expected = [for (var t = 0.5; t < 6.0; t += 60 / bpm) t];
    expect(beats.length, inInclusiveRange(expected.length - 1, expected.length));
    for (final b in beats) {
      final nearest = expected.reduce((a, c) => (c - b).abs() < (a - b).abs() ? c : a);
      // Detection lands within ~2 hops of the hit (window lag included).
      expect(b - nearest, inInclusiveRange(0.0, 0.07), reason: 'beat at $b');
    }
    expect(e.latest.bpm, closeTo(bpm, 4));
    expect(e.latest.beatCount, beats.length);
  });

  test('kicks still come through over a noisy bed', () {
    final e = AudioEngine();
    final k = kicks(124, 8), bed = pink(0.12, 8);
    final beats = feed(e, [for (var i = 0; i < k.length; i++) k[i] + bed[i]]);
    final expected = [for (var t = 0.5; t < 7.8; t += 60 / 124) t];
    final hits = expected.where((t) => beats.any((b) => b - t >= 0 && b - t < 0.07));
    expect(hits.length, greaterThanOrEqualTo((expected.length * 0.8).floor()));
    expect(beats.length - hits.length, lessThanOrEqualTo(2), reason: 'false beats');
    expect(e.latest.bpm, closeTo(124, 4));
  });

  test('a steady tone is not a beat', () {
    final e = AudioEngine();
    final beats = feed(e, sine(60, 0.6, 3));
    expect(beats.length, lessThanOrEqualTo(1)); // the onset itself may count
  });

  test('PCM16 bytes split at odd offsets decode like float samples', () {
    final samples = sine(700, 0.4, 0.5);
    final bytes = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(i * 2, (samples[i] * 32767).round(), Endian.little);
    }
    final raw = bytes.buffer.asUint8List();
    final a = AudioEngine(), b = AudioEngine();
    feed(a, samples);
    for (var i = 0; i < raw.length; i += 777) {
      b.addPcm16(Uint8List.sublistView(raw, i, min(i + 777, raw.length)));
    }
    expect(b.latest.dominantHz, closeTo(a.latest.dominantHz, 1));
    expect(argmax(b.latest.bands), argmax(a.latest.bands));
  });

  test('wave is normalised and follows the signal', () {
    final e = AudioEngine();
    feed(e, sine(220, 0.05, 1));
    final w = e.latest.wave;
    expect(w.length, greaterThan(16));
    expect(w.reduce(max), greaterThan(0.7));
    expect(w.reduce(min), lessThan(-0.7));
  });

  group('lifecycle', () {
    test('an interrupted stream stops native capture before a retry starts', () async {
      final src = FakePcmSource();
      final e = AudioEngine(source: src, permission: FakeMicPermission(MicAccess.granted));
      await e.acquire('screen');
      src.addSine(1000, 0.5, 0.1);
      await pumpEventQueue();
      expect(e.latest.bands, isNotEmpty);
      src.fail();
      await pumpEventQueue();
      expect(e.status, AudioStatus.failed);
      expect(src.running, false);
      expect(e.latest.bands, isEmpty);
      await e.acquire('retry');
      expect(src.running, true);
      expect(e.status, AudioStatus.listening);
      await e.release('screen');
      await e.release('retry');
      e.dispose();
    });

    test('runs while held, stops when released', () async {
      final src = FakePcmSource();
      final e = AudioEngine(source: src, permission: FakeMicPermission(MicAccess.granted));
      await e.acquire('screen');
      expect(e.status, AudioStatus.listening);
      expect(src.running, isTrue);
      await e.acquire('playback');
      await e.release('screen');
      expect(src.running, isTrue);
      await e.release('playback');
      expect(e.status, AudioStatus.off);
      expect(src.running, isFalse);
      expect(e.latest.bands, isEmpty);
    });

    test('streamed PCM reaches the features', () async {
      final src = FakePcmSource();
      final e = AudioEngine(source: src, permission: FakeMicPermission(MicAccess.granted));
      await e.acquire('t');
      src.addSine(1000, 0.5, 0.5);
      await pumpEventQueue();
      expect(e.latest.dominantHz, closeTo(1000, 10));
      await e.release('t');
    });

    test('asks for permission, then starts', () async {
      final perm = FakeMicPermission(MicAccess.denied, onRequest: MicAccess.granted);
      final e = AudioEngine(source: FakePcmSource(), permission: perm);
      await e.acquire('t');
      expect(e.status, AudioStatus.needsPermission);
      await e.requestPermission();
      expect(e.status, AudioStatus.listening);
      await e.release('t');
    });

    test('a blocked mic points at settings and recovers on refresh', () async {
      final perm = FakeMicPermission(MicAccess.denied, onRequest: MicAccess.blocked);
      final e = AudioEngine(source: FakePcmSource(), permission: perm);
      await e.acquire('t');
      await e.requestPermission();
      expect(e.status, AudioStatus.blocked);
      await e.openSettings();
      expect(perm.openedSettings, isTrue);
      perm.access = MicAccess.granted;
      await e.refreshPermission();
      expect(e.status, AudioStatus.listening);
      await e.release('t');
    });

    test('a failing source reports an error', () async {
      final e = AudioEngine(
        source: FakePcmSource(failOnStart: true),
        permission: FakeMicPermission(MicAccess.granted),
      );
      await e.acquire('t');
      expect(e.status, AudioStatus.failed);
      expect(e.error, isNotNull);
      // A later release still settles cleanly.
      await e.release('t');
      expect(e.status, AudioStatus.off);
      unawaited(Future.value());
    });
  });
}
