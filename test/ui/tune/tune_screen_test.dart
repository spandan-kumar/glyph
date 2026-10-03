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
import 'package:glyph/ui/design/stage.dart';
import 'package:glyph/ui/tune/channels.dart';
import 'package:glyph/ui/tune/tiles.dart';
import 'package:glyph/ui/tune/tune_screen.dart';
import 'package:glyph/ui/tune/tweak_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<PlaybackController> pumpApp(WidgetTester tester, {Size size = const Size(412, 915)}) async {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(GlyphApp(
      catalog: catalog,
      devices: DeviceStore(),
      playback: playback,
      creations: CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph')),
    ));
    // Previews tick forever, so pump fixed durations instead of settling.
    await step(tester, 300);
    await step(tester, 300);
    return playback;
  }

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
      expect(find.text('Tune'), findsWidgets);
      expect(find.byType(Stage), findsOneWidget);
      expect(find.byType(ChannelRail), findsWidgets);
      expect(rail('Right now'), findsOneWidget);
      // Never a dead Stage: something is tuned in on open.
      expect(playback.generator, isNotNull);
      expect(find.text(playingTitle(playback)!), findsWidgets);
      expect(find.textContaining('CH 01 · RIGHT NOW').hitTestable(), findsOneWidget);
      expect(find.text('NO MATRIX · TAP TO CONNECT'), findsOneWidget);
      expect(find.text('SWIPE THE MATRIX'), findsOneWidget);

      // Scroll through the rails; the mini-stage takes over at the top.
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -1400));
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
    expect(find.text('SWIPE THE MATRIX'), findsNothing, reason: 'hint hides after the first swipe');

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
    expect(find.text('Connect a matrix to dim or brighten it.'), findsOneWidget);

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
        await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -300));
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

  testWidgets('Keep without a matrix explains instead of failing', (tester) async {
    final playback = await pumpApp(tester);
    await tester.tap(find.text('KEEP'));
    await step(tester, 300);
    expect(find.text('Connect a matrix to keep this on it.'), findsOneWidget);
    playback.pause();
  });

  testWidgets('swipe hint shows for the first two sessions only', (tester) async {
    SharedPreferences.setMockInitialValues({TuneScreen.swipeHintKey: 2});
    final playback = await pumpApp(tester);
    expect(find.text('SWIPE THE MATRIX'), findsNothing);
    playback.pause();
  });
}
