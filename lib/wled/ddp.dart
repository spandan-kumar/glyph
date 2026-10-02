import 'dart:io';
import 'dart:typed_data';

// Distributed Display Protocol (http://www.3waylabs.com/ddp/) as received by
// WLED (wled00/e131.cpp handleDDPPacket). WLED renders on the push flag, or on
// every packet until it has seen one.

const ddpPort = 4048;
const ddpHeaderLength = 10;

/// 480 RGB pixels; the same chunk size WLED uses for its own DDP output
/// (DDP_CHANNELS_PER_PACKET in wled00/udp.cpp) and safely under a 1500 MTU.
const ddpMaxPayload = 1440;

const _flagVersion1 = 0x40;
const _flagPush = 0x01;
const _typeRgb8 = 0x0B; // RGB, 8 bits per channel
const _destDisplay = 0x01;

/// One DDP packet carrying [rgb] at byte [offset] of the frame.
Uint8List buildDdpPacket(Uint8List rgb,
    {required int offset, required int sequence, required bool push}) {
  final out = Uint8List(ddpHeaderLength + rgb.length);
  _writePacket(out, rgb, 0, rgb.length, offset, sequence, push);
  return out;
}

/// Splits a whole frame into packets of at most [ddpMaxPayload] bytes. All
/// packets share [sequence]; only the last one carries the push flag.
List<Uint8List> buildDdpFrame(Uint8List rgb, int sequence) {
  final packets = <Uint8List>[];
  for (var off = 0; off < rgb.length || packets.isEmpty; off += ddpMaxPayload) {
    final len = (rgb.length - off).clamp(0, ddpMaxPayload);
    packets.add(buildDdpPacket(Uint8List.sublistView(rgb, off, off + len),
        offset: off,
        sequence: sequence,
        push: off + len >= rgb.length));
  }
  return packets;
}

void _writePacket(Uint8List out, Uint8List src, int start, int len, int offset,
    int sequence, bool push) {
  out[0] = _flagVersion1 | (push ? _flagPush : 0);
  out[1] = sequence & 0x0F;
  out[2] = _typeRgb8;
  out[3] = _destDisplay;
  out[4] = (offset >> 24) & 0xFF;
  out[5] = (offset >> 16) & 0xFF;
  out[6] = (offset >> 8) & 0xFF;
  out[7] = offset & 0xFF;
  out[8] = (len >> 8) & 0xFF;
  out[9] = len & 0xFF;
  out.setRange(ddpHeaderLength, ddpHeaderLength + len, src, start);
}

/// Streams frames to one WLED over UDP. Packet buffers are reused between
/// frames, and send failures (weak Wi‑Fi, network switch) are counted, never
/// thrown, so a render loop can keep calling [send].
class DdpSender {
  DdpSender(this.host, {this.port = ddpPort});

  final String host;
  final int port;

  RawDatagramSocket? _socket;
  InternetAddress? _address;
  int _sequence = 0;
  int _framesSent = 0;
  int _errors = 0;
  final _buffers = <Uint8List>[];

  bool get isOpen => _socket != null;
  int get framesSent => _framesSent;

  /// Frames that were dropped entirely or partially.
  int get errors => _errors;

  Future<void> open() async {
    if (_socket != null) return;
    final address = InternetAddress.tryParse(host) ??
        (await InternetAddress.lookup(host)).first;
    final socket = await RawDatagramSocket.bind(
        address.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0);
    socket.readEventsEnabled = false;
    // Async socket errors surface on the stream; count them instead of
    // letting them become unhandled.
    socket.listen((_) {}, onError: (Object _) => _errors++);
    _address = address;
    _socket = socket;
  }

  void send(Uint8List rgb) {
    final socket = _socket, address = _address;
    if (socket == null || address == null) return;
    _sequence = _sequence % 15 + 1;
    final count = rgb.isEmpty ? 1 : (rgb.length + ddpMaxPayload - 1) ~/ ddpMaxPayload;
    var ok = true;
    for (var i = 0; i < count; i++) {
      final off = i * ddpMaxPayload;
      final len = (rgb.length - off).clamp(0, ddpMaxPayload);
      final buf = _buffer(i, len);
      _writePacket(buf, rgb, off, len, off, _sequence, i == count - 1);
      try {
        if (socket.send(buf, address, port) == 0) ok = false;
      } on SocketException {
        ok = false;
      } on OSError {
        ok = false;
      }
    }
    if (ok) {
      _framesSent++;
    } else {
      _errors++;
    }
  }

  Uint8List _buffer(int index, int payloadLength) {
    final size = ddpHeaderLength + payloadLength;
    if (index < _buffers.length) {
      if (_buffers[index].length != size) _buffers[index] = Uint8List(size);
      return _buffers[index];
    }
    final b = Uint8List(size);
    _buffers.add(b);
    return b;
  }

  void close() {
    _socket?.close();
    _socket = null;
  }
}
