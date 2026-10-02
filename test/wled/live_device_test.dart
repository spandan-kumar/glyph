// Exercises the matrix-management API against a real WLED 16 device.
// Skipped unless GLYPH_LIVE_HOST is set, e.g.
//   GLYPH_LIVE_HOST=192.168.29.6 flutter test test/wled/live_device_test.dart
// Only touches presets ≥ 200 and files named glyph_test_*; timers, boot preset,
// device name, night light and power/brightness are snapshotted and restored.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/presets.dart';
import 'package:glyph/wled/schedule.dart';
import 'package:glyph/wled/wled_client.dart';

final _host = Platform.environment['GLYPH_LIVE_HOST'];

/// 1×1 GIF.
final _tinyGif = base64Decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7');

Future<void> _settle([int ms = 900]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test(
    'presets, playlists, timers, boot preset, name, night light',
    () async {
      final c = WledClient(_host!);
      final state0 = await c.state();
      final cfg0 = await c.config();
      final sched0 = WledSchedule.fromConfig(cfg0);
      final name0 = (cfg0['id'] as Map)['name'] as String;
      final nl0 = Map<String, dynamic>.from(state0['nl'] as Map);
      final timers0 = ((cfg0['timers'] as Map)['ins'] as List).cast<Map>();
      final presets0 = {for (final p in await c.presetList()) p.id};
      expect(presets0.where((id) => id >= 200), isEmpty, reason: 'test slots must be free');

      try {
        // Light on, so snapshots and the night light behave as in normal use.
        await c.setState({'on': true});
        // State preset at 200, then rename it (re-saved verbatim with "o").
        await c.saveCurrentAsPreset('glyph_test_state', id: 200);
        await _settle();
        var p200 = (await c.presetList()).firstWhere((p) => p.id == 200);
        expect(p200.name, 'glyph_test_state');
        final segsBefore = jsonEncode(p200.body['seg']);
        await c.renamePreset(200, 'glyph_test_renamed');
        await _settle();
        p200 = (await c.presetList()).firstWhere((p) => p.id == 200);
        expect(p200.name, 'glyph_test_renamed');
        expect(jsonEncode(p200.body['seg']), segsBefore, reason: 'content kept');
        expect(p200.body.containsKey('o'), isFalse);
        expect(p200.body.containsKey('psave'), isFalse);

        // Playlist at 201: stored as {"playlist":{…},"on":true,"n":…}.
        const pl = WledPlaylist(
          entries: [
            PlaylistEntry(presetId: 200, durationDs: 50, transitionDs: 0),
            PlaylistEntry(presetId: 102, durationDs: 70, transitionDs: 5),
          ],
          repeat: 2,
          endPreset: WledPlaylist.restorePrevious,
        );
        await c.savePlaylist(id: 201, name: 'glyph_test_list', playlist: pl);
        await _settle(1200);
        final p201 = (await c.presetList()).firstWhere((p) => p.id == 201);
        // ignore: avoid_print
        print('stored playlist: ${jsonEncode(p201.body)}');
        expect(p201.isPlaylist, isTrue);
        expect(p201.name, 'glyph_test_list');
        final back = p201.playlist!;
        expect(back.entries, pl.entries);
        expect(back.repeat, 2);
        expect(back.shuffle, isFalse);
        expect(back.endPreset, anyOf(WledPlaylist.restorePrevious, 0));
        // Saving starts it without an id ("pl": 0); applying gives it one.
        expect((await c.state())['pl'], anyOf(0, 201));
        await c.applyPreset(201);
        await _settle(600);
        expect((await c.state())['pl'], 201);
        await c.nextInPlaylist();

        // Rename a playlist (re-saved as a playlist).
        await c.renamePreset(201, 'glyph_test_list2');
        await _settle(1200);
        final p201b = (await c.presetList()).firstWhere((p) => p.id == 201);
        expect(p201b.name, 'glyph_test_list2');
        expect(p201b.playlist!.entries.map((e) => e.presetId), [200, 102]);

        // Timers: replace, read back from the live config, restore.
        final timers = [
          const WledTimer(presetId: 200, enabled: false, hour: 3, minute: 7, weekdays: 0x15),
          const WledTimer(
            presetId: 201,
            enabled: false,
            hour: WledTimer.sunsetHour,
            minute: -30,
            startMonth: 11,
            startDay: 2,
            endMonth: 2,
            endDay: 20,
          ),
          const WledTimer(
            presetId: 200,
            enabled: false,
            hour: WledTimer.everyHourValue,
            minute: 15,
          ),
        ];
        await c.saveTimers(timers);
        final cfg1 = await c.config();
        // ignore: avoid_print
        print('timers back: ${jsonEncode((cfg1['timers'] as Map)['ins'])}');
        expect(WledSchedule.fromConfig(cfg1).timers, timers);

        await c.setBootPreset(200);
        expect((await c.schedule()).bootPreset, 200);

        await c.setDeviceName('glyph_test_name');
        expect((await c.info()).name, 'glyph_test_name');

        await c.setNightlight(on: true, minutes: 45, mode: 1, targetBri: 0);
        final nl = (await c.state())['nl'] as Map;
        expect(nl['on'], isTrue);
        expect(nl['dur'], 45);

        // Files: fetch an existing GIF; upload, list and delete a test file.
        final duck = await c.fileBytes('/duck.gif');
        expect(latin1.decode(duck.sublist(0, 6)), 'GIF89a');
        await c.uploadFile('/glyph_test_tiny.gif', Uint8List.fromList(_tinyGif));
        expect((await c.files()).containsKey('/glyph_test_tiny.gif'), isTrue);
        await c.deleteFile('/glyph_test_tiny.gif');
        expect((await c.files()).containsKey('/glyph_test_tiny.gif'), isFalse);
      } finally {
        // Restore everything, most important first.
        await c.setConfig({
          'timers': {'ins': timers0},
          'def': {'ps': sched0.bootPreset},
          'id': {'name': name0},
        });
        await c.setNightlight(
          on: nl0['on'] == true,
          minutes: (nl0['dur'] as num).toInt(),
          mode: (nl0['mode'] as num).toInt(),
          targetBri: (nl0['tbri'] as num).toInt(),
        );
        for (final id in [201, 200]) {
          await c.deletePreset(id);
        }
        final files = await c.files();
        for (final f in files.keys.where((f) => f.startsWith('/glyph_test_'))) {
          await c.deleteFile(f);
        }
        // Re-posting the segments also unloads any playlist (json.cpp: an "fx"
        // in a direct request calls unloadPlaylist).
        final ps = state0['ps'];
        if (ps is num && ps > 0) {
          await c.setState({'ps': ps.toInt()});
          await _settle(600);
        } else {
          await c.setState({'seg': state0['seg']});
        }
        await c.setState({'on': state0['on'], 'bri': state0['bri']});
      }

      final state2 = await c.state();
      expect(state2['on'], state0['on']);
      expect(state2['bri'], state0['bri']);
      expect(state2['pl'], -1);
      expect((state2['nl'] as Map)['on'], nl0['on']);
      final cfg2 = await c.config();
      expect((cfg2['timers'] as Map)['ins'], timers0);
      expect((cfg2['def'] as Map)['ps'], sched0.bootPreset);
      expect((cfg2['id'] as Map)['name'], name0);
      expect({for (final p in await c.presetList()) p.id}, presets0);
      c.close();
    },
    skip: _host == null ? 'set GLYPH_LIVE_HOST to run against a device' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
