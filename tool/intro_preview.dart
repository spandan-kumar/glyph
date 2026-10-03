// Previews the Glyph intro.
//
//   dart run tool/intro_preview.dart --gif out.gif     # LED-style preview GIF
//   dart run tool/intro_preview.dart --stream <host>   # play it on a device
import 'dart:io';
import 'dart:typed_data';

import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/generators/intro.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/wled/ddp.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:image/image.dart' as img;

const fps = 30;

List<Frame> render() {
  final g = GlyphIntro();
  final inst = g.create(16, 16, 1);
  final frames = <Frame>[];
  final n = ((GlyphIntro.duration + 1.0) * fps).round();
  for (var i = 0; i < n; i++) {
    final f = Frame(16, 16);
    inst.render(f, i / fps, 1 / fps, Params({}), palettes.first);
    frames.add(f);
  }
  return frames;
}

img.Image led(Frame f, {int cell = 20}) {
  final im = img.Image(width: 16 * cell, height: 16 * cell, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(8, 7, 6, 255));
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      final c = f.get(x, y);
      final r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
      final on = r + g + b > 20;
      img.fillCircle(im,
          x: x * cell + cell ~/ 2, y: y * cell + cell ~/ 2, radius: (cell * 0.4).round(),
          color: on ? img.ColorRgba8(r, g, b, 255) : img.ColorRgba8(29, 26, 23, 255), antialias: true);
    }
  }
  return im;
}

Future<void> main(List<String> args) async {
  final frames = render();
  if (args.first == '--gif') {
    final anim = led(frames.first)..frameDuration = 1000 ~/ fps;
    for (final f in frames.skip(1)) {
      anim.addFrame(led(f)..frameDuration = 1000 ~/ fps);
    }
    File(args[1]).writeAsBytesSync(img.encodeGif(anim, repeat: 0));
    File('${args[1]}.last.png').writeAsBytesSync(img.encodePng(led(frames.last)));
    stdout.writeln('${frames.length} frames → ${args[1]}');
  } else {
    final host = args[1];
    final client = WledClient(host);
    await client.prepareStream();
    final s = DdpSender(host);
    await s.open();
    final sw = Stopwatch()..start();
    for (var i = 0; i < frames.length; i++) {
      while (sw.elapsedMicroseconds < i * 1000000 ~/ fps) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      s.send(Uint8List.fromList(frames[i].rgb));
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    s.close();
    await client.exitLive();
    stdout.writeln('streamed ${frames.length} frames to $host');
  }
}
