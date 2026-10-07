import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/gif_encoder.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/actions.dart';
import 'package:glyph/ui/scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/device/fake_wled.dart';

class _Playback extends PlaybackController {
  int stops = 0;
  @override
  Future<void> stopStreaming({bool notify = true}) {
    stops++;
    return super.stopStreaming(notify: notify);
  }
}

void main() {
  late FakeWled alpha, beta;
  late DeviceStore devices;
  late _Playback playback;
  late FrameClip clip;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    alpha = FakeWled();
    beta = FakeWled();
    devices = DeviceStore(
      clientFactory: (host) => (host == 'alpha' ? alpha : beta).client(host),
    );
    playback = _Playback();
    clip = FrameClip(
      width: 1,
      height: 1,
      delaysMs: [100],
      frames: [Frame(1, 1)..set(0, 0, 0xFF0000)],
    );
  });
  tearDown(() {
    playback.dispose();
    devices.dispose();
  });

  Future<BuildContext> mount(WidgetTester tester) async {
    await tester.runAsync(() => devices.addAndSelect('alpha', 'Alpha'));
    late BuildContext context;
    await tester.pumpWidget(
      AppScope(
        devices: devices,
        playback: playback,
        creations: CreationsStore(),
        catalog: Catalog(
          version: Catalog.currentVersion,
          items: [],
          categories: [],
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets(
    'unchanged clip offers Play it without uploading even when storage is full',
    (tester) async {
      final info = jsonDecode(alpha.info) as Map<String, dynamic>;
      (info['fs'] as Map)['u'] = (info['fs'] as Map)['t'];
      alpha.info = jsonEncode(info);
      final context = await mount(tester);
      final fitted = clip.fitTo(devices.caps!.width, devices.caps!.height);
      final bytes = encodeGif(fitted.frames, [10], forLeds: true);
      expect(devices.caps!.fitsFile(bytes.length), isFalse);
      alpha.presets['12'] = {
        'n': 'Original',
        'seg': [
          {'id': 0, 'n': 'original-00.gif'},
        ],
      };
      alpha.files.add({
        'name': 'original-00.gif',
        'type': 'file',
        'size': bytes.length,
      });
      alpha.gifs['/original-00.gif'] = bytes;
      playback.playGenerator(ClipGenerator(clip, title: 'Original'));
      var uploadsStarted = 0;
      final result = await tester.runAsync(
        () => GlyphActions.saveToDevice(
          context,
          onUpload: () async {
            uploadsStarted++;
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(result, alreadyOnDeviceMessage);
      expect(uploadsStarted, 0);
      expect(alpha.uploads, isEmpty);
      expect(playback.stops, 0);
      expect(alpha.posts, isEmpty);
      expect(devices.keptTitle, isNull);
      expect(find.text('Already on your device'), findsOneWidget);
      expect(find.text('Show it off'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.text('Play it'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      expect(alpha.posts.where((p) => p.$2['ps'] == 12), hasLength(1));
      expect(playback.stops, 1);
      playback.pause();
    },
  );

  testWidgets('changing a clip sends new bytes and reuses its Saved entry', (
    tester,
  ) async {
    final context = await mount(tester);
    alpha.presets['12'] = {
      'n': 'Original',
      'seg': [
        {'id': 0, 'n': 'original.gif'},
      ],
    };
    alpha.files.add({
      'name': 'original.gif',
      'type': 'file',
      'size': FakeWled.gif.length,
    });
    playback.playGenerator(ClipGenerator(clip, title: 'Original'));
    var uploadsStarted = 0;
    final result = await tester.runAsync(
      () => GlyphActions.saveToDevice(
        context,
        onUpload: () async {
          uploadsStarted++;
        },
      ),
    );
    expect(result, startsWith('Sent'));
    expect(uploadsStarted, 1);
    expect(alpha.uploads, ['/original-00.gif']);
    expect(alpha.posts.where((p) => p.$2['psave'] == 12), hasLength(1));
    expect(alpha.presets['12']['seg'][0]['n'], 'original-00.gif');
    playback.pause();
  });

  testWidgets('changing clip speed changes the saved GIF timing', (
    tester,
  ) async {
    final context = await mount(tester);
    final fitted = clip.fitTo(devices.caps!.width, devices.caps!.height);
    final original = encodeGif(fitted.frames, [10], forLeds: true);
    alpha.presets['12'] = {
      'n': 'Original',
      'seg': [
        {'id': 0, 'n': 'original.gif'},
      ],
    };
    alpha.files.add({
      'name': 'original.gif',
      'type': 'file',
      'size': original.length,
    });
    alpha.gifs['/original.gif'] = original;
    playback.playGenerator(ClipGenerator(clip, title: 'Original'));
    playback.setParam('speed', 2);
    final result = await tester.runAsync(
      () => GlyphActions.saveToDevice(context),
    );
    expect(result, startsWith('Sent'));
    expect(alpha.uploads, ['/original-00.gif']);
    expect(
      alpha.gifs['/original-00.gif'],
      encodeGif(fitted.frames, [5], forLeds: true),
    );
    playback.pause();
  });

  for (final change in ['palette', 'params', 'speed', 'dimensions']) {
    testWidgets(
      'unchanged library look is detected, then changing $change sends it again',
      (tester) async {
        final context = await mount(tester);
        const item = LibraryItem(
          id: 'original',
          title: 'Original',
          category: 'test',
          generatorId: 'plasma',
          paletteId: 'ocean',
        );
        playback.playItem(item);
        var uploadsStarted = 0;
        Future<String?> send() => GlyphActions.saveToDevice(
          context,
          onUpload: () async {
            uploadsStarted++;
          },
        );
        expect(await tester.runAsync(send), startsWith('Sent'));
        final id = devices.presetId;
        expect(await tester.runAsync(send), alreadyOnDeviceMessage);
        expect(uploadsStarted, 1);
        expect(alpha.uploads, ['/original.gif']);
        switch (change) {
          case 'palette':
            playback.setPalette(paletteById('lava'));
          case 'params':
            playback.setParam('scale', 0.8);
          case 'speed':
            playback.playItem(
              const LibraryItem(
                id: 'original',
                title: 'Original',
                category: 'test',
                generatorId: 'plasma',
                paletteId: 'ocean',
                speed: 2,
              ),
            );
          case 'dimensions':
            final info = jsonDecode(alpha.info) as Map<String, dynamic>;
            (info['leds'] as Map)['matrix'] = {'w': 8, 'h': 8};
            alpha.info = jsonEncode(info);
            await tester.runAsync(devices.refresh);
            playback.resize(8, 8);
        }
        expect(await tester.runAsync(send), startsWith('Sent'));
        expect(uploadsStarted, 2);
        expect(devices.presetId, id);
        expect(alpha.uploads, ['/original.gif', '/original-00.gif']);
        playback.pause();
      },
    );
  }

  for (final switchDevice in [true, false]) {
    testWidgets(
      switchDevice
          ? 'switching devices during Send changes neither device playback nor selected Saved state'
          : 'newer playback during Send is not stopped or marked Saved',
      (tester) async {
        final context = await mount(tester);
        playback.playGenerator(ClipGenerator(clip, title: 'Original'));
        late Completer<void> entered, release;
        alpha.beforeRequest = (r) async {
          if (r.url.path == '/upload') {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
        };
        late Future<String?> sent;
        await tester.runAsync(() async {
          entered = Completer<void>();
          release = Completer<void>();
          sent = GlyphActions.saveClipToDevice(context, clip, 'Original');
          await Future.any([
            entered.future,
            sent.then<void>(
              (value) => throw StateError('Send ended before upload: $value'),
            ),
          ]).timeout(const Duration(seconds: 10));
          if (switchDevice) await devices.addAndSelect('beta', 'Beta');
        });
        final newer = ClipGenerator(clip, title: 'Newer');
        playback.playGenerator(newer);
        release.complete();
        final result = await tester.runAsync(() => sent);
        await tester.pump();
        expect(result, isNull);
        // Never a silent stop: the toast says why.
        expect(
          find.text(
            switchDevice
                ? 'Send stopped — you switched device.'
                : 'Send stopped — you picked a different look.',
          ),
          findsOneWidget,
        );
        expect(playback.generator, same(newer));
        expect(playback.isPlaying, isTrue);
        expect(playback.stops, 0);
        expect(playback.streamThrottled, isFalse);
        expect(devices.keptTitle, isNull);
        expect(alpha.posts.where((p) => p.$1 == '/json/state'), isEmpty);
        expect(beta.posts.where((p) => p.$1 == '/json/state'), isEmpty);
        playback.pause();
      },
    );
  }

  testWidgets(
    'a completed Send stops only its session and marks the original device Saved',
    (tester) async {
      final context = await mount(tester);
      playback.playGenerator(ClipGenerator(clip, title: 'Original'));
      final result = await tester.runAsync(
        () => GlyphActions.saveClipToDevice(context, clip, 'Original'),
      );
      expect(result, startsWith('Sent'));
      expect(playback.stops, 1);
      expect(devices.keptTitle, 'Original');
      expect(playback.streamThrottled, isFalse);
      playback.pause();
    },
  );

  testWidgets(
    'brightness, power, pause/resume, tweaks and palette changes do not cancel a Send',
    (tester) async {
      final context = await mount(tester);
      playback.playGenerator(ClipGenerator(clip, title: 'Original'));
      late Completer<void> entered, release;
      alpha.beforeRequest = (r) async {
        if (r.url.path == '/upload') {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        }
      };
      late Future<SendResult> sent;
      await tester.runAsync(() async {
        entered = Completer<void>();
        release = Completer<void>();
        sent = GlyphActions.sendClipToDevice(context, clip, 'Original');
        await entered.future.timeout(const Duration(seconds: 10));
        devices.setBrightness(40);
        await devices.setPower(true);
        playback.pause();
        playback.resume();
        playback.setParam('speed', 1.5);
        playback.setPalette(paletteById('lava'));
      });
      release.complete();
      final result = await tester.runAsync(() => sent);
      expect(result, isA<Sent>());
      expect(devices.keptTitle, 'Original');
      expect(alpha.posts.where((p) => p.$2['psave'] != null), hasLength(1));
      expect(find.textContaining('Send stopped'), findsNothing);
      playback.pause();
    },
  );

  group('re-sending a changed look after an app restart', () {
    // The fresh client in mount() knows nothing about files from earlier.
    void seedOldFile(int listedSize) {
      alpha.presets['12'] = {
        'n': 'Original',
        'seg': [
          {'id': 0, 'n': 'original.gif'},
        ],
      };
      alpha.files.add({
        'name': 'original.gif',
        'type': 'file',
        'size': listedSize,
      });
      alpha.gifs['/original.gif'] = [1, 2, 3];
    }

    void setFreeKb(int kb) {
      final info = jsonDecode(alpha.info) as Map<String, dynamic>;
      (info['fs'] as Map)
        ..['t'] = 1000
        ..['u'] = 1000 - kb;
      alpha.info = jsonEncode(info);
    }

    testWidgets(
      'retires the previous file and counts it as free space on a nearly full device',
      (tester) async {
        // 32 KB free is exactly the safety margin: the new file fits only
        // because the replaced 6 KB one is given back.
        setFreeKb(32);
        seedOldFile(6000);
        final context = await mount(tester);
        playback.playGenerator(ClipGenerator(clip, title: 'Original'));
        final result = await tester.runAsync(
          () => GlyphActions.sendClipToDevice(context, clip, 'Original'),
        );
        expect(result, isA<Sent>());
        expect(alpha.uploads, ['/original-00.gif']);
        expect(alpha.deleted, ['/original.gif']);
        expect(alpha.presets['12']['seg'][0]['n'], 'original-00.gif');
        playback.pause();
      },
    );

    testWidgets('a full device with nothing to give back still says so and stays untouched', (
      tester,
    ) async {
      setFreeKb(32);
      alpha.presets['12'] = {
        'n': 'Original',
        'seg': [
          {'id': 0, 'n': 'someone-elses.gif'},
        ],
      };
      alpha.files.add({'name': 'someone-elses.gif', 'type': 'file', 'size': 6000});
      final context = await mount(tester);
      playback.playGenerator(ClipGenerator(clip, title: 'Original'));
      final result = await tester.runAsync(
        () => GlyphActions.sendClipToDevice(context, clip, 'Original'),
      );
      expect(result, isA<Failed>());
      expect((result as Failed).message, contains('space'));
      expect(alpha.uploads, isEmpty);
      expect(alpha.deleted, isEmpty);
      expect(alpha.posts, isEmpty);
      playback.pause();
    });
  });
}
