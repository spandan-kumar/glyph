import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
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

/// Pumps [ms] of time as a run of frames, so animations that start on the
/// next frame actually progress (never pumpAndSettle: previews tick forever).
Future<void> step(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(Duration(milliseconds: ms - t < 50 ? ms - t : 50));
  }
}

void main() {
  final catalog = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync());

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PlaybackController> pumpApp(WidgetTester tester,
      {Size size = const Size(412, 915), DeviceStore? devices}) async {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final playback = PlaybackController();
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
      expect(find.text('NO DEVICE · TAP TO CONNECT'), findsOneWidget);
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
    await tester.drag(find.byType(Knob).first, const Offset(0, -60));
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
    await tester.tap(find.text('SEND'));
    await step(tester, 300);
    expect(find.text('Connect a device to send this to it.'), findsOneWidget);
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
    expect(find.text('DEVICE · OFF'), findsNothing);
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
    expect(find.text('DEVICE · OFF'), findsOneWidget);
    expect(find.byTooltip('Turn on'), findsOneWidget);

    await tester.tap(find.byKey(PowerKey.keyId));
    await step(tester, 200);
    expect(wled.posts.last.$2, {'on': true});
    expect(find.text('DEVICE · OFF'), findsNothing);

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
