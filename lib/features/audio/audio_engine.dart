import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// One snapshot of what the microphone hears, already gain-normalised so
/// visualisers can map values straight to pixels.
@immutable
class AudioFeatures {
  const AudioFeatures({
    required this.bands,
    required this.wave,
    this.level = 0,
    this.bass = 0,
    this.mid = 0,
    this.treble = 0,
    this.beat = false,
    this.beatCount = 0,
    this.beatStrength = 0,
    this.bpm = 0,
    this.dominantHz = 0,
    this.inputDb = -120,
    this.silent = true,
    this.time = 0,
  });

  /// 0..1 per log-spaced band, lowest frequency first.
  final Float32List bands;

  /// Recent waveform, -1..1 after gain control, triggered on a rising edge.
  final Float32List wave;

  final double level, bass, mid, treble;

  /// A beat landed since the previous snapshot. Renderers that run at a
  /// different rate should compare [beatCount] instead.
  final bool beat;
  final int beatCount;
  final double beatStrength;

  /// Tempo estimate, 0 until a few beats have been heard.
  final double bpm;
  final double dominantHz;

  /// Raw input RMS in dBFS, before any gain control. Drives the input meter.
  final double inputDb;
  final bool silent;

  /// Seconds of audio analysed so far.
  final double time;

  static final silence = AudioFeatures(bands: Float32List(0), wave: Float32List(0));

  /// Band value at [u] (0 = lowest band, 1 = highest), interpolated so any
  /// matrix width can sample any band count.
  double band(double u) => _sample(bands, u);

  double waveAt(double u) => _sample(wave, u);

  static double _sample(Float32List a, double u) {
    if (a.isEmpty) return 0;
    if (a.length == 1) return a[0];
    final x = u.clamp(0.0, 1.0) * (a.length - 1);
    final i = x.floor().clamp(0, a.length - 2);
    final f = x - i;
    return a[i] + (a[i + 1] - a[i]) * f;
  }
}

/// Anything that can hand a visualiser the latest [AudioFeatures].
abstract interface class AudioFeed {
  AudioFeatures get latest;
}

/// Delivers little-endian PCM16 mono chunks. Injectable so tests never touch
/// a real microphone.
abstract interface class PcmSource {
  Future<Stream<Uint8List>> start(int sampleRate);
  Future<void> stop();
}

/// Streams the phone microphone. Nothing is written to disk: `record` hands
/// over raw PCM in memory and we only ever analyse it.
class MicSource implements PcmSource {
  AudioRecorder? _rec;

  @override
  Future<Stream<Uint8List>> start(int sampleRate) {
    final rec = _rec ??= AudioRecorder();
    return rec.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        // Voice processing squashes music, so take the signal as-is.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        // `pause` would grab audio focus and stop music playing on this phone.
        audioInterruption: AudioInterruptionMode.none,
        // Bluetooth SCO would drop a headset to call quality.
        androidConfig: const AndroidRecordConfig(
          manageBluetooth: false,
          audioSource: AndroidAudioSource.mic,
        ),
        iosConfig: const IosRecordConfig(
          categoryOptions: [
            IosAudioCategoryOption.mixWithOthers,
            IosAudioCategoryOption.defaultToSpeaker,
            IosAudioCategoryOption.allowBluetoothA2DP,
          ],
        ),
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _rec?.stop();
  }
}

enum MicAccess { unknown, granted, denied, blocked }

abstract interface class MicPermission {
  Future<MicAccess> check();
  Future<MicAccess> request();
  Future<void> openSettings();
}

class SystemMicPermission implements MicPermission {
  const SystemMicPermission();

  static MicAccess _map(PermissionStatus s) => switch (s) {
    PermissionStatus.granted ||
    PermissionStatus.limited ||
    PermissionStatus.provisional => MicAccess.granted,
    PermissionStatus.permanentlyDenied || PermissionStatus.restricted => MicAccess.blocked,
    PermissionStatus.denied => MicAccess.denied,
  };

  @override
  Future<MicAccess> check() async => _map(await Permission.microphone.status);

  @override
  Future<MicAccess> request() async => _map(await Permission.microphone.request());

  @override
  Future<void> openSettings() => openAppSettings();
}

enum AudioStatus { off, needsPermission, blocked, starting, listening, failed }

/// Mic capture → Hann-windowed FFT → log bands with gain control, smoothing
/// and beat tracking. Runs while at least one owner holds it (the screen for
/// previews, playback while a visualiser streams).
class AudioEngine extends ChangeNotifier implements AudioFeed {
  AudioEngine({
    PcmSource? source,
    MicPermission? permission,
    this.sampleRate = 44100,
    int bandCount = 16,
  }) : _source = source ?? MicSource(),
       _permission = permission ?? const SystemMicPermission(),
       _bandCount = bandCount.clamp(1, 128) {
    for (var i = 0; i < fftSize; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (fftSize - 1));
    }
    _planBands();
  }

  static AudioEngine? _shared;

  /// The app-wide engine; the mic is a single resource.
  static AudioEngine get shared => _shared ??= AudioEngine();

  static const fftSize = 2048;
  static const hop = 512;
  static const _waveLen = 64;
  static const _historyLen = 86; // ~1 s of onset values at 44.1 kHz.

  final int sampleRate;
  final PcmSource _source;
  final MicPermission _permission;

  // ---- Lifecycle -----------------------------------------------------------

  AudioStatus _status = AudioStatus.off;
  MicAccess _access = MicAccess.unknown;
  String? _error;
  final _holders = <Object>{};
  StreamSubscription<Uint8List>? _sub;
  Future<void> _op = Future.value();

  AudioStatus get status => _status;
  MicAccess get access => _access;
  String? get error => _error;
  bool get isListening => _status == AudioStatus.listening;
  bool isHeldBy(Object owner) => _holders.contains(owner);

  final _features = ValueNotifier<AudioFeatures>(AudioFeatures.silence);
  ValueListenable<AudioFeatures> get features => _features;
  @override
  AudioFeatures get latest => _features.value;

  /// Starts listening on behalf of [owner] (if the mic is allowed).
  Future<void> acquire(Object owner) {
    _holders.add(owner);
    return _sync();
  }

  Future<void> release(Object owner) {
    _holders.remove(owner);
    return _sync();
  }

  /// Shows the system prompt, then starts if anyone is waiting.
  Future<void> requestPermission() async {
    _access = await _permission.request();
    _status = _statusForAccess();
    notifyListeners();
    await _sync();
  }

  /// Re-reads the permission, e.g. after returning from system settings.
  Future<void> refreshPermission() async {
    _access = await _permission.check();
    await _sync();
  }

  Future<void> openSettings() => _permission.openSettings();

  AudioStatus _statusForAccess() => switch (_access) {
    MicAccess.blocked => AudioStatus.blocked,
    MicAccess.granted => _status,
    _ => AudioStatus.needsPermission,
  };

  // Serialised so quick acquire/release pairs can't interleave start/stop.
  Future<void> _sync() => _op = _op.then((_) => _apply()).catchError((Object e) {
    _fail(e);
  });

  Future<void> _apply() async {
    if (_holders.isEmpty) {
      if (_sub != null) await _stopCapture();
      if (_status != AudioStatus.off) _setStatus(AudioStatus.off);
      return;
    }
    if (_sub != null) return;
    if (_access != MicAccess.granted) _access = await _permission.check();
    if (_access != MicAccess.granted) {
      _setStatus(_statusForAccess());
      return;
    }
    _setStatus(AudioStatus.starting);
    _reset();
    final stream = await _source.start(sampleRate);
    _sub = stream.listen(addPcm16, onError: _fail);
    _setStatus(AudioStatus.listening);
  }

  Future<void> _stopCapture() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _source.stop();
    } catch (_) {
      // Already stopped by the platform (e.g. interrupted); nothing to undo.
    }
    _features.value = AudioFeatures.silence;
  }

  void _fail(Object e) {
    _error = '$e';
    _sub?.cancel();
    _sub = null;
    _setStatus(AudioStatus.failed);
  }

  void _setStatus(AudioStatus s) {
    if (_status == s) return;
    _status = s;
    if (s != AudioStatus.failed) _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _holders.clear();
    _sub?.cancel();
    _source.stop().catchError((_) {});
    _features.dispose();
    super.dispose();
  }

  // ---- Settings ------------------------------------------------------------

  int _bandCount;
  double _sensitivity = 0.5, _smoothing = 0.5, _range = 0.7;

  int get bandCount => _bandCount;
  set bandCount(int n) {
    n = n.clamp(1, 128);
    if (n == _bandCount) return;
    _bandCount = n;
    _planBands();
    notifyListeners();
  }

  /// 0..1; shifts the display ±12 dB on top of automatic gain control.
  double get sensitivity => _sensitivity;
  set sensitivity(double v) {
    _sensitivity = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 0..1; how slowly bands fall back after a hit.
  double get smoothing => _smoothing;
  set smoothing(double v) {
    _smoothing = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 0 = bass-heavy (35 Hz–2.5 kHz), 1 = full range (35 Hz–16 kHz).
  double get range => _range;
  set range(double v) {
    _range = v.clamp(0.0, 1.0);
    _planBands();
    notifyListeners();
  }

  /// Input below this (dBFS RMS) for half a second counts as silence.
  double silenceDb = -58;

  /// Index of the band covering [hz], or -1 outside the current range.
  int bandOf(double hz) {
    final k = (hz / _binHz).round();
    for (var b = 0; b < _bandCount; b++) {
      final lo = _bandLo[b], hi = _bandHi[b];
      if (hi >= lo ? (k >= lo && k <= hi) : (hz / _binHz - _bandCentre[b]).abs() < 0.5) {
        return b;
      }
    }
    return -1;
  }

  // ---- Analysis state ------------------------------------------------------

  final _ring = Float64List(fftSize);
  final _hann = Float64List(fftSize);
  final _spec = Float64x2List(fftSize);
  final _mag = Float64List(fftSize ~/ 2 + 1);
  final _prevLog = Float64List(7 * _lag);
  final _fft = FFT(fftSize);
  final _onsets = Float64List(_historyLen);
  final _beatTimes = <double>[];

  Int32List _bandLo = Int32List(0), _bandHi = Int32List(0);
  Float64List _bandCentre = Float64List(0), _tilt = Float64List(0);
  Float64List _bands = Float64List(0), _raw = Float64List(0);
  final _wave = Float32List(_waveLen);

  int _pos = 0, _sinceHop = 0, _onsetN = 0, _beatCount = 0;
  int? _carry;
  double _hopSq = 0, _clock = 0, _quiet = 0;
  double _agc = 0, _agc3 = 0, _rmsAgc = 0, _waveAgc = 0;
  double _level = 0, _bass = 0, _mid = 0, _treble = 0;
  double _inputDb = -120, _lastBeat = -10, _beatStrength = 0, _bpm = 0;
  double _dominant = 0, _prevOnset = 0;
  bool _beatInChunk = false;

  double get _binHz => sampleRate / fftSize;
  double get _hopDt => hop / sampleRate;
  double get _sensDb => (_sensitivity - 0.5) * 24;

  void _planBands() {
    final n = _bandCount;
    final nyquist = sampleRate / 2 * 0.95;
    const lo = 35.0;
    final hi = math.min(nyquist, math.exp(_lerp(math.log(2500), math.log(16000), _range)));
    _bandLo = Int32List(n);
    _bandHi = Int32List(n);
    _bandCentre = Float64List(n);
    _tilt = Float64List(n);
    final old = _bands;
    _bands = Float64List(n);
    _raw = Float64List(n);
    if (old.length == n) _bands.setAll(0, old);
    for (var b = 0; b < n; b++) {
      final e0 = lo * math.pow(hi / lo, b / n);
      final e1 = lo * math.pow(hi / lo, (b + 1) / n);
      _bandLo[b] = (e0 / _binHz).ceil();
      _bandHi[b] = (e1 / _binHz).ceil() - 1;
      final fc = math.sqrt(e0 * e1);
      _bandCentre[b] = fc / _binHz;
      // Music rolls off with frequency; lift highs and tame lows a little so
      // the whole width moves.
      final tiltDb = (1.5 * math.log(fc / 1000) / math.ln2).clamp(-6.0, 6.0);
      _tilt[b] = math.pow(10, tiltDb / 20).toDouble();
    }
  }

  void _reset() {
    _ring.fillRange(0, _ring.length, 0);
    _prevLog.fillRange(0, _prevLog.length, 0);
    _onsets.fillRange(0, _onsets.length, 0);
    _bands.fillRange(0, _bands.length, 0);
    _beatTimes.clear();
    _pos = _sinceHop = _onsetN = 0;
    _carry = null;
    _hopSq = _clock = _quiet = 0;
    _agc = _agc3 = _rmsAgc = _waveAgc = 0;
    _level = _bass = _mid = _treble = 0;
    _inputDb = -120;
    _lastBeat = -10;
    _bpm = _dominant = _prevOnset = 0;
  }

  /// Feeds little-endian PCM16 mono bytes (the mic stream format).
  void addPcm16(Uint8List bytes) {
    var i = 0;
    final carry = _carry;
    if (carry != null && bytes.isNotEmpty) {
      _push((bytes[0] << 8 | carry).toSigned(16) / 32768);
      _carry = null;
      i = 1;
    }
    final data = ByteData.sublistView(bytes);
    for (; i + 1 < bytes.length; i += 2) {
      _push(data.getInt16(i, Endian.little) / 32768);
    }
    if (i < bytes.length) _carry = bytes[i];
    _publish();
  }

  /// Feeds float samples in -1..1; mainly for tests and synthetic input.
  void addSamples(List<double> samples) {
    for (final s in samples) {
      _push(s);
    }
    _publish();
  }

  void _push(double s) {
    _ring[_pos] = s;
    _pos = (_pos + 1) & (fftSize - 1);
    _hopSq += s * s;
    if (++_sinceHop >= hop) {
      _sinceHop = 0;
      _analyse();
    }
  }

  void _analyse() {
    const n = fftSize;
    for (var i = 0; i < n; i++) {
      _spec[i] = Float64x2(_ring[(_pos + i) & (n - 1)] * _hann[i], 0);
    }
    _fft.inPlaceFft(_spec);
    // Scaled so a full-scale sine peaks at ~1 in its bin.
    const scale = 4.0 / n;
    for (var k = 0; k < _mag.length; k++) {
      final c = _spec[k];
      _mag[k] = math.sqrt(c.x * c.x + c.y * c.y) * scale;
    }
    final dt = _hopDt;
    _clock += dt;

    final rms = math.sqrt(_hopSq / hop);
    _hopSq = 0;
    _inputDb = 20 * math.log(rms + 1e-9) / math.ln10;
    _quiet = _inputDb < silenceDb ? _quiet + dt : 0;
    final silent = _quiet > 0.5;
    final sensGain = math.pow(10, _sensDb / 20).toDouble();

    // Bands, with automatic gain control: instant attack, ~3 s release, and a
    // floor so a quiet room isn't amplified into noise.
    final raw = _raw;
    var peak = 0.0;
    for (var b = 0; b < _bandCount; b++) {
      final a = _bandAmp(b) * _tilt[b];
      raw[b] = a;
      if (a > peak) peak = a;
    }
    final release = math.exp(-dt / 3);
    final floor = 0.004 / sensGain;
    _agc = math.max(floor, peak > _agc ? peak : math.max(peak, _agc * release));

    final atk = math.exp(-dt / 0.012);
    final rel = math.exp(-dt / (0.05 + _smoothing * 0.45));
    double follow(double cur, double target) =>
        target + (cur - target) * (target > cur ? atk : rel);

    for (var b = 0; b < _bandCount; b++) {
      final target = silent ? 0.0 : _display(raw[b] / _agc, sensGain, 30);
      _bands[b] = follow(_bands[b], target);
    }

    final bass = _rangeAmp(35, 250), mid = _rangeAmp(250, 2000), treble = _rangeAmp(2000, 12000);
    final p3 = math.max(bass, math.max(mid, treble));
    _agc3 = math.max(floor, p3 > _agc3 ? p3 : math.max(p3, _agc3 * release));
    _bass = follow(_bass, silent ? 0 : _display(bass / _agc3, sensGain, 30));
    _mid = follow(_mid, silent ? 0 : _display(mid / _agc3, sensGain, 30));
    _treble = follow(_treble, silent ? 0 : _display(treble / _agc3, sensGain, 30));

    _rmsAgc = math.max(0.003 / sensGain, rms > _rmsAgc ? rms : _rmsAgc * release);
    final lvl = silent ? 0.0 : _display(rms / _rmsAgc, sensGain, 24);
    _level = lvl + (_level - lvl) * math.exp(-dt / (lvl > _level ? 0.03 : 0.3));

    _dominant = silent ? 0 : _peakFrequency(40, 5000);
    _waveform();
    _onset(silent);
  }

  static double _display(double ratio, double gain, double rangeDb) {
    final db = 20 * math.log(ratio * gain + 1e-9) / math.ln10;
    return ((db + rangeDb) / rangeDb).clamp(0.0, 1.0);
  }

  double _bandAmp(int b) {
    final lo = _bandLo[b], hi = math.min(_bandHi[b], _mag.length - 1);
    if (hi >= lo) {
      var e = 0.0;
      for (var k = lo; k <= hi; k++) {
        e += _mag[k] * _mag[k];
      }
      return math.sqrt(e);
    }
    // Narrower than one bin (deep bass): interpolate at the band centre.
    final x = _bandCentre[b].clamp(0.0, _mag.length - 1.001);
    final k = x.floor();
    return _mag[k] + (_mag[k + 1] - _mag[k]) * (x - k);
  }

  double _rangeAmp(double f0, double f1) {
    final k0 = (f0 / _binHz).ceil(), k1 = math.min((f1 / _binHz).floor(), _mag.length - 1);
    var e = 0.0;
    for (var k = k0; k <= k1; k++) {
      e += _mag[k] * _mag[k];
    }
    return math.sqrt(e);
  }

  double _peakFrequency(double f0, double f1) {
    final k0 = math.max(1, (f0 / _binHz).floor());
    final k1 = math.min(_mag.length - 2, (f1 / _binHz).ceil());
    var best = k0;
    for (var k = k0; k <= k1; k++) {
      if (_mag[k] > _mag[best]) best = k;
    }
    final a = _mag[best - 1], b = _mag[best], c = _mag[best + 1];
    final d = a - 2 * b + c;
    final p = d == 0 ? 0.0 : (0.5 * (a - c) / d).clamp(-0.5, 0.5);
    return (best + p) * _binHz;
  }

  void _waveform() {
    const n = fftSize, span = 1024;
    // Look for a rising zero crossing so the trace stands still on tones.
    var start = n - span;
    for (var i = n - span - 512; i < n - span; i++) {
      final a = _ring[(_pos + i) & (n - 1)], b = _ring[(_pos + i + 1) & (n - 1)];
      if (a <= 0 && b > 0) {
        start = i + 1;
        break;
      }
    }
    const per = span ~/ _waveLen;
    var peak = 0.0;
    for (var j = 0; j < _waveLen; j++) {
      var s = 0.0;
      for (var k = 0; k < per; k++) {
        s += _ring[(_pos + start + j * per + k) & (n - 1)];
      }
      s /= per;
      _wave[j] = s;
      if (s.abs() > peak) peak = s.abs();
    }
    _waveAgc = math.max(0.01, peak > _waveAgc ? peak : _waveAgc * math.exp(-_hopDt / 2));
    for (var j = 0; j < _waveLen; j++) {
      _wave[j] = (_wave[j] / _waveAgc).clamp(-1.0, 1.0);
    }
  }

  // Onset bands: aggregating bins keeps noise from looking like hits; low
  // bands weigh most because that's where kicks live.
  static const _onsetEdges = <double>[35, 120, 250, 500, 1000, 2000, 4000, 8000];
  static const _onsetWeights = [1.5, 1.2, 0.6, 0.4, 0.4, 0.3, 0.3];
  static const _lag = 3;

  // Spectral flux on log-compressed band energies (so it's gain invariant)
  // against an adaptive threshold over the last second.
  void _onset(bool silent) {
    final ref = math.max(_agc3, 1e-6);
    var onset = 0.0;
    final slot = _onsetN % _lag;
    for (var b = 0; b < _onsetWeights.length; b++) {
      final l = math.log(1 + 20 * _rangeAmp(_onsetEdges[b], _onsetEdges[b + 1]) / ref);
      // Rise over the last few hops: a hit climbs steadily as it fills the
      // window, while noise only jitters.
      var low = l;
      for (var j = 0; j < _lag; j++) {
        low = math.min(low, _prevLog[b * _lag + j]);
      }
      _prevLog[b * _lag + slot] = l;
      onset += (l - low) * _onsetWeights[b];
    }

    final filled = math.min(_onsetN, _historyLen);
    var mean = 0.0;
    for (var i = 0; i < filled; i++) {
      mean += _onsets[i];
    }
    mean = filled == 0 ? 0 : mean / filled;
    final threshold = 2.6 * mean + 0.1;

    if (!silent &&
        filled >= 20 &&
        onset > threshold &&
        onset >= _prevOnset &&
        _clock - _lastBeat > 0.28) {
      _lastBeat = _clock;
      _beatCount++;
      _beatInChunk = true;
      _beatStrength = (onset / threshold - 1).clamp(0.25, 1.0);
      _beatTimes.add(_clock);
      _beatTimes.removeWhere((t) => _clock - t > 8);
      _bpm = _estimateBpm();
    }
    if (_clock - _lastBeat > 4) _bpm = 0;
    _onsets[_onsetN % _historyLen] = onset;
    _onsetN++;
    _prevOnset = onset;
  }

  double _estimateBpm() {
    if (_beatTimes.length < 4) return _bpm;
    final gaps = [for (var i = 1; i < _beatTimes.length; i++) _beatTimes[i] - _beatTimes[i - 1]]
      ..sort();
    var bpm = 60 / gaps[gaps.length ~/ 2];
    while (bpm < 80) {
      bpm *= 2;
    }
    while (bpm > 170) {
      bpm /= 2;
    }
    return bpm;
  }

  void _publish() {
    if (_clock == 0) return;
    _features.value = AudioFeatures(
      bands: Float32List.fromList(_bands),
      wave: Float32List.fromList(_wave),
      level: _level,
      bass: _bass,
      mid: _mid,
      treble: _treble,
      beat: _beatInChunk,
      beatCount: _beatCount,
      beatStrength: _beatStrength,
      bpm: _bpm,
      dominantHz: _dominant,
      inputDb: _inputDb,
      silent: _quiet > 0.5,
      time: _clock,
    );
    _beatInChunk = false;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
