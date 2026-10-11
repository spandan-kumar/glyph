import 'package:flutter/material.dart';

import '../../engine/clip.dart';
import '../../engine/generator.dart';
import '../../features/audio/audio_screen.dart';
import '../../features/glance/glance_screen.dart';
import '../../features/editor/editor_screen.dart';
import '../../features/games/catalog.dart';
import '../../features/games/games_screen.dart';
import '../../features/import/import_screen.dart';
import '../../features/now_playing/now_playing_screen.dart';
import '../../features/notifications/notification_screen.dart';
import '../../features/notifications/notification_logo.dart';
import '../../features/text/text_studio_screen.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import '../community/glyph_menu.dart';
import 'creation_tile.dart';
import 'demos.dart';
import 'led_loop.dart';
import 'studio_kit.dart';
import '../design/route.dart';

/// Make: a studio of tools that demo themselves, then everything you've made.
class MakeScreen extends StatefulWidget {
  const MakeScreen({super.key});

  @override
  State<MakeScreen> createState() => _MakeScreenState();
}

class _MakeScreenState extends State<MakeScreen> {
  // Built once so the previews keep running across rebuilds.
  final _glance = glanceDemo();
  final _draw = ClipGenerator(drawDemoClip, title: 'Draw');
  final _write = writeDemo();
  final _clock = clockDemo();
  final _timer = timerDemo();
  final _gif = ClipGenerator(gifDemoClip, title: 'Bring a GIF');
  final _music = musicDemo();
  final _play = playDemo();
  final _nowPlaying = nowPlayingDemo();
  final _notifications = NotificationLogoGenerator(NotificationLogo.fallback);

  void _open(Widget page) =>
      Navigator.of(context).push(lbRoute((_) => page));

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([scope.creations, scope.devices]),
        builder: (context, _) {
          final items = scope.creations.items;
          final connected = scope.devices.isConnected;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Lb.gutter, 20, Lb.gutter, 20),
                sliver: SliverToBoxAdapter(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('Make', style: LbType.display)),
                      const GlyphMenuKey(),
                    ]),
                    const SizedBox(height: 8),
                    Text('Draw it, write it or bring it in. It shows up on your device.',
                        style: LbType.body.copyWith(color: Lb.text2)),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Lb.gutter),
                sliver: SliverToBoxAdapter(
                  child: _StudioGrid(
                    draw: _StudioTile(
                      big: true,
                      label: 'Draw',
                      line: connected ? null : 'Pixel by pixel',
                      lineWidget: connected ? const LivePulse(label: 'Draws live on your device') : null,
                      generator: _draw,
                      onTap: () => _open(const EditorScreen(blank: true)),
                    ),
                    write: _StudioTile(
                      label: 'Write',
                      line: 'Say it big',
                      generator: _write,
                      onTap: () => _open(const TextStudioScreen(mode: 'text')),
                    ),
                    clock: _StudioTile(
                      label: 'Clock',
                      line: 'Tick tock',
                      generator: _clock,
                      onTap: () => _open(const TextStudioScreen(mode: 'clock')),
                    ),
                    timer: _StudioTile(
                      label: 'Timer',
                      line: '3, 2, 1…',
                      generator: _timer,
                      onTap: () => _open(const TextStudioScreen(mode: 'countdown')),
                    ),
                    gif: _StudioTile(
                      label: 'Bring a GIF',
                      line: 'Any image',
                      generator: _gif,
                      onTap: () => _open(const ImportScreen()),
                    ),
                    music: _StudioTile(
                      label: 'Music',
                      line: 'Hears you',
                      generator: _music,
                      onTap: () => _open(const AudioScreen()),
                    ),
                    nowPlaying: _StudioTile(
                      label: 'Now Playing',
                      line: 'Album art',
                      generator: _nowPlaying,
                      onTap: () => _open(const NowPlayingScreen()),
                    ),
                    glance: _StudioTile(
                      label: 'Glance',
                      line: 'Live cards',
                      generator: _glance,
                      onTap: () => _open(const GlanceScreen()),
                    ),
                    notifications: _StudioTile(
                      label: 'Alerts',
                      line: 'App logos',
                      generator: _notifications,
                      onTap: () => _open(const NotificationScreen()),
                    ),
                    play: _StudioBanner(
                      label: 'Play',
                      line: '${gameDefs.length} games',
                      generator: _play,
                      onTap: () => _open(const GamesScreen()),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Lb.gutter, 32, Lb.gutter, 12),
                sliver: SliverToBoxAdapter(
                  child: Row(children: [
                    const Expanded(child: MonoLabel('Made by you')),
                    if (items.isNotEmpty) MonoLabel('${items.length}'),
                  ]),
                ),
              ),
              if (items.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: Lb.gutter),
                  sliver: SliverToBoxAdapter(
                    child: LbPanel(
                      child: Text(
                        'Things you draw, write or bring in live here. '
                        'Tap one to play it; hold it for more.',
                        style: LbType.small,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: Lb.gutter),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 128,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) =>
                        CreationTile(key: ValueKey(items[i].id), creation: items[i]),
                  ),
                ),
              // Room for the floating dock.
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
    );
  }
}

/// Ten tools on a three-column grid, read in order:
///
///     ┌───────────┬─────┐
///     │           │Write│
///     │   Draw    ├─────┤
///     │           │Clock│
///     ├─────┬─────┼─────┤
///     │Timer│ GIF │Music│
///     └─────┴─────┴─────┘
///      LIVE FROM YOUR PHONE
///     ┌─────┬─────┬─────┐
///     │ Now │Glanc│Alert│
///     ├─────┴─────┴─────┤
///     │ Play ▸ ░░░░░░░░ │   arcade marquee, game running wide
///     └─────────────────┘
///
/// Draw is the big one (2×2); the text tools start beside it and spill into
/// the row below. The tools that need the phone to stay connected sit on
/// their own labelled row; Play closes the studio as a full-width strip.
class _StudioGrid extends StatelessWidget {
  const _StudioGrid({
    required this.draw,
    required this.write,
    required this.clock,
    required this.timer,
    required this.gif,
    required this.music,
    required this.nowPlaying,
    required this.notifications,
    required this.glance,
    required this.play,
  });

  final Widget draw, write, clock, timer, gif, music, nowPlaying, notifications, glance, play;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LayoutBuilder(builder: (context, c) {
            final cell = (c.maxWidth - 2 * _gap) / 3;
            final h = cell * 1.36;
            Widget row(List<Widget> tiles) => SizedBox(
                  height: h,
                  child: Row(children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      SizedBox(width: cell, child: tiles[i]),
                    ],
                  ]),
                );
            return Column(children: [
              SizedBox(
                height: 2 * h + _gap,
                child: Row(children: [
                  SizedBox(width: 2 * cell + _gap, child: draw),
                  const SizedBox(width: _gap),
                  SizedBox(
                    width: cell,
                    child: Column(children: [
                      SizedBox(height: h, child: write),
                      const SizedBox(height: _gap),
                      SizedBox(height: h, child: clock),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: _gap),
              row([timer, gif, music]),
              // Tools that stay live from the phone get their own shelf, so
              // nobody expects them to run with the phone away.
              const Padding(
                padding: EdgeInsets.fromLTRB(2, 24, 2, 10),
                child: Align(alignment: Alignment.centerLeft, child: MonoLabel('Live from your phone')),
              ),
              row([nowPlaying, glance, notifications]),
              const SizedBox(height: _gap),
              SizedBox(height: cell.clamp(0.0, 116.0), width: double.infinity, child: play),
            ]);
          }),
        ),
      );
}

/// The hairline panel every studio tool sits in.
class _ToolPanel extends StatelessWidget {
  const _ToolPanel({required this.label, required this.onTap, required this.padding, required this.child});

  final String label;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Lb.panel,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel)),
            side: Lb.hairline,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

Widget _toolLine(String line) => Text(
      line.toUpperCase(),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: LbType.label,
    );

/// A wide strip: name on the left, the tool's demo running wide beside it.
class _StudioBanner extends StatelessWidget {
  const _StudioBanner({
    required this.label,
    required this.line,
    required this.generator,
    required this.onTap,
  });

  final String label, line;
  final Generator generator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ToolPanel(
        label: label,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(children: [
          Expanded(flex: 3, child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                  child: Text(label, maxLines: 1, style: LbType.title)),
              const SizedBox(height: 3),
              _toolLine(line),
            ],
          )),
          const SizedBox(width: 14),
          Expanded(flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: LedLoop(
                generator: generator,
                width: 24,
                height: 12,
                borderRadius: Lb.rTile,
              ),
            ),
          ),
        ]),
      );
}

class _StudioTile extends StatelessWidget {
  const _StudioTile({
    required this.label,
    required this.generator,
    required this.onTap,
    this.line,
    this.lineWidget,
    this.big = false,
  });

  final String label;
  final String? line;
  final Widget? lineWidget;
  final Generator generator;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) => _ToolPanel(
        label: label,
        onTap: onTap,
        padding: EdgeInsets.all(big ? 14 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: LedLoop(
                  generator: generator,
                  glow: big,
                  bezel: big,
                  borderRadius: big ? Lb.rControl : Lb.rTile,
                ),
              ),
            ),
            SizedBox(height: big ? 12 : 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label, maxLines: 1, style: big ? LbType.title : LbType.heading),
            ),
            const SizedBox(height: 3),
            lineWidget ?? _toolLine(line ?? ''),
          ],
        ),
      );
}
