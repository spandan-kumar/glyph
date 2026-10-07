import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine/generator.dart';
import '../engine/generators/sprite.dart';
import '../features/device/boot_intro.dart';

import '../engine/clip.dart';
import '../engine/frame.dart';
import '../app/background.dart';
import '../app/community.dart';
import '../app/devices.dart';
import '../engine/gif_baker.dart';
import '../engine/gif_encoder.dart';
import '../engine/palette.dart';
import '../engine/registry.dart';
import '../library/catalog.dart';
import '../wled/wled_client.dart';
import '../wled/presets.dart';
import 'community/glyph_menu.dart';
import 'scope.dart';

const alreadyOnDeviceMessage = 'Already on your device';

/// Why a live-only look (see [Generator.liveOnly]) wasn't sent.
const liveOnlyMessage = 'This one follows your phone live, so it stays on your phone.';

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
      final client = d.client!, selection = d.selectionGeneration;
      await client.prepareStream();
      if (!d.isCurrent(client, selection) || !context.mounted) return;
      await s.playback.startStreaming(d.selected!.host, d.selected!.layout);
    } catch (e) {
      if (context.mounted) _fail(context, 'Couldn\'t start streaming: $e');
    }
  }

  static Future<void> stopStreaming(BuildContext context) async {
    final s = AppScope.of(context);
    await s.playback.stopStreaming();
    await BackgroundStreaming.stop();
    try {
      await Future.wait([s.devices.client!.exitLive(), s.devices.exitLiveMirrors()]);
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
  /// frames; anything else (games, audio) is recorded for about 4 s. Effects
  /// are baked as seamless loops (renderLoop), since the matrix replays the
  /// GIF end to start forever.
  static Future<String?> saveToDevice(BuildContext context, {Future<void> Function()? onUpload}) async {
    final s = AppScope.of(context);
    final caps = s.devices.caps;
    final g = s.playback.generator;
    if (g != null && g.liveOnly) return liveOnlyMessage;
    if (caps == null || g == null) return null;
    final title = s.playback.item?.title ?? g.name;
    final w = caps.width, h = caps.height;
    // On weak Wi-Fi a shorter, lighter loop uploads far more reliably. Keep
    // the frame rate: WLED plays 50 ms frames evenly, 66 ms ones judder.
    final weak = (s.devices.info?.signal ?? 100) < 40;
    final seconds = weak ? 3.0 : 4.0;
    const fps = deviceGifFps;

    if (g is ClipGenerator) {
      return saveClipToDevice(context, g.clip, title, onUpload: onUpload,
          speed: s.playback.params['speed'] * s.playback.timeScale);
    }
    final Future<Uint8List> bytes;
    if (findGenerator(g.id) != null) {
      // compute() with a top-level function avoids capturing BuildContext.
      bytes = compute(_bake, (
        g.id,
        s.playback.params.toMap(),
        s.playback.palette.id,
        w,
        h,
        s.playback.timeScale,
        seconds,
        fps,
        g is SpriteGenerator ? g : null,
      ));
    } else {
      final loop = renderLoop(
        generator: g,
        params: s.playback.params,
        palette: s.playback.palette,
        width: w,
        height: h,
        timeScale: s.playback.timeScale,
        seconds: seconds,
        fps: fps,
      );
      bytes = compute(_encodeLoop, loop);
    }
    return _upload(context, title, bytes, onUpload: onUpload);
  }

  static Future<String?> saveClipToDevice(
      BuildContext context, FrameClip clip, String title,
      {Future<void> Function()? onUpload, double speed = 1}) async {
    final caps = AppScope.of(context).devices.caps;
    if (caps == null) return null;
    final fitted = clip.fitTo(caps.width, caps.height);
    // Keep each frame's own timing. GIF delays are whole centiseconds (min
    // 2), so round each frame's end time rather than each delay: the loop
    // then lasts as long as the clip instead of drifting.
    final delays = <int>[];
    var elapsedMs = 0, totalCs = 0;
    for (final ms in fitted.delaysMs) {
      elapsedMs += ms;
      final d = ((elapsedMs / (10 * speed)).round() - totalCs).clamp(2, 65535);
      delays.add(d);
      totalCs += d;
    }
    return _upload(context, title, compute(_encodeClip, (fitted.frames, delays)), onUpload: onUpload);
  }

  static Future<String?> _upload(
    BuildContext context,
    String title,
    Future<Uint8List> encoding, {
    Future<void> Function()? onUpload,
  }) async {
    final s = AppScope.of(context);
    final d = s.devices;
    final caps = d.caps, client = d.client;
    if (caps == null || client == null) return null;
    final selection = d.selectionGeneration, control = d.controlGeneration;
    final playback = s.playback, revision = playback.revision;
    var stream = playback.streamGeneration;
    final throttle = Object();
    playback.blockAlerts(throttle);
    bool current() =>
        context.mounted &&
        d.isCurrent(client, selection) &&
        control == d.controlGeneration &&
        revision == playback.revision &&
        stream == playback.streamGeneration;
    if (!caps.canPlayGifs) {
      playback.unblockAlerts(throttle);
      return _fail(
        context,
        'This controller can\'t play GIFs. Live streaming still works.',
      );
    }
    try {
      final bytes = await encoding;
      if (!current()) return null;
      // Keep the current look on the matrix while the file uploads (a slow
      // trickle of frames holds live mode); switch only once it's saved.
      var fileName = keptFileName(title);
      if (fileName == BootIntro.fileName) fileName = 'my-$fileName';
      var alreadySaved = false;
      final presetId = await client.withPresetMutation(() async {
        if (!current()) throw WledException('Send cancelled: playback changed');
        final existing = await _existingPreset(client, title, fileName);
        if (existing?.gifName != null) {
          try {
            final name = existing!.gifName!;
            final path = name.startsWith('/') ? name : '/$name';
            final files = await client.files();
            final saved = files[path] == bytes.length ? await client.fileBytes(name) : null;
            if (saved != null && listEquals(saved, bytes)) {
              alreadySaved = true;
              return existing.id;
            }
          } on WledException {
            // A missing or unreadable old file can be repaired by sending it.
          }
        }
        if (!current()) throw WledException('Send cancelled: playback changed');
        if (!caps.fitsFile(bytes.length)) throw WledException('Not enough space on the controller.');
        await onUpload?.call();
        if (!current()) throw WledException('Send cancelled: playback changed');
        playback.throttleStream(throttle);
        return client.saveGifToDevice(
          fileName: fileName,
          gif: bytes,
          presetName: title,
          caps: caps,
          // Sending the same animation again replaces it rather than adding a
          // duplicate entry.
          presetId: existing?.id,
          canSwitch: current,
          beforeSwitch: () async {
            if (!current()) return;
            playback.releaseStreamThrottle(throttle);
            final stopped = playback.stopStreaming();
            stream = playback.streamGeneration;
            await stopped;
            if (!current()) return;
            await BackgroundStreaming.stop();
            if (!current()) return;
            await d.exitLiveMirrors();
          },
          onRetry: (a) {
            if (current()) {
              _toast(context, 'Weak Wi-Fi — trying again ($a of 3)…');
            }
          },
        );
      });
      if (!current()) return null;
      if (alreadySaved && context.mounted) {
        _toast(context, alreadyOnDeviceMessage,
            action: SnackBarAction(label: 'Play it', onPressed: () => _playSaved(context, client, selection, presetId)));
        return alreadyOnDeviceMessage;
      }
      await d.refresh();
      if (!current()) return null;
      d.noteKept(presetId, title);
      final kb = (bytes.length / 1024).toStringAsFixed(1);
      return context.mounted
          ? _report(
              context,
              'Sent to your device ($kb KB). It keeps playing without your phone.',
            )
          : null;
    } catch (e) {
      if (!current()) return null;
      final why = e is WledException ? e.message : '$e';
      return context.mounted ? _fail(context, 'Couldn\'t send it: $why') : null;
    } finally {
      playback.releaseStreamThrottle(throttle);
      playback.unblockAlerts(throttle);
    }
  }

  static Future<void> _playSaved(BuildContext context, WledClient client, int selection, int id) async {
    if (!context.mounted) return;
    final s = AppScope.of(context);
    final d = s.devices;
    final revision = s.playback.revision;
    var control = d.controlGeneration;
    bool current() => context.mounted && d.isCurrent(client, selection) &&
        s.playback.revision == revision && d.controlGeneration == control;
    if (!current()) return;
    try {
      await s.playback.stopStreaming();
      if (!current()) return;
      await BackgroundStreaming.stop();
      if (!current()) return;
      await client.exitLive();
      if (!current()) return;
      await d.exitLiveMirrors();
      if (!current()) return;
      final applied = d.applyPreset(id);
      control = d.controlGeneration;
      await applied;
    } catch (e) {
      if (context.mounted && current()) _fail(context, 'Couldn’t play it: $e');
    }
  }

  /// The preset that already holds [title] (same name or same GIF file), so
  /// a re-send overwrites it. Null when it's new or the list can't be read.
  static Future<WledPreset?> _existingPreset(WledClient client, String title, String fileName) async {
    try {
      final presets = await client.presetList();
      for (final p in presets) {
        // Never overwrite the protected boot intro.
        if (p.name == BootIntro.presetName || p.gifName == BootIntro.fileName) continue;
        if (!p.isPlaylist && ((p.gifName != null &&
                    WledClient.matchesGifName(fileName, p.gifName!)) || p.name == title)) {
          return p;
        }
      }
    } on WledException {
      // Fall back to a new slot; a duplicate beats a failed send.
    }
    return null;
  }

  /// Reports a failure and keeps it for feedback reports (LastError).
  static String _fail(BuildContext context, String msg) {
    LastError.record(msg);
    _toast(context, msg, action: reportAction(context));
    return msg;
  }

  static String _report(BuildContext context, String msg) {
    _toast(context, msg);
    return msg;
  }

  static void _toast(BuildContext context, String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, action: action));
  }
}

Uint8List _bake((String, Map<String, double>, String, int, int, double, double, int, SpriteGenerator?) a) {
  final (genId, params, paletteId, w, h, speed, seconds, fps, sprite) = a;
  return bakeGif(
    // Downloaded sprites aren't registered in the worker isolate.
    generator: sprite ?? generatorById(genId),
    params: Params(params),
    palette: paletteById(paletteId),
    width: w,
    height: h,
    timeScale: speed,
    seconds: seconds,
    fps: fps,
  ).bytes;
}

Uint8List _encodeLoop(LoopFrames loop) => bakeLoop(loop).bytes;

Uint8List _encodeClip((List<Frame>, List<int>) a) => encodeGif(a.$1, a.$2, forLeds: true);
