import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/user_library.dart';
import 'package:glyph/main.dart';
import 'package:glyph/ui/widgets/discover/seasons.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    await tester.pump(const Duration(milliseconds: 300));
    return playback;
  }

  testWidgets('shelves, favourites, search and recents on the full catalog', (tester) async {
    final playback = await pumpApp(tester);
    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('Search ${catalog.items.length} animations'), findsOneWidget);
    expect(find.text(seasonFor(DateTime.now()).title), findsOneWidget);

    // Heart the first featured card.
    final first = catalog.featured.first;
    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(UserLibrary.shared.isFavourite(first.id), isTrue);
    expect(find.text('Added "${first.title}" to favourites'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsWidgets);

    // The Favourites chip shows only hearted items.
    await tester.tap(find.text('Favourites'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Favourites · 1'), findsOneWidget);
    expect(find.text(first.title), findsOneWidget);
    expect(find.text('Chill Vibes'), findsNothing, reason: 'shelves only show while browsing All');

    // Search ignores the shelves and ranks title hits.
    await tester.tap(find.text('All'));
    await tester.enterText(find.byType(TextField), 'pizza');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('result'), findsOneWidget);
    expect(find.text('Cheesy Pizza'), findsOneWidget);

    // Playing something adds a "Recently played" row once we're browsing again.
    await tester.tap(find.text('Cheesy Pizza'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Recently played'), findsOneWidget);
    expect(UserLibrary.shared.recents.first, 'cheesy-pizza');

    // Persisted for the next launch.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(UserLibrary.favouritesKey), contains(first.id));
    playback.pause();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('sort menu and narrow screens', (tester) async {
    await pumpApp(tester, size: const Size(360, 740));
    // The chip, not a shelf card that happens to show the category name.
    final chip = find.widgetWithText(ChoiceChip, catalog.categories.first);
    await tester.ensureVisible(chip);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(chip);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byTooltip('Sort'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('A–Z').last);
    await tester.pump(const Duration(milliseconds: 300));
    final sorted = catalog.inCategory(catalog.categories.first)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    expect(find.text(sorted.first.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
