// Streams a generator to a WLED over DDP, then hands the device back.
//
//   dart run tool/stream_smoke.dart <host> [generator=plasma] [seconds=5] [fps=40]
import 'dart:async';
import 'dart:io';

import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/wled/ddp.dart';
import 'package:glyph/wled/layout.dart';
import 'package:glyph/wled/wled_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
        'usage: dart run tool/stream_smoke.dart <host> [generator] [seconds] [fps]');
    stderr.writeln('generators: ${generators.map((g) => g.id).join(', ')}');
    exit(64);
  }
  final host = args[0];
  final gen = generatorById(args.length > 1 ? args[1] : 'plasma');
  final seconds = args.length > 2 ? double.parse(args[2]) : 5.0;
  final fps = args.length > 3 ? int.parse(args[3]) : 40;

  final client = WledClient(host);
  final info = await client.info();
  final caps = await client.capabilities();
  stdout.writeln('${info.name} ${info.version} ${info.arch}, ${info.ledCount} LEDs, '
      'matrix ${caps.width}x${caps.height}, rssi ${info.rssi}, '
      'gifs ${caps.canPlayGifs} (Image fx ${caps.imageEffectId})');
  if (!caps.canStream) {
    stderr.writeln('Realtime/UDP receive appears disabled on the device.');
  }

  final frame = Frame(caps.width, caps.height);
  final effect = gen.create(frame.width, frame.height, 1);
  final params = Params.defaultsFor(gen);
  final palette = paletteById(gen.defaultPalette);
  const layout = MatrixLayout();

  final sender = DdpSender(host);
  await sender.open();
  stdout.writeln('Streaming ${gen.name} at $fps fps for ${seconds}s…');

  final clock = Stopwatch()..start();
  var last = 0.0;
  final done = Completer<void>();
  final timer = Timer.periodic(Duration(microseconds: 1000000 ~/ fps), (t) {
    final now = clock.elapsedMicroseconds / 1e6;
    if (now >= seconds) {
      t.cancel();
      done.complete();
      return;
    }
    effect.render(frame, now, now - last, params, palette);
    last = now;
    sender.send(layout.apply(frame));
  });
  await done.future;
  timer.cancel();
  sender.close();

  final elapsed = clock.elapsedMilliseconds / 1000;
  stdout.writeln('frames sent ${sender.framesSent}, errors ${sender.errors}, '
      '${(sender.framesSent / elapsed).toStringAsFixed(1)} fps');

  // Let in-flight packets land before leaving realtime mode.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await client.exitLive();
  final after = await client.info();
  stdout.writeln('live after exit: ${after.isLive}');
  client.close();
}
