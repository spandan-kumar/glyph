import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine/generator.dart';

import '../engine/clip.dart';
import '../engine/frame.dart';
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

  /// Plays a fixed clip (drawing, import, text) and streams it if possible.
  static Future<void> playClip(BuildContext context, FrameClip clip, String title) async {
    AppScope.of(context).playback.playGenerator(ClipGenerator(clip, title: title));
    await ensureStreaming(context);
  }

  /// Saves whatever is playing so it runs on the matrix without the phone.
  /// Library effects bake on a background isolate; clips encode their own
  /// frames; anything else (games, audio) is recorded for 4 s.
  static Future<String?> saveToDevice(BuildContext context) async {
    final s = AppScope.of(context);
    final caps = s.devices.caps;
    final g = s.playback.generator;
    if (caps == null || g == null) return null;
    final title = s.playback.item?.title ?? g.name;
    final w = caps.width, h = caps.height;

    if (g is ClipGenerator) {
      return saveClipToDevice(context, g.clip, title);
    }
    final Future<Uint8List> bytes;
    if (generators.any((x) => x.id == g.id)) {
      // compute() with a top-level function avoids capturing BuildContext.
      bytes = compute(_bake, (
        g.id,
        s.playback.params.toMap(),
        s.playback.palette.id,
        w,
        h,
        s.playback.timeScale,
      ));
    } else {
      final frames = renderFrames(
        generator: g,
        params: s.playback.params,
        palette: s.playback.palette,
        width: w,
        height: h,
        timeScale: s.playback.timeScale,
      );
      bytes = compute(_encodeFrames, (frames, 20));
    }
    return _upload(context, title, bytes);
  }

  static Future<String?> saveClipToDevice(
      BuildContext context, FrameClip clip, String title) async {
    final caps = AppScope.of(context).devices.caps;
    if (caps == null) return null;
    final fitted = clip.fitTo(caps.width, caps.height);
    return _upload(context, title, compute(_encodeFrames, (fitted.frames, fitted.averageFps)));
  }

  static Future<String?> _upload(
      BuildContext context, String title, Future<Uint8List> encoding) async {
    final s = AppScope.of(context);
    final d = s.devices;
    final caps = d.caps, client = d.client;
    if (caps == null || client == null) return null;
    if (!caps.canPlayGifs) {
      return _report(context, 'This controller can\'t play GIFs. Live streaming still works.');
    }
    try {
      final bytes = await encoding;
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

Uint8List _encodeFrames((List<Frame>, int) a) => bakeFrames(a.$1, fps: a.$2).bytes;
