import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/gif_encoder.dart';

/// Frame delays (centiseconds) from a GIF's Graphic Control Extensions.
List<int> _delays(List<int> b) => [
      for (var i = 0; i + 5 < b.length; i++)
        if (b[i] == 0x21 && b[i + 1] == 0xF9 && b[i + 2] == 4) b[i + 4] | (b[i + 5] << 8),
    ];

void main() {
  // WLED carries a frame's wait over to the next GIF it opens, so a long
  // frame on the device would blank whatever plays next.
  test('device GIFs never hold a frame longer than 1 s', () {
    final a = Frame(4, 4)..fill(0xFF0000), b = Frame(4, 4)..fill(0x00FF00);
    final gif = encodeGif([a, b, b, b, b], [5, 60000, 50, 50, 50], forLeds: true);
    expect(_delays(gif).every((d) => d <= deviceMaxFrameCs), isTrue);
  });

  test('share GIFs keep their exact timing', () {
    final a = Frame(4, 4)..fill(0xFF0000), b = Frame(4, 4)..fill(0x00FF00);
    expect(_delays(encodeGif([a, b], [5, 6000])), contains(6000));
  });
}
