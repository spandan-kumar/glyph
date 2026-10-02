import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/ddp.dart';

void main() {
  test('packet header', () {
    final p = buildDdpPacket(Uint8List.fromList([9, 8, 7]),
        offset: 0x01020304, sequence: 5, push: true);
    expect(p, [0x41, 5, 0x0B, 0x01, 1, 2, 3, 4, 0, 3, 9, 8, 7]);

    final q = buildDdpPacket(Uint8List(2), offset: 0, sequence: 0x1F, push: false);
    expect(q.sublist(0, 10), [0x40, 0x0F, 0x0B, 0x01, 0, 0, 0, 0, 0, 2]);
  });

  test('32x32 frame splits into 1440/1440/192 with push on last only', () {
    final rgb = Uint8List.fromList(List.generate(32 * 32 * 3, (i) => i & 0xFF));
    final packets = buildDdpFrame(rgb, 7);
    expect(packets.map((p) => p.length - ddpHeaderLength), [1440, 1440, 192]);

    int offsetOf(Uint8List p) => ByteData.sublistView(p).getUint32(4);
    int lengthOf(Uint8List p) => ByteData.sublistView(p).getUint16(8);
    expect(packets.map(offsetOf), [0, 1440, 2880]);
    expect(packets.map(lengthOf), [1440, 1440, 192]);
    expect(packets.map((p) => p[0]), [0x40, 0x40, 0x41]);
    expect(packets.map((p) => p[1]), [7, 7, 7]);

    final joined = [for (final p in packets) ...p.sublist(ddpHeaderLength)];
    expect(joined, rgb);
  });

  test('16x16 frame is a single push packet', () {
    final packets = buildDdpFrame(Uint8List(768), 1);
    expect(packets, hasLength(1));
    expect(packets.single[0], 0x41);
    expect(packets.single.length, 778);
  });

  test('sender delivers packets and cycles sequence 1..15', () async {
    final rx = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final got = <Uint8List>[];
    final sub = rx.listen((e) {
      if (e == RawSocketEvent.read) {
        final d = rx.receive();
        if (d != null) got.add(d.data);
      }
    });

    final sender = DdpSender('127.0.0.1', port: rx.port);
    sender.send(Uint8List(3)); // not open: ignored, no throw
    expect(sender.isOpen, isFalse);
    await sender.open();
    expect(sender.isOpen, isTrue);

    final frame = Uint8List(32 * 32 * 3);
    for (var i = 0; i < 16; i++) {
      sender.send(frame);
    }
    for (var i = 0; i < 50 && got.length < 48; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    sender.close();
    await sub.cancel();
    rx.close();

    expect(sender.framesSent, 16);
    expect(sender.errors, 0);
    expect(got, hasLength(48));
    final seqs = [for (var i = 0; i < got.length; i += 3) got[i][1]];
    expect(seqs, [for (var i = 0; i < 16; i++) i % 15 + 1]);
    expect(got.last[0], 0x41);
    expect(sender.isOpen, isFalse);
    sender.send(frame); // closed: ignored, no throw
  });
}
