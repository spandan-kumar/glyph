import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/gif_encoder.dart';
import 'package:glyph/features/device/boot_intro.dart';
import 'package:glyph/ui/tune/beam.dart';
import 'package:glyph/wled/layout.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/user_library.dart';
import 'package:glyph/main.dart';
import 'package:glyph/ui/design/knob.dart';
import 'package:glyph/ui/design/tokens.dart';
import 'package:glyph/ui/design/stage.dart';
import 'package:glyph/ui/tune/channels.dart';
import 'package:glyph/ui/tune/mini_stage.dart';
import 'package:glyph/ui/tune/stage_deck.dart';
import 'package:glyph/ui/tune/tiles.dart';
import 'package:glyph/ui/tune/tune_screen.dart';
import 'package:glyph/ui/tune/tweak_panel.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/device/fake_wled.dart';
import '../design/turn_knob.dart';

/// Pumps [ms] of time as a run of frames, so animations that start on the
/// next frame actually progress (never pumpAndSettle: previews tick forever).
Future<void> step(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(Duration(milliseconds: ms - t < 50 ? ms - t : 50));
  }
}

class _NoStreamPlayback extends PlaybackController {
  @override
  Future<void> startStreaming(String host, MatrixLayout layout) async {}
}

class _LiveClip extends ClipGenerator {
  _LiveClip(super.clip);
  @override
  bool get liveOnly => true;
}

void main() {
  final catalog = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync());

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PlaybackController> pumpApp(WidgetTester tester,
      {Size size = const Size(412, 915), DeviceStore? devices, PlaybackController? controller}) async {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final playback = controller ?? PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(GlyphApp(
      catalog: catalog,
      devices: devices ?? DeviceStore(),
      playback: playback,
      creations: CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph')),
    ));
    // Previews tick forever, so pump fixed durations instead of settling.
    await step(tester, 300);
    await step(tester, 300);
    return playback;
  }

  /// Scrolls Display by dragging on the rails (left edge, clear of the Stage).
  Future<void> scrollPage(WidgetTester tester, double dy) async {
    final view = tester.getRect(find.byType(TuneScreen));
    await tester.dragFrom(Offset(view.left + 30, view.bottom - 160), Offset(0, dy));
  }

  ScrollPosition pagePosition(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byType(TuneScreen), matching: find.byType(Scrollable)).first)
      .position;

  Finder rail(String name) => find.byWidgetPredicate((w) => w is RailHeader && w.channel.name == name);

  String? playingTitle(PlaybackController p) => p.item?.title;

  /// A visible tile that isn't the one playing.
  LedTile otherTile(WidgetTester tester, PlaybackController p) => tester
      .widgetList<LedTile>(find.byType(LedTile).hitTestable())
      .firstWhere((t) => !t.entry.isPlaying(p));

  for (final size in const [Size(360, 740), Size(412, 915)]) {
    testWidgets('Stage, caption and rails render without overflow at $size', (tester) async {
      final playback = await pumpApp(tester, size: size);
      expect(tester.takeException(), isNull);
      expect(find.text('Display'), findsWidgets);
      expect(find.byType(Stage), findsOneWidget);
      expect(find.byType(ChannelRail), findsWidgets);
      expect(rail('Right now'), findsOneWidget);
      // Never a dead Stage: something is tuned in on open.
      expect(playback.generator, isNotNull);
      expect(find.text(playingTitle(playback)!), findsWidgets);
      expect(find.textContaining('CH 01 · RIGHT NOW').hitTestable(), findsOneWidget);
      expect(find.text('TAP TO CONNECT A DEVICE'), findsOneWidget);
      expect(find.text('SWIPE THE DISPLAY'), findsOneWidget);

      // Scroll through the rails; the mini-stage takes over at the top.
      await scrollPage(tester, -1400);
      await step(tester, 400);
      expect(find.byTooltip('Next').hitTestable(), findsOneWidget, reason: 'mini-stage is pinned');
      final before = playingTitle(playback);
      await tester.tap(find.byTooltip('Next'));
      await step(tester, 300);
      expect(playingTitle(playback), isNot(before));
      expect(tester.takeException(), isNull);
      playback.pause();
    });
  }

  testWidgets('tapping a tile tunes in and the channel becomes the surf order', (tester) async {
    final playback = await pumpApp(tester);
    final tile = otherTile(tester, playback);
    await tester.tap(find.byWidget(tile));
    await step(tester, 500);
    expect(playingTitle(playback), tile.entry.title);
    expect(find.text(tile.entry.title), findsWidgets);
    final pos = tile.channel.items.indexOf(tile.entry) + 1;
    expect(
        find.textContaining('CH ${pos.toString().padLeft(2, '0')} · ${tile.channel.name.toUpperCase()}').hitTestable(),
        findsOneWidget);
    // The playing tile carries the lit dot.
    expect(find.byKey(const ValueKey('on-air')), findsWidgets);
    playback.pause();
  });

  testWidgets('swiping the Stage surfs the channel', (tester) async {
    final playback = await pumpApp(tester);
    final first = playingTitle(playback);
    await tester.drag(find.byType(Stage), const Offset(-220, 0));
    await step(tester, 400);
    final second = playingTitle(playback);
    expect(second, isNot(first));
    expect(find.text(second!), findsWidgets);
    expect(find.textContaining('CH 02 · RIGHT NOW').hitTestable(), findsOneWidget);
    expect(find.text('SWIPE THE DISPLAY'), findsNothing, reason: 'hint hides after the first swipe');

    await tester.drag(find.byType(Stage), const Offset(220, 0));
    await step(tester, 400);
    expect(playingTitle(playback), first);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('Tweak shows the palette strip and one knob per parameter', (tester) async {
    final playback = await pumpApp(tester, size: const Size(360, 740));
    await tester.tap(find.byTooltip('Tweak'));
    await step(tester, 400);
    expect(find.byType(TweakPanel), findsOneWidget);
    expect(find.byType(PaletteStrip), findsOneWidget);
    expect(find.byType(Knob), findsNWidgets(playback.generator!.params.length));
    expect(find.text('Connect a device to dim or brighten it.'), findsOneWidget);

    // Swiping the strip changes the colours live.
    final palette = playback.palette.id;
    await tester.drag(find.byType(PageView), const Offset(-140, 0));
    await step(tester, 600);
    expect(playback.palette.id, isNot(palette));

    // Knobs turn live, too.
    final spec = playback.generator!.params.first;
    final v = playback.params[spec.key];
    await turnKnob(tester, find.byType(Knob).first);
    await step(tester, 100);
    expect(playback.params[spec.key], isNot(v));

    await tester.tap(find.text('DONE'));
    await step(tester, 400);
    expect(find.byType(TweakPanel), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('search finds looks by title and tunes in', (tester) async {
    final playback = await pumpApp(tester);
    await tester.tap(find.byTooltip('Search'));
    await step(tester, 400);
    expect(find.text('cozy'), findsOneWidget, reason: 'mood tokens');
    await tester.enterText(find.byType(TextField), 'pizza');
    await step(tester, 300);
    final hit = catalog.search('pizza').first;
    expect(find.text(hit.title), findsOneWidget);
    await tester.tap(find.text(hit.title));
    await step(tester, 600);
    expect(playingTitle(playback), hit.title);
    expect(find.byType(TextField), findsNothing, reason: 'search closes after tuning in');
    expect(find.textContaining('SEARCH · PIZZA').hitTestable(), findsOneWidget);

    // A mood token searches too.
    await tester.tap(find.byTooltip('Search'));
    await step(tester, 400);
    await tester.tap(find.text('spooky'));
    await step(tester, 300);
    expect(find.textContaining('LOOKS'), findsOneWidget);
    expect(find.byType(LedTile), findsWidgets);
    playback.pause();
  });

  testWidgets('long-press and the heart favourite; Your favourites appears', (tester) async {
    final playback = await pumpApp(tester);
    final lib = UserLibrary.shared;
    final tile = otherTile(tester, playback);
    final id = (tile.entry as ItemEntry).item.id;
    final was = lib.isFavourite(id);
    await tester.longPress(find.byWidget(tile));
    await step(tester, 900);
    expect(lib.isFavourite(id), !was);

    // Heart what's on the Stage.
    final now = playback.item!.id;
    final nowWas = lib.isFavourite(now);
    await tester.tap(find.byTooltip(nowWas ? 'Unheart' : 'Heart'));
    await step(tester, 200);
    expect(lib.isFavourite(now), !nowWas);
    if (lib.favourites.isNotEmpty) {
      for (var i = 0; i < 12 && rail('Your favourites').evaluate().isEmpty; i++) {
        await scrollPage(tester, -300);
        await step(tester, 200);
      }
      expect(rail('Your favourites'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('Surprise me spins and lands on a Surprise channel', (tester) async {
    final playback = await pumpApp(tester);
    await tester.tap(find.byTooltip('Surprise me'));
    await step(tester, 100);
    expect(find.text('SHUFFLING…').hitTestable(), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await step(tester, 100);
    }
    expect(find.textContaining('CH 01 · SURPRISE').hitTestable(), findsOneWidget);
    final landed = playingTitle(playback);
    await tester.drag(find.byType(Stage), const Offset(-220, 0));
    await step(tester, 400);
    expect(playingTitle(playback), isNot(landed));
    expect(find.textContaining('CH 02 · SURPRISE').hitTestable(), findsOneWidget);
    playback.pause();
  });

  testWidgets('Send without a device explains instead of failing', (tester) async {
    final playback = await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel('Send'));
    await step(tester, 300);
    expect(find.text('Connect a device to send this to it.'), findsOneWidget);
    playback.pause();
  });

  testWidgets('Send from the collapsed mini bar uploads in place: no scroll, no beam, progress on its key', (tester) async {
    final wled = FakeWled();
    BootIntro.autoInstall = false;
    addTearDown(BootIntro.resetForTest);
    final devices = DeviceStore(clientFactory: wled.client);
    addTearDown(devices.dispose);
    await tester.runAsync(() => devices.addAndSelect('fake', 'Test device'));
    final playback = await pumpApp(tester, size: const Size(360, 740),
        devices: devices, controller: _NoStreamPlayback());
    final clip = FrameClip(width: 1, height: 1, delaysMs: [100],
        frames: [Frame(1, 1)..set(0, 0, 0xFF0000)]);
    playback.playGenerator(ClipGenerator(clip, title: 'Fresh look'));
    final pos = pagePosition(tester)..jumpTo(900);
    await step(tester, 100);
    late Completer<void> entered, release;
    wled.beforeRequest = (r) async {
      if (r.url.path == '/upload') {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
    };
    await tester.runAsync(() async {
      entered = Completer<void>();
      release = Completer<void>();
      await tester.tap(find.bySemanticsLabel('Send').hitTestable());
      await entered.future.timeout(const Duration(seconds: 10));
    });
    await step(tester, 100);
    expect(pos.pixels, 900);
    expect(find.bySemanticsLabel('Sending').hitTestable(), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BeamPainter), findsNothing);
    await tester.runAsync(() async {
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await step(tester, 300);
    expect(pos.pixels, 900);
    expect(wled.uploads, ['/fresh-look.gif']);
    expect(find.bySemanticsLabel('Sent').hitTestable(), findsOneWidget);
    expect(find.text(sendSuccessMessage), findsOneWidget);
    await step(tester, 2000);
    playback.pause();
  });

  testWidgets('collapsed Send checks saved content without a beam or scrolling, and hides for live-only looks', (tester) async {
    final wled = FakeWled();
    BootIntro.autoInstall = false;
    addTearDown(BootIntro.resetForTest);
    final devices = DeviceStore(clientFactory: wled.client);
    addTearDown(devices.dispose);
    await tester.runAsync(() => devices.addAndSelect('fake', 'Test device'));
    final playback = await pumpApp(tester, size: const Size(360, 740),
        devices: devices, controller: _NoStreamPlayback());
    final clip = FrameClip(width: 1, height: 1, delaysMs: [100],
        frames: [Frame(1, 1)..set(0, 0, 0xFF0000)]);
    playback.playGenerator(ClipGenerator(clip, title: 'Original'));
    final fitted = clip.fitTo(devices.caps!.width, devices.caps!.height);
    final bytes = encodeGif(fitted.frames, [10], forLeds: true);
    wled.presets['12'] = {'n': 'Original', 'seg': [{'id': 0, 'n': 'original.gif'}]};
    wled.files.add({'name': 'original.gif', 'type': 'file', 'size': bytes.length});
    wled.gifs['/original.gif'] = bytes;
    final pos = pagePosition(tester)..jumpTo(900);
    await step(tester, 100);
    expect(find.bySemanticsLabel('Send').hitTestable(), findsOneWidget);
    final uploads = wled.uploads.length;
    late Completer<void> entered, release;
    wled.beforeRequest = (r) async {
      if (r.url.path == '/original.gif') {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
    };
    await tester.runAsync(() async {
      entered = Completer<void>();
      release = Completer<void>();
      await tester.tap(find.bySemanticsLabel('Send').hitTestable());
      await entered.future.timeout(const Duration(seconds: 10));
    });
    await step(tester, 100);
    expect(find.bySemanticsLabel('Checking').hitTestable(), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BeamPainter), findsNothing);
    await tester.runAsync(() async {
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await step(tester, 300);
    expect(pos.pixels, 900);
    expect(wled.uploads.length, uploads);
    expect(find.text('Already on your device'), findsOneWidget);
    expect(find.text('Play it'), findsOneWidget);
    expect(find.text('Show it off'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BeamPainter), findsNothing);
    playback.playGenerator(_LiveClip(clip));
    await step(tester, 100);
    expect(find.bySemanticsLabel('Send').hitTestable(), findsNothing);
    final info = jsonDecode(wled.info) as Map<String, dynamic>..['arch'] = 'esp8266';
    wled.info = jsonEncode(info);
    await tester.runAsync(devices.refresh);
    playback.playGenerator(ClipGenerator(clip));
    await step(tester, 100);
    expect(devices.caps!.canPlayGifs, isFalse);
    expect(find.bySemanticsLabel('Send').hitTestable(), findsNothing);
    await tester.runAsync(() => devices.remove(devices.selected!));
    playback.playGenerator(ClipGenerator(clip));
    await step(tester, 100);
    expect(find.bySemanticsLabel('Send').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('a previous Sent flash cannot clear the next Send checking state', (tester) async {
    BootIntro.autoInstall = false;
    addTearDown(BootIntro.resetForTest);
    final wled = FakeWled();
    final devices = DeviceStore(clientFactory: wled.client);
    addTearDown(devices.dispose);
    await tester.runAsync(() => devices.addAndSelect('fake', 'Test device'));
    final playback = await pumpApp(tester, size: const Size(360, 740),
        devices: devices, controller: _NoStreamPlayback());
    final clip = FrameClip(width: 1, height: 1, delaysMs: [100],
        frames: [Frame(1, 1)..set(0, 0, 0xFF0000)]);
    playback.playGenerator(ClipGenerator(clip, title: 'Original'));
    await step(tester, 100);
    await tester.runAsync(() async {
      await tester.tap(find.bySemanticsLabel('Send').hitTestable());
      await Future<void>(() async {
        while (devices.keptTitle != 'Original') {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }).timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await step(tester, 100);
    expect(find.bySemanticsLabel('Sent').hitTestable(), findsOneWidget);
    expect(find.text('Show it off'), findsOneWidget);
    late Completer<void> entered, release;
    wled.beforeRequest = (r) async {
      if (r.url.path == '/original.gif') {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
    };
    await tester.runAsync(() async {
      entered = Completer<void>();
      release = Completer<void>();
      await tester.tap(find.bySemanticsLabel('Sent').hitTestable());
      await entered.future.timeout(const Duration(seconds: 10));
    });
    await step(tester, 2000);
    expect(tester.widget<SendButton>(find.byType(SendButton)).state, KeepState.checking);
    await tester.runAsync(() async {
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await step(tester, 700);
    expect(find.text('Already on your device'), findsOneWidget);
    expect(find.text('Show it off'), findsNothing);
    expect(wled.uploads, ['/original.gif']);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('swipe hint shows for the first two sessions only', (tester) async {
    SharedPreferences.setMockInitialValues({TuneScreen.swipeHintKey: 2});
    final playback = await pumpApp(tester);
    expect(find.text('SWIPE THE DISPLAY'), findsNothing);
    playback.pause();
  });

  testWidgets('scrolling morphs the Stage into the mini thumbnail and back', (tester) async {
    final playback = await pumpApp(tester, size: const Size(360, 740));
    final pos = pagePosition(tester);
    final full = tester.getRect(find.byType(Stage));
    final f = playback.frame;
    expect(full.width, closeTo(stageWidthFor(const Size(360, 740), f.width / f.height), 0.5));
    final mini = MiniStage.panelRect(top: 0, aspect: f.width / f.height);
    // The mini-stage's ‹ › wait until the Stage has arrived.
    expect(find.byTooltip('Next').hitTestable(), findsNothing);

    // Partway: smaller than at the top, bigger than the thumbnail, and on
    // its way up and to the left.
    pos.jumpTo(140);
    await step(tester, 50);
    final mid = tester.getRect(find.byType(Stage));
    expect(mid.width, lessThan(full.width));
    expect(mid.width, greaterThan(mini.width));
    expect(mid.left, lessThan(full.left));
    expect(find.byType(Stage), findsOneWidget, reason: 'one live panel, not two');

    // Further along it keeps shrinking.
    pos.jumpTo(260);
    await step(tester, 50);
    expect(tester.getRect(find.byType(Stage)).width, lessThan(mid.width));

    // Collapsed: it IS the mini thumbnail.
    pos.jumpTo(900);
    await step(tester, 50);
    final collapsed = tester.getRect(find.byType(Stage));
    expect(collapsed.width, closeTo(mini.width, 0.5));
    expect(collapsed.left, closeTo(mini.left, 0.5));
    expect(collapsed.top, closeTo(mini.top, 0.5));
    expect(find.byTooltip('Next').hitTestable(), findsOneWidget);

    // Tapping the thumbnail goes back to the top, and the Stage grows back.
    await tester.tap(find.byType(Stage));
    await step(tester, 900);
    expect(pos.pixels, 0);
    expect(tester.getRect(find.byType(Stage)).width, closeTo(full.width, 0.5));
    expect(find.byTooltip('Next').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('the title and Send ride into the bar with the Stage, never shown twice', (tester) async {
    final wled = FakeWled();
    BootIntro.autoInstall = false;
    addTearDown(BootIntro.resetForTest);
    final devices = DeviceStore(clientFactory: wled.client);
    addTearDown(devices.dispose);
    await tester.runAsync(() => devices.addAndSelect('fake', 'Test device'));
    final playback = await pumpApp(tester, size: const Size(360, 740),
        devices: devices, controller: _NoStreamPlayback());
    final pos = pagePosition(tester);
    final title = playingTitle(playback)!;
    final send = find.byType(SendButton).hitTestable();
    final flying = find.byType(SendInFlight);

    // At the top: the deck's own Send, nothing in flight.
    expect(send, findsOneWidget);
    expect(flying, findsNothing);
    final deckSend = tester.getRect(send);
    final deckTitle = tester.getRect(find.text(title).hitTestable());

    // Partway: one Send and one title, both in flight between the two ends.
    final tops = <double>[];
    for (final at in [120.0, 240.0]) {
      pos.jumpTo(at);
      await step(tester, 50);
      expect(send, findsNothing, reason: 'the real keys hide while their twin flies');
      expect(flying, findsOneWidget);
      final r = tester.getRect(flying);
      expect(r.top, lessThan(deckSend.top));
      tops.add(r.top);
      final titles = tester.widgetList<Text>(find.text(title)).length;
      expect(titles, greaterThanOrEqualTo(1));
    }
    expect(tops.last, lessThan(tops.first), reason: 'still climbing toward the bar');

    // Collapsed: the bar's square Send, nothing in flight.
    pos.jumpTo(900);
    await step(tester, 50);
    expect(flying, findsNothing);
    expect(send, findsOneWidget);
    final barSend = tester.getRect(send);
    expect(barSend.width, closeTo(40, 0.5));
    expect(barSend.top, lessThan(MiniStage.height + 1));
    expect(tester.getRect(find.text(title).hitTestable()).top, lessThan(deckTitle.top));
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('the Stage has two states: any drag in the zone runs the whole morph', (tester) async {
    final playback = await pumpApp(tester, size: const Size(360, 740));
    final pos = pagePosition(tester);
    final full = tester.getRect(find.byType(Stage)).width;
    final f = playback.frame;
    final mini = MiniStage.panelRect(top: 0, aspect: f.width / f.height);

    // A short nudge down: it doesn't stop halfway, it lands in the bar.
    await tester.timedDrag(find.text('SEE ALL').first, const Offset(0, -40), const Duration(milliseconds: 400));
    await step(tester, 100);
    final mid = tester.getRect(find.byType(Stage)).width;
    expect(mid, lessThan(full));
    await step(tester, 600);
    expect(tester.getRect(find.byType(Stage)).width, closeTo(mini.width, 0.5));

    // A short nudge back up: all the way back to the full Stage.
    await tester.timedDrag(find.text('SEE ALL').first, const Offset(0, 40), const Duration(milliseconds: 400));
    await step(tester, 700);
    expect(pos.pixels, 0);
    expect(tester.getRect(find.byType(Stage)).width, closeTo(full, 0.5));
    playback.pause();
  });

  testWidgets('back to the top: on Display once past the Stage, and on a channel page with its own Send', (tester) async {
    final wled = FakeWled();
    BootIntro.autoInstall = false;
    addTearDown(BootIntro.resetForTest);
    final devices = DeviceStore(clientFactory: wled.client);
    addTearDown(devices.dispose);
    await tester.runAsync(() => devices.addAndSelect('fake', 'Test device'));
    final playback = await pumpApp(tester, size: const Size(360, 740),
        devices: devices, controller: _NoStreamPlayback());
    final pos = pagePosition(tester);
    final top = find.bySemanticsLabel('Back to the top').hitTestable();
    expect(top, findsNothing);

    pos.jumpTo(1400);
    await step(tester, 400);
    expect(top, findsOneWidget);
    await tester.tap(top);
    await step(tester, 900);
    expect(pos.pixels, 0);
    await step(tester, 400);
    expect(top, findsNothing);

    // A channel's See all: the bar carries Send, and the page its own key.
    await tester.tap(find.text('SEE ALL').first);
    await step(tester, 600);
    expect(find.bySemanticsLabel('Send').hitTestable(), findsOneWidget);
    final grid = tester.state<ScrollableState>(find.byType(Scrollable).hitTestable().last).position;
    grid.jumpTo(min(grid.maxScrollExtent, 900.0));
    await step(tester, 400);
    if (grid.pixels > 240) {
      await tester.tap(top);
      await step(tester, 900);
      expect(grid.pixels, 0);
    }
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('a vertical drag on the Stage scrolls the page', (tester) async {
    final playback = await pumpApp(tester, size: const Size(360, 740));
    await tester.drag(find.byType(Stage), const Offset(0, -200));
    await step(tester, 300);
    expect(pagePosition(tester).pixels, greaterThan(100));
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('power key is dimmed with no device', (tester) async {
    final playback = await pumpApp(tester, size: const Size(360, 740));
    expect(find.byKey(PowerKey.keyId), findsOneWidget);
    expect(find.byTooltip('Connect a device'), findsOneWidget);
    await tester.tap(find.byKey(PowerKey.keyId));
    await step(tester, 100);
    expect(find.text('OFF · TAP TO WAKE'), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('power key switches the device; picking a look wakes it', (tester) async {
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([const SavedDevice(host: '192.168.29.6', name: 'Desk').toJson()]),
      'devices.selected': '192.168.29.6',
    });
    final wled = FakeWled();
    final devices = DeviceStore(clientFactory: wled.client);
    await devices.load();
    expect(devices.isConnected, isTrue);
    final playback = await pumpApp(tester, size: const Size(360, 740), devices: devices);
    expect(find.byTooltip('Turn off'), findsOneWidget);

    await tester.tap(find.byKey(PowerKey.keyId));
    await step(tester, 200);
    expect(wled.posts.last.$2, {'on': false});
    expect(devices.isOn, isFalse);
    expect(find.text('OFF · TAP TO WAKE'), findsOneWidget);
    expect(find.byTooltip('Turn on'), findsOneWidget);

    await tester.tap(find.byKey(PowerKey.keyId));
    await step(tester, 200);
    expect(wled.posts.last.$2, {'on': true});
    expect(find.text('OFF · TAP TO WAKE'), findsNothing);

    // Off again, then surf: the device comes back on by itself.
    await tester.tap(find.byKey(PowerKey.keyId));
    await step(tester, 200);
    expect(devices.isOn, isFalse);
    final n = wled.posts.length;
    await tester.drag(find.byType(Stage), const Offset(-220, 0));
    await step(tester, 400);
    expect(devices.isOn, isTrue);
    expect(wled.posts.skip(n).map((p) => p.$2), anyElement(equals({'on': true})));
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  test('send errors read in our words', () {
    expect(sendSuccessMessage, 'Sent to your device. It keeps playing without your phone.');
    expect(friendlySendError("Couldn't keep it: timed out"),
        'Couldn’t send this one — your device still shows it live. timed out');
    expect(friendlySendError('Couldn’t send it: timed out'),
        'Couldn’t send this one — your device still shows it live. timed out');
    expect(friendlySendError('Not enough space on the controller.'), contains('Your device is full'));
  });

  for (final size in const [Size(360, 740), Size(412, 915)]) {
    testWidgets('every SEE ALL sits on the same right gutter and centre line at $size', (tester) async {
      final playback = await pumpApp(tester, size: size);
      final width = tester.getSize(find.byType(TuneScreen)).width;
      final rights = <double>{};
      final centres = <double>{};
      final sizes = <Size>{};
      final seen = <String>{};
      for (var pass = 0; pass < 8; pass++) {
        for (final header in tester.widgetList<RailHeader>(find.byType(RailHeader))) {
          final headerFinder = find.byWidget(header);
          final seeAll = find.descendant(of: headerFinder, matching: find.text('SEE ALL'));
          if (seeAll.evaluate().isEmpty) continue;
          seen.add(header.channel.id);
          final row = find.descendant(of: headerFinder, matching: find.byType(Row)).first;
          rights.add(tester.getTopRight(seeAll).dx);
          centres.add(tester.getCenter(seeAll).dy - tester.getCenter(row).dy);
          sizes.add(tester.getSize(seeAll));
          // Centred on the row band, which is the same height on every rail.
          expect(tester.getSize(row).height, RailHeader.rowHeight);
        }
        await scrollPage(tester, -300);
        await step(tester, 200);
      }
      expect(seen.length, greaterThan(2), reason: 'several rails checked');
      expect(rights, hasLength(1), reason: 'right edges: $rights');
      expect(rights.single, moreOrLessEquals(width - Lb.gutter));
      expect(centres, hasLength(1), reason: 'centre offsets: $centres');
      expect(centres.single.abs(), lessThan(0.5));
      expect(sizes, hasLength(1));
      expect(tester.takeException(), isNull);
      playback.pause();
    });
  }
}
