import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine/generator.dart';

import '../engine/gif_baker.dart';
import '../engine/palette.dart';
import '../engine/registry.dart';
import '../library/catalog.dart';
import 'scope.dart';

/// User-level operations that touch both playback and the device.
abstract final class GlyphActions {
  static Future<void> play(BuildContext context, LibraryItem item) async {
    final s = AppScope.of(context);
    s.playback.playItem(item);
    await ensureStreaming(context);
  }

  /// Starts streaming to the selected device if it's reachable.
  static Future<void> ensureStreaming(BuildContext context) async {
    final s = AppScope.of(context);
    final d = s.devices;
    if (!d.isConnected || d.selected == null || s.playback.isStreaming) return;
    final caps = d.caps!;
    s.playback.resize(caps.width, caps.height);
    try {
      // Clears a leftover realtime override, which would make WLED ignore DDP.
      await d.client!.prepareStream();
      await s.playback.startStreaming(d.selected!.host, d.selected!.layout);
    } catch (e) {
      if (context.mounted) _toast(context, 'Couldn\'t start streaming: $e');
    }
  }

  static Future<void> stopStreaming(BuildContext context) async {
    final s = AppScope.of(context);
    await s.playback.stopStreaming();
    try {
      await s.devices.client?.exitLive();
    } catch (_) {
      // WLED drops out of live mode on its own after the realtime timeout.
    }
  }

  /// Renders the current animation to a GIF on a background isolate, uploads
  /// it and saves it as a preset so it plays without the phone.
  static Future<String?> saveToDevice(BuildContext context) async {
    final s = AppScope.of(context);
    final d = s.devices;
    final caps = d.caps, client = d.client;
    final g = s.playback.generator;
    if (caps == null || client == null || g == null) return null;
    if (!caps.canPlayGifs) {
      return _report(context, 'This controller can\'t play GIFs. Live streaming still works.');
    }

    final title = s.playback.item?.title ?? g.name;
    final genId = g.id;
    final params = s.playback.params;
    final paletteId = s.playback.palette.id;
    final w = caps.width, h = caps.height;
    final speed = s.playback.timeScale;

    try {
      // compute() with a top-level function avoids capturing BuildContext.
      final bytes = await compute(_bake, (genId, params.toMap(), paletteId, w, h, speed));
      if (!caps.fitsFile(bytes.length)) {
        return context.mounted ? _report(context, 'Not enough space on the controller.') : null;
      }
      if (!context.mounted) return null;
      await stopStreaming(context);
      final presetId = await client.saveGifToDevice(
        fileName: '${_slug(title)}.gif',
        gif: bytes,
        presetName: title,
        caps: caps,
      );
      await d.refresh();
      final kb = (bytes.length / 1024).toStringAsFixed(1);
      return context.mounted
          ? _report(context, 'Saved as preset $presetId ($kb KB). It now plays without your phone.')
          : null;
    } catch (e) {
      return context.mounted ? _report(context, 'Save failed: $e') : null;
    }
  }

  static String _report(BuildContext context, String msg) {
    _toast(context, msg);
    return msg;
  }

  static String _slug(String s) {
    final slug = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    // LittleFS paths on WLED are short; keep names well under the limit.
    return slug.length > 24 ? slug.substring(0, 24) : slug;
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }
}

Uint8List _bake((String, Map<String, double>, String, int, int, double) a) {
  final (genId, params, paletteId, w, h, speed) = a;
  return bakeGif(
    generator: generatorById(genId),
    params: Params(params),
    palette: paletteById(paletteId),
    width: w,
    height: h,
    timeScale: speed,
  ).bytes;
}
