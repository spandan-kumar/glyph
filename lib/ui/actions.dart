import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine/generator.dart';
import '../engine/generators/sprite.dart';
import '../features/device/boot_intro.dart';

import '../engine/clip.dart';
import '../engine/bake_limits.dart';
import '../engine/frame.dart';
import '../app/background.dart';
import '../app/community.dart';
import '../app/devices.dart';
import '../app/playback.dart';
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

/// How a Send ended. UI branches on the type, never on message text.
sealed class SendResult {
  const SendResult();

  /// The words to show or log; null when the Send was stopped quietly.
  String? get message;
}

/// The look is on the device and playing from it.
final class Sent extends SendResult {
  const Sent(this.kb);
  final double kb;
  @override
  String get message => 'Sent to your device (${kb.toStringAsFixed(1)} KB). It keeps playing without your phone.';
}

/// The device already holds exactly these bytes; nothing was uploaded.
final class AlreadyOnDevice extends SendResult {
  const AlreadyOnDevice();
  @override
  String get message => alreadyOnDeviceMessage;
}

/// What or where it was sending changed ([reason] reads "you switched
/// device"); the device was left as it was.
final class Cancelled extends SendResult {
  const Cancelled(this.reason);
  final String reason;
  @override
  String? get message => null;
}

/// It couldn't be sent ([liveOnly]: by design, the look follows the phone).
final class Failed extends SendResult {
  const Failed(this.message, {this.liveOnly = false});
  @override
  final String message;
  final bool liveOnly;
}

/// What a Send is sending and where, taken when it starts. Brightness,
/// power, pause/resume, tweaks and backgrounding don't change either (the
/// GIF is already baked from a snapshot) and must not cancel it.
class _SendGuard {
  _SendGuard(this.context, this.devices, this.playback, this.client)
      : selection = devices.selectionGeneration,
        generator = playback.generator,
        itemId = playback.item?.id,
        width = devices.caps?.width,
        height = devices.caps?.height,
        layout = _layoutKey(devices);

  final BuildContext context;
  final DeviceStore devices;
  final PlaybackController playback;
  final WledClient client;
  final int selection;
  final Generator? generator;
  final String? itemId;
  final int? width, height;
  final String layout;

  static String _layoutKey(DeviceStore d) => '${d.selected?.layout.toJson()}';

  bool get deviceCurrent => devices.isCurrent(client, selection);

  /// Why the Send can't go on ("you switched device"), or null while it can.
  String? get stopped {
    if (!context.mounted) return 'the screen was closed';
    if (!deviceCurrent) return 'you switched device';
    if (!identical(playback.generator, generator) || playback.item?.id != itemId) {
      return 'you picked a different look';
    }
    final caps = devices.caps;
    if (caps == null || caps.width != width || caps.height != height || _layoutKey(devices) != layout) {
      return 'the device layout changed';
    }
    return null;
  }

  bool get ok => stopped == null;
}

class _SendStopped implements Exception {
  const _SendStopped();
}

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
      // The raw error goes to the feedback report, not on screen.
      LastError.record('Couldn\'t start streaming: $e');
      if (context.mounted) {
        _toast(context, 'Couldn’t show this on your device. Check it’s on and on the same Wi-Fi.',
            action: reportAction(context));
      }
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
  /// frames; procedural effects record at least 30 s. Authored sprites keep
  /// their complete sequence and motion pass. Procedural loops blend their
  /// seam, since the device replays the GIF end to start forever.
  static Future<String?> saveToDevice(BuildContext context, {Future<void> Function()? onUpload}) async =>
      (await sendToDevice(context, onUpload: onUpload)).message;

  /// [saveToDevice] with a typed outcome.
  static Future<SendResult> sendToDevice(BuildContext context, {Future<void> Function()? onUpload}) async {
    final s = AppScope.of(context);
    final caps = s.devices.caps;
    final g = s.playback.generator;
    if (g != null && g.liveOnly) return const Failed(liveOnlyMessage, liveOnly: true);
    if (caps == null || g == null) return const Cancelled('nothing is playing on a connected device');
    final title = s.playback.item?.title ?? g.name;
    final w = caps.width, h = caps.height;

    if (g is ClipGenerator) {
      return sendClipToDevice(context, g.clip, title, onUpload: onUpload,
          speed: s.playback.params['speed'] * s.playback.timeScale);
    }
    final Future<Uint8List> Function() bytes;
    if (findGenerator(g.id) != null) {
      // compute() with a top-level function avoids capturing BuildContext.
      final request = (
        g.id,
        s.playback.params.toMap(),
        s.playback.palette.id,
        w,
        h,
        s.playback.timeScale,
        g is SpriteGenerator ? g : null,
      );
      bytes = () => compute(_bake, request);
    } else {
      bytes = () {
        final loop = renderDeviceLoop(
          generator: g,
          params: s.playback.params,
          palette: s.playback.palette,
          width: w,
          height: h,
          timeScale: s.playback.timeScale,
        );
        return compute(_encodeLoop, loop);
      };
    }
    return _upload(context, title, bytes, onUpload: onUpload);
  }

  static Future<String?> saveClipToDevice(
          BuildContext context, FrameClip clip, String title,
          {Future<void> Function()? onUpload, double speed = 1}) async =>
      (await sendClipToDevice(context, clip, title, onUpload: onUpload, speed: speed)).message;

  static Future<SendResult> sendClipToDevice(
      BuildContext context, FrameClip clip, String title,
      {Future<void> Function()? onUpload, double speed = 1}) async {
    final caps = AppScope.of(context).devices.caps;
    if (caps == null) return const Cancelled('no device is connected');
    try {
      checkBakeSize(caps.width, caps.height, clip.frames.length);
    } on BakeLimitException catch (e) {
      return Failed(_fail(context, e.message));
    }
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
    return _upload(context, title, () => compute(_encodeClip, (fitted.frames, delays)), onUpload: onUpload);
  }

  static Future<SendResult> _upload(
    BuildContext context,
    String title,
    Future<Uint8List> Function() encoding, {
    Future<void> Function()? onUpload,
  }) async {
    final s = AppScope.of(context);
    final d = s.devices;
    final caps = d.caps, client = d.client;
    if (caps == null || client == null) return const Cancelled('no device is connected');
    final playback = s.playback;
    final guard = _SendGuard(context, d, playback, client);
    final throttle = Object();
    playback.blockAlerts(throttle);
    bool current() => guard.ok;
    SendResult stop() {
      final why = guard.stopped ?? 'something changed';
      // Said out loud, so a Send never just vanishes.
      if (context.mounted) _toast(context, 'Send stopped because $why.');
      return Cancelled(why);
    }

    if (!caps.canPlayGifs) {
      playback.unblockAlerts(throttle);
      return Failed(_fail(context, 'This device can’t save animations. It can still show them live from your phone.'));
    }
    try {
      final bytes = await encoding();
      if (!current()) return stop();
      // Keep the current look on the matrix while the file uploads (a slow
      // trickle of frames holds live mode); switch only once it's saved.
      var fileName = keptFileName(title);
      if (fileName == BootIntro.fileName) fileName = 'my-$fileName';
      var alreadySaved = false;
      final presetId = await client.withPresetMutation(() async {
        if (!current()) throw const _SendStopped();
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
        if (!current()) throw const _SendStopped();
        // The file this replaces goes once the switch is done, so it counts
        // as free space.
        final credit = await client.reclaimableBytes(existing?.id, fileName);
        if (!caps.fitsFile(bytes.length - credit)) {
          throw WledException('Not enough space on the device for the full animation. '
              'Remove unused Saved animations or show it live.');
        }
        await onUpload?.call();
        if (!current()) throw const _SendStopped();
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
            await playback.stopStreaming();
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
      // The device is done; only touch app state if it's still the one
      // the user is looking at.
      if (!guard.deviceCurrent || !context.mounted) {
        if (alreadySaved) return const AlreadyOnDevice();
        return Sent(bytes.length / 1024);
      }
      if (alreadySaved) {
        _toast(context, alreadyOnDeviceMessage,
            action: SnackBarAction(label: 'Play it', onPressed: () => _playSaved(context, client, guard.selection, presetId)));
        return const AlreadyOnDevice();
      }
      await d.refresh();
      if (!guard.deviceCurrent) return Sent(bytes.length / 1024);
      d.noteKept(presetId, title);
      final sent = Sent(bytes.length / 1024);
      if (context.mounted) _report(context, sent.message);
      return sent;
    } on _SendStopped {
      return stop();
    } catch (e) {
      // A failure that follows the user's own change reads as that change.
      if (guard.stopped != null) return stop();
      final why = e is WledException ? e.message : '$e';
      return Failed(context.mounted
          ? _fail(context, 'Couldn\'t send it: $why')
          : 'Couldn\'t send it: $why');
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

Uint8List _bake((String, Map<String, double>, String, int, int, double, SpriteGenerator?) a) {
  final (genId, params, paletteId, w, h, speed, sprite) = a;
  return bakeLoop(renderDeviceLoop(
    // Downloaded sprites aren't registered in the worker isolate.
    generator: sprite ?? generatorById(genId),
    params: Params(params),
    palette: paletteById(paletteId),
    width: w,
    height: h,
    timeScale: speed,
  )).bytes;
}

Uint8List _encodeLoop(LoopFrames loop) => bakeLoop(loop).bytes;

Uint8List _encodeClip((List<Frame>, List<int>) a) => encodeGif(a.$1, a.$2, forLeds: true);
