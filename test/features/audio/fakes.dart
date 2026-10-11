import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:glyph/features/audio/audio_engine.dart';

class FakePcmSource implements PcmSource {
  FakePcmSource({this.failOnStart = false});

  final bool failOnStart;
  StreamController<Uint8List>? _ctrl;
  bool get running => _ctrl != null;

  @override
  Future<Stream<Uint8List>> start(int sampleRate) async {
    if (failOnStart) throw StateError('no mic');
    _ctrl = StreamController<Uint8List>();
    return _ctrl!.stream;
  }

  @override
  Future<void> stop() async {
    await _ctrl?.close();
    _ctrl = null;
  }

  void addSamples(List<double> s) {
    final b = ByteData(s.length * 2);
    for (var i = 0; i < s.length; i++) {
      b.setInt16(i * 2, (s[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    _ctrl?.add(b.buffer.asUint8List());
  }

  void fail() => _ctrl?.addError(StateError('capture interrupted'));

  void addSine(double hz, double amp, double seconds, {int sampleRate = 44100}) => addSamples([
    for (var i = 0; i < (seconds * sampleRate).round(); i++)
      amp * sin(2 * pi * hz * i / sampleRate),
  ]);
}

class FakeMicPermission implements MicPermission {
  FakeMicPermission(this.access, {MicAccess? onRequest}) : onRequest = onRequest ?? access;

  MicAccess access;
  MicAccess onRequest;
  bool openedSettings = false;

  @override
  Future<MicAccess> check() async => access;

  @override
  Future<MicAccess> request() async => access = onRequest;

  @override
  Future<void> openSettings() async => openedSettings = true;
}

/// A feed with hand-set features, for driving visualisers directly.
class FixedFeed implements AudioFeed {
  FixedFeed(this.latest);

  @override
  AudioFeatures latest;
}
