import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/ui/widgets/led_matrix_view.dart';
import 'package:glyph/wled/ddp_group.dart';

class CountingGenerator extends Generator {
  CountingGenerator({this.previewFps = 20, this.streamFps = 40});
  @override
  final int previewFps;
  @override
  final int streamFps;
  int renders = 0;
  @override
  String get id => 'counting';
  @override
  String get name => 'Counting';
  @override
  EffectInstance create(int width, int height, int seed) => _Count(this);
}

class _Count extends EffectInstance {
  _Count(this.generator);
  final CountingGenerator generator;
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) {
    generator.renders++;
    out.fill(0xff0000);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'hidden preview suspends without changing playback intent or revision',
    (tester) async {
      final p = PlaybackController()..managePreviews();
      final g = CountingGenerator();
      p.playGenerator(g);
      final revision = p.revision;
      expect(p.isPlaying, true);
      expect(p.isRendering, false);
      await tester.pump(const Duration(seconds: 1));
      expect(g.renders, 1);

      Widget view(bool active) => Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: active,
          child: LedMatrixView(frame: p.frame, repaint: p.frameTick),
        ),
      );
      await tester.pumpWidget(view(true));
      await tester.pump(const Duration(milliseconds: 200));
      expect(g.renders, 5); // initial frame + four 20 fps ticks
      expect(
        p.renderTick.value,
        5,
      ); // simulation observers also see identical frames
      expect(p.revision, revision);
      final published = p.frameTick.value;
      await tester.pumpWidget(view(false));
      final hidden = g.renders;
      await tester.pump(const Duration(seconds: 1));
      expect(g.renders, hidden);
      expect(p.frameTick.value, published); // identical frames never repaint
      expect(p.isPlaying, true);

      await tester.pumpWidget(view(true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.renders, hidden + 2);
      p.pause();
      await tester.pumpWidget(view(false));
      await tester.pumpWidget(view(true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(p.isRendering, false); // user pause survives visibility changes
      await tester.pumpWidget(const SizedBox());
      p.dispose();
    },
  );

  testWidgets('interactive local content keeps its requested 40 fps cadence', (
    tester,
  ) async {
    final p = PlaybackController()..managePreviews();
    final g = CountingGenerator(previewFps: 40);
    p.setPreviewActive(Object(), true);
    p.playGenerator(g);
    await tester.pump(const Duration(milliseconds: 200));
    expect(g.renders, 9);
    p.dispose();
    await tester.pump();
  });

  testWidgets(
    'scrolling the primary preview out of view suspends local playback',
    (tester) async {
      final p = PlaybackController()..managePreviews();
      final g = CountingGenerator(), scroll = ScrollController();
      p.playGenerator(g);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 600)),
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 1200),
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: LedMatrixView(frame: p.frame, repaint: p.frameTick),
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(g.renders, 1);
      scroll.jumpTo(1100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.renders, 3);
      scroll.jumpTo(0);
      await tester.pump();
      final hidden = g.renders;
      await tester.pump(const Duration(milliseconds: 200));
      expect(g.renders, hidden);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      p.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'screen-off stops local rendering and restores only active previews',
    (tester) async {
      final p = PlaybackController()..managePreviews();
      final g = CountingGenerator(), owner = Object();
      p.setPreviewActive(owner, true);
      p.playGenerator(g);
      await tester.pump(const Duration(milliseconds: 100));
      p.foreground = false;
      final hidden = g.renders;
      await tester.pump(const Duration(seconds: 1));
      expect(g.renders, hidden);
      p.foreground = true;
      await tester.pump(const Duration(milliseconds: 100));
      expect(g.renders, hidden + 2);
      p.setPreviewActive(owner, false);
      p.foreground = false;
      p.foreground = true;
      expect(p.isRendering, false);
      p.dispose();
      await tester.pump();
    },
  );

  test('hidden live streaming keeps sending; device-off suspends and device-on resumes', () async {
    final p = PlaybackController()..managePreviews();
    addTearDown(p.dispose);
    final g = CountingGenerator();
    p.playGenerator(g);
    p.foreground = false;
    await p.startStreamingTo([const DdpTarget('127.0.0.1')]);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(g.renders, greaterThan(4));
    expect(
      p.framesSent,
      greaterThan(3),
    ); // unchanged frames still keep live mode alive
    p.streamHeld = true;
    final held = g.renders, sent = p.framesSent;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(g.renders, held);
    expect(p.framesSent, sent);
    p.streamHeld = false;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(p.framesSent, greaterThan(sent));
    await p.stopStreaming();
    expect(p.isRendering, false);
    expect(p.isPlaying, true);
  });

  test(
    'background alert wakes a suspended loop without rendering the hidden base',
    () async {
      final p = PlaybackController()..managePreviews();
      addTearDown(p.dispose);
      final base = CountingGenerator(), alert = CountingGenerator();
      p.playGenerator(base);
      p.foreground = false;
      final revision = p.revision;
      expect(
        await p.beginAlert(
          alert,
          const DdpTarget('127.0.0.1'),
          width: 16,
          height: 16,
        ),
        true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(alert.renders, greaterThan(1));
      expect(base.renders, 1);
      p.endAlert();
      expect(p.isPlaying, true);
      expect(p.isRendering, false);
      expect(p.revision, revision);
      p.pause();
      await p.beginAlert(
        alert,
        const DdpTarget('127.0.0.1'),
        width: 16,
        height: 16,
      );
      p.endAlert();
      expect(p.isPlaying, false);
    },
  );

  test('slow live cards use fewer ticks and alerts temporarily retain full cadence', () async {
    final p = PlaybackController()..managePreviews();
    addTearDown(p.dispose);
    final card = CountingGenerator(streamFps: 10), alert = CountingGenerator();
    p.playGenerator(card);
    p.foreground = false;
    await p.startStreamingTo([const DdpTarget('127.0.0.1')]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(card.renders, inInclusiveRange(2, 5));
    expect(p.framesSent, greaterThan(0));
    await p.beginAlert(
      alert,
      const DdpTarget('127.0.0.1'),
      width: 16,
      height: 16,
    );
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(alert.renders, greaterThan(4));
    p.endAlert();
    final ended = card.renders;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(card.renders - ended, inInclusiveRange(1, 4));
  });
}
