import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/community.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/community_design.dart';
import 'package:glyph/ui/make/community_share.dart';
import 'package:glyph/ui/make/creation_tile.dart';
import 'package:glyph/features/import/sharing.dart';
import 'package:glyph/ui/design/toggle.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

FrameClip smallClip() {
  final a = Frame(8, 8)..set(1, 1, 0xFF0000);
  final b = Frame(8, 8)..set(2, 2, 0x00FF00);
  return FrameClip.uniform([a, b], fps: 4);
}

/// Noisy 64x64 frames in 40 colours: the token won't fit in a link.
FrameClip bigClip() {
  final rnd = Random(1);
  final palette = [
    for (var i = 0; i < 40; i++)
      rgb(rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256)),
  ];
  final frames = [
    for (var f = 0; f < 4; f++)
      (() {
        final fr = Frame(64, 64);
        for (var y = 0; y < 64; y++) {
          for (var x = 0; x < 64; x++) {
            fr.set(x, y, palette[rnd.nextInt(palette.length)]);
          }
        }
        return fr;
      })(),
  ];
  return FrameClip.uniform(frames, fps: 5);
}

void main() {
  late List<Uri> opened;
  late List<String> clipboard;

  setUp(() {
    opened = [];
    clipboard = [];
    Community.launcher = (u) async {
      opened.add(u);
      return true;
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    Community.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpSheet(
    WidgetTester tester,
    FrameClip clip, {
    String title = 'Blinky',
  }) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: CommunityShareSheet(title: title, clip: clip),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Continue opens the prefilled issue form', (tester) async {
    await pumpSheet(tester, smallClip());
    expect(find.text('Share with the community'), findsOneWidget);
    await tester.tap(find.text('Continue on GitHub'));
    await tester.pump(const Duration(milliseconds: 100));

    final u = opened.single;
    expect(u.host, 'github.com');
    expect(u.path, '/spandan-kumar/glyph/issues/new');
    expect(u.queryParameters['template'], 'community_design.yml');
    expect(u.queryParameters['labels'], 'community-design');
    expect(u.queryParameters['title'], 'Community design: Blinky');
    expect(u.queryParameters['name'], 'Blinky');
    final design = CommunityDesign.decode(u.queryParameters['design']!);
    expect(design.title, 'Blinky');
    expect(design.frames, hasLength(2));
    expect(clipboard, isEmpty);
  });

  testWidgets('edited name goes into the link', (tester) async {
    await pumpSheet(tester, smallClip());
    await tester.enterText(find.byType(TextField), 'Red & green');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Continue on GitHub'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened.single.queryParameters['name'], 'Red & green');
    expect(
      CommunityDesign.decode(opened.single.queryParameters['design']!).title,
      'Red & green',
    );
  });

  testWidgets('a link too long for GitHub copies the design instead', (
    tester,
  ) async {
    await pumpSheet(tester, bigClip());
    await tester.tap(find.text('Continue on GitHub'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(opened.single.queryParameters.containsKey('design'), isFalse);
    expect(opened.single.queryParameters['name'], 'Blinky');
    expect(clipboard.single, startsWith(CommunityDesign.prefix));
    expect(
      find.text(
        'Your design is copied. Paste it into the Design box on GitHub.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open GitHub again'), findsOneWidget);
  });

  testWidgets('an empty name disables Continue and says why', (tester) async {
    await pumpSheet(tester, smallClip());
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump(const Duration(milliseconds: 50));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Give it a name to continue.'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('a drawing that is too big shows why', (tester) async {
    final frames = [
      for (var i = 0; i < CommunityDesign.maxFrames + 1; i++) Frame(8, 8),
    ];
    await pumpSheet(tester, FrameClip.uniform(frames, fps: 5));
    expect(
      find.textContaining('up to ${CommunityDesign.maxFrames} frames'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('a browser that will not open leaves the link copied', (
    tester,
  ) async {
    Community.launcher = (_) async => false;
    await pumpSheet(tester, smallClip());
    await tester.tap(find.text('Continue on GitHub'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      clipboard.single,
      startsWith('https://github.com/spandan-kumar/glyph/issues/new'),
    );
  });

  group('creation actions', () {
    Future<void> openActions(WidgetTester tester, String kind) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 740) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final playback = PlaybackController();
      addTearDown(playback.dispose);
      final dir = Directory.systemTemp.createTempSync('glyph_share');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = Creation(
        id: 'x',
        title: 'Blinky',
        kind: kind,
        clip: smallClip(),
        updatedAt: DateTime(2026),
      );
      await tester.pumpWidget(
        AppScope(
          playback: playback,
          devices: DeviceStore(),
          catalog: Catalog(items: const []),
          creations: CreationsStore(directory: () async => dir),
          child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showCreationActions(context, c),
                  child: const Text('Actions'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Actions'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('drawings can be shared with the community', (tester) async {
      await openActions(tester, 'drawing');
      expect(find.text('Share with the community'), findsOneWidget);
      await tester.tap(find.text('Share with the community'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Continue on GitHub'), findsOneWidget);
    });

    for (final kind in ['text', 'import']) {
      testWidgets('$kind creations cannot', (tester) async {
        await openActions(tester, kind);
        expect(find.text('Share'), findsOneWidget);
        expect(find.text('Share with the community'), findsNothing);
      });
    }

    testWidgets('Share offers a GIF, a Glyph file and Discord, with a caption that is on by default',
        (tester) async {
      await openActions(tester, 'drawing');
      await tester.tap(find.text('Share'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      for (final a in ['Add a caption', 'Share as GIF', 'Share Glyph file', 'Post in Show and tell']) {
        expect(find.text(a), findsOneWidget, reason: a);
      }
      expect(find.textContaining(shareCaption), findsOneWidget);
      expect(tester.widget<LbToggleTile>(find.byType(LbToggleTile)).value, isTrue);

      // Switching it off sticks for next time.
      await tester.tap(find.text('Add a caption'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<LbToggleTile>(find.byType(LbToggleTile)).value, isFalse);
      expect(await ShareCaptionPref.get(), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
