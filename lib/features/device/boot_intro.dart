import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../engine/generator.dart';
import '../../engine/generators/intro.dart';
import '../../engine/gif_baker.dart';
import '../../engine/gif_encoder.dart';
import '../../engine/palette.dart';
import '../../wled/device.dart';
import '../../wled/presets.dart';
import '../../wled/wled_client.dart';

/// The Glyph intro is the boot screen of every device Glyph manages:
///
/// * `/glyph-intro.gif` — [GlyphIntro] baked at the device's size, start to
///   end, with the finished logo held on the last frame;
/// * a "Glyph intro" preset that plays it;
/// * a "Power-on" playlist: the intro once, then the user's own power-on
///   look (its `end`), or the intro itself (resting on the logo) when there
///   is none;
/// * cfg `def.ps` pointing at that playlist.
///
/// The playlist's `end` is the source of truth for the user's power-on look
/// while the intro is installed. Both presets are system items: hidden from
/// Saved, Shows and pickers, and never deleted by the app.
///
/// Installing never touches what the device shows. A preset saved through
/// the JSON API is applied as it is saved (json.cpp deserializeState runs
/// the body before `psave`; playlists are started by loadPlaylist in the
/// same request), so the two presets are written into /presets.json and
/// uploaded instead (wled_server.cpp handleUpload bumps
/// presetsModifiedTime, which drops WLED's preset cache, file.cpp
/// getPresetCache). The upload is verified by size and retried.
abstract final class BootIntro {
  static const fileName = 'glyph-intro.gif';
  static const presetName = 'Glyph intro';
  static const playlistName = 'Power-on';

  /// How long the intro plays before the playlist moves on.
  static const seconds = GlyphIntro.duration + 0.6;
  static int get durationDs => (seconds * 10).round();
  static const fps = 20;

  /// The last frame (the finished logo) is held for 10 minutes; WLED's
  /// Image effect waits each frame's own GIF delay (image_loader.cpp
  /// renderImageToSegment), so the logo rests rather than replaying.
  static const holdCs = 60000;

  /// Install on connect. Widget tests that don't exercise it turn it off.
  static bool autoInstall = true;

  /// Bakes the GIF for a [w]×[h] device. Swappable in tests (the default
  /// runs on a background isolate).
  @visibleForTesting
  static Future<Uint8List> Function(int w, int h) bake = _bakeInBackground;

  /// Bumped whenever an install or end change rewrote the device, so views
  /// read it again.
  static final revision = ValueNotifier<int>(0);

  static final _baked = <String, Future<Uint8List>>{};

  /// Baked once per size; a failed bake is tried again next time.
  static Future<Uint8List> _gif(int w, int h) {
    final key = '${w}x$h';
    return _baked[key] ??= bake(w, h).catchError((Object e) {
      _baked.remove(key);
      throw e;
    });
  }

  @visibleForTesting
  static void resetForTest() {
    _baked.clear();
    autoInstall = true;
    bake = _bakeInBackground;
  }

  /// The "Glyph intro" preset body.
  static Map<String, dynamic> introBody(int imageEffectId) => {
    'on': true,
    'n': presetName,
    'seg': [
      // See WledClient.playGif: the Image effect plays the file named by
      // the segment; sx 128 is normal speed, ix (blur) 0.
      {'id': 0, 'fx': imageEffectId, 'n': fileName, 'sx': 128, 'ix': 0, 'frz': false},
    ],
  };

  /// The "Power-on" playlist body: the intro once, then [end].
  static Map<String, dynamic> playlistBody(int introId, int end) => {
    'playlist': WledPlaylist(
      entries: [PlaylistEntry(presetId: introId, durationDs: durationDs, transitionDs: 0)],
      repeat: 1,
      endPreset: end,
    ).toJson(),
    'on': true,
    'n': playlistName,
  };

  /// Makes sure the intro is installed on the device behind [c]. Quiet and
  /// idempotent: when the file has the right size and both presets and
  /// `def.ps` are right, nothing is written. Returns whether anything
  /// changed.
  static Future<bool> ensure(WledClient c, DeviceCapabilities caps) async {
    final fx = caps.imageEffectId;
    if (!caps.canPlayGifs || fx == null) return false;
    final gif = await _gif(caps.width, caps.height);
    if (gif.isEmpty) return false;
    var changed = false;

    final files = await c.files();
    if (files['/$fileName'] != gif.length) {
      await c.uploadFileReliably('/$fileName', gif);
      changed = true;
    }

    final raw = await _readPresets(c);
    final boot = (await c.schedule()).bootPreset;
    final plan = planInstall(raw, bootPreset: boot, imageEffectId: fx);
    if (plan == null) return changed;
    if (plan.presets != null) {
      await _writePresets(c, plan.presets!);
      changed = true;
    }
    if (boot != plan.playlistId) {
      await c.setBootPreset(plan.playlistId);
      changed = true;
    }
    return changed;
  }

  /// Sets what plays after the intro (0 = rest on the Glyph logo).
  static Future<void> setPowerOnLook(WledClient c, int presetId) async {
    final raw = await _readPresets(c);
    final layout = BootIntroLayout.of(WledPreset.parseAll(raw), 0);
    final intro = layout.intro, playlist = layout.playlist;
    if (intro == null || playlist == null) {
      throw WledException('The Glyph intro isn\'t set up on this device yet');
    }
    final end = presetId == 0 || presetId == playlist.id ? intro.id : presetId;
    await _writePresets(c, {...raw, '${playlist.id}': playlistBody(intro.id, end)});
  }

  static Future<Map<String, dynamic>> _readPresets(WledClient c) async {
    try {
      final j = jsonDecode(utf8.decode(await c.fileBytes('/presets.json')));
      if (j is Map) return j.cast<String, dynamic>();
    } on WledException catch (e) {
      if (e.cause != 404) rethrow;
    }
    return {'0': <String, dynamic>{}};
  }

  static Future<void> _writePresets(WledClient c, Map<String, dynamic> presets) async {
    await c.uploadFileReliably('/presets.json', Uint8List.fromList(utf8.encode(jsonEncode(presets))));
    revision.value++;
  }
}

/// What [BootIntro.ensure] has to write: new /presets.json contents (null
/// when they are already right) and the playlist's id.
class BootIntroPlan {
  const BootIntroPlan(this.presets, this.playlistId);

  final Map<String, dynamic>? presets;
  final int playlistId;
}

/// Works out the presets for the intro from the current /presets.json
/// ([raw]) and power-on preset. Pure, for tests. Null when no slot is free.
@visibleForTesting
BootIntroPlan? planInstall(Map<String, dynamic> raw, {required int bootPreset, required int imageEffectId}) {
  final layout = BootIntroLayout.of(WledPreset.parseAll(raw), bootPreset);
  final used = {for (final k in raw.keys) ?int.tryParse(k)};
  // System items go at the top of the range, out of the way of the user's.
  int? free(Set<int> taken) {
    for (var id = 250; id >= 1; id--) {
      if (!taken.contains(id)) return id;
    }
    return null;
  }

  final introId = layout.intro?.id ?? free(used);
  if (introId == null) return null;
  final playlistId = layout.playlist?.id ?? free({...used, introId});
  if (playlistId == null) return null;

  final old = layout.playlist?.playlist?.endPreset;
  var end = switch (old) {
    // Installed: the playlist's end is the user's choice. If def.ps was
    // changed elsewhere (WLED's own page), that is the new choice.
    final e? when bootPreset == playlistId || bootPreset == 0 => e,
    _ => bootPreset,
  };
  if (end == 0 || end == playlistId) end = introId;

  final intro = BootIntro.introBody(imageEffectId);
  final playlist = BootIntro.playlistBody(introId, end);
  final same = jsonEncode(raw['$introId']) == jsonEncode(intro) &&
      jsonEncode(raw['$playlistId']) == jsonEncode(playlist);
  return BootIntroPlan(
    same ? null : {...raw, '$introId': intro, '$playlistId': playlist},
    playlistId,
  );
}

/// The intro's presets as found on a device.
class BootIntroLayout {
  const BootIntroLayout._(this.intro, this.playlist, this.bootPreset);

  factory BootIntroLayout.of(List<WledPreset> presets, int bootPreset) {
    WledPreset? intro;
    for (final p in presets) {
      if (p.body['n'] == BootIntro.presetName && p.gifName?.toLowerCase() == BootIntro.fileName) {
        intro = p;
        break;
      }
    }
    WledPreset? playlist;
    if (intro != null) {
      for (final p in presets) {
        final pl = p.playlist;
        if (p.body['n'] == BootIntro.playlistName && pl != null && pl.entries.isNotEmpty &&
            pl.entries.first.presetId == intro.id) {
          playlist = p;
          break;
        }
      }
    }
    return BootIntroLayout._(intro, playlist, bootPreset);
  }

  final WledPreset? intro, playlist;
  final int bootPreset;

  /// The device starts with the intro.
  bool get installed => playlist != null && bootPreset == playlist!.id;

  /// What plays at power-on after the intro (or instead of it when it isn't
  /// installed); 0 = nothing / the Glyph logo.
  int get powerOnLook {
    if (!installed) return bootPreset;
    final end = playlist!.playlist!.endPreset;
    return end == intro!.id ? 0 : end;
  }

  bool isSystem(int id) => id == intro?.id || id == playlist?.id;
}

Future<Uint8List> _bakeInBackground(int w, int h) => compute(bakeIntroGif, (w, h));

/// [GlyphIntro] from start to finish at [BootIntro.fps], with the finished
/// logo held. Top-level so it can run on an isolate.
Uint8List bakeIntroGif((int, int) size) {
  final (w, h) = size;
  final g = GlyphIntro();
  final frames = renderFrames(
    generator: g,
    params: Params.defaultsFor(g, null),
    palette: paletteById(g.defaultPalette),
    width: w,
    height: h,
    seconds: BootIntro.seconds,
    fps: BootIntro.fps,
    warmup: 0,
  );
  final step = 100 ~/ BootIntro.fps;
  final delays = [for (var i = 0; i < frames.length; i++) i == frames.length - 1 ? BootIntro.holdCs : step];
  return encodeGif(frames, delays, forLeds: true);
}
