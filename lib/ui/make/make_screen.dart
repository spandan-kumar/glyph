import 'package:flutter/material.dart';

import '../../engine/clip.dart';
import '../../engine/generator.dart';
import '../../features/audio/audio_screen.dart';
import '../../features/editor/editor_screen.dart';
import '../../features/games/catalog.dart';
import '../../features/games/games_screen.dart';
import '../../features/import/import_screen.dart';
import '../../features/text/text_studio_screen.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import 'creation_tile.dart';
import 'demos.dart';
import 'led_loop.dart';
import 'studio_kit.dart';

/// Make: a studio of tools that demo themselves, then everything you've made.
class MakeScreen extends StatefulWidget {
  const MakeScreen({super.key});

  @override
  State<MakeScreen> createState() => _MakeScreenState();
}

class _MakeScreenState extends State<MakeScreen> {
  // Built once so the previews keep running across rebuilds.
  final _draw = ClipGenerator(drawDemoClip, title: 'Draw');
  final _write = writeDemo();
  final _clock = clockDemo();
  final _gif = ClipGenerator(gifDemoClip, title: 'Bring a GIF');
  final _music = musicDemo();
  final _play = playDemo();

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

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
                    Text('Make', style: LbType.display),
                    const SizedBox(height: 8),
                    Text('Draw it, write it, bring it — it shows up on your matrix.',
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
                      lineWidget: connected ? const LivePulse(label: 'Draws live on your matrix') : null,
                      generator: _draw,
                      onTap: () => _open(const EditorScreen(blank: true)),
                    ),
                    write: _StudioTile(
                      label: 'Write',
                      line: 'Say it big',
                      generator: _write,
                      onTap: () => _open(const TextStudioScreen()),
                    ),
                    clock: _StudioTile(
                      label: 'Clock',
                      line: 'Tick tock',
                      generator: _clock,
                      onTap: () => _open(const TextStudioScreen(mode: 'clock')),
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
                    play: _StudioTile(
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

/// Draw is the big one (2×2); Write and Clock stack beside it; the rest
/// sit in a row underneath.
class _StudioGrid extends StatelessWidget {
  const _StudioGrid({
    required this.draw,
    required this.write,
    required this.clock,
    required this.gif,
    required this.music,
    required this.play,
  });

  final Widget draw, write, clock, gif, music, play;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LayoutBuilder(builder: (context, c) {
            final cell = (c.maxWidth - 2 * _gap) / 3;
            final h = cell * 1.36;
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
              SizedBox(
                height: h,
                child: Row(children: [
                  SizedBox(width: cell, child: gif),
                  const SizedBox(width: _gap),
                  SizedBox(width: cell, child: music),
                  const SizedBox(width: _gap),
                  SizedBox(width: cell, child: play),
                ]),
              ),
            ]);
          }),
        ),
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
  Widget build(BuildContext context) {
    return Semantics(
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
        child: InkWell(
          onTap: onTap,
          child: Padding(
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
                  child: Text(label, maxLines: 1, style: LbType.heading),
                ),
                const SizedBox(height: 3),
                lineWidget ??
                    Text(
                      (line ?? '').toUpperCase(),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: LbType.label,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
