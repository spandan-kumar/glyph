import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/ambient.dart';
import '../design/led_text.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import '../widgets/live_preview.dart';
import 'channels.dart';
import 'tune_controller.dart';

/// Space under a tile's panel for its title and category.
const tileTextHeight = 46.0;

/// A look as a bare LED panel with its name printed underneath — no card.
/// Tap tunes in (and the channel becomes the surf order); long-press hearts.
class LedTile extends StatefulWidget {
  const LedTile({super.key, required this.entry, required this.channel, this.onTuned, this.showKind = true});

  final TuneEntry entry;
  final Channel channel;

  /// Called after tuning in (e.g. to close a search page).
  final VoidCallback? onTuned;
  final bool showKind;

  @override
  State<LedTile> createState() => _LedTileState();
}

class _LedTileState extends State<LedTile> {
  final _panelKey = GlobalKey();
  bool _pop = false;

  void _tune() {
    final tune = TuneScope.read(context);
    final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      tune.onTunedFrom?.call(box.localToGlobal(Offset.zero) & box.size, widget.entry);
    }
    tune.tune(context, widget.channel, widget.entry);
    widget.onTuned?.call();
  }

  void _favourite() {
    final e = widget.entry;
    if (e is! ItemEntry) {
      HapticFeedback.selectionClick();
      return;
    }
    HapticFeedback.mediumImpact();
    final lib = TuneScope.read(context).library;
    final adding = !lib.isFavourite(e.item.id);
    lib.toggleFavourite(e.item.id);
    setState(() => _pop = adding);
    if (adding) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _pop = false);
      });
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(adding ? 'Hearted “${e.title}”.' : 'Out of your favourites.'),
        duration: const Duration(milliseconds: 1400),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final playback = AppScope.of(context).playback;
    final preview = switch (e) {
      ItemEntry(:final item) => LivePreview(item: item, bezel: true),
      CreationEntry() => LivePreview.generator(generator: e.generator, previewKey: e.key, bezel: true),
    };
    return Semantics(
      button: true,
      label: e.title,
      onLongPressHint: 'Heart',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tune,
        onLongPress: _favourite,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    key: _panelKey,
                    fit: StackFit.expand,
                    children: [
                      preview,
                      ListenableBuilder(
                        listenable: playback,
                        builder: (context, _) => e.isPlaying(playback) ? const _OnAirDot() : const SizedBox.shrink(),
                      ),
                      IgnorePointer(
                        child: AnimatedScale(
                          scale: _pop ? 1 : 0.4,
                          duration: Lb.medium,
                          curve: Curves.easeOutBack,
                          child: AnimatedOpacity(
                            opacity: _pop ? 1 : 0,
                            duration: Lb.fast,
                            child: const Center(child: LedHeart(dot: 5)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LbType.small.copyWith(color: Lb.text)),
            if (widget.showKind)
              Text(e.kind.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LbType.label.copyWith(fontSize: 9.5, letterSpacing: 0.8)),
          ],
        ),
      ),
    );
  }
}

/// The lit dot that marks the tile currently on the Stage.
class _OnAirDot extends StatelessWidget {
  const _OnAirDot();

  @override
  Widget build(BuildContext context) {
    final accent = AmbientScope.of(context).accent;
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          key: const ValueKey('on-air'),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
            border: Border.all(color: Lb.ink, width: 1),
            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.9), blurRadius: 8)],
          ),
        ),
      ),
    );
  }
}

/// A small heart drawn in LED dots.
class LedHeart extends StatelessWidget {
  const LedHeart({super.key, this.dot = 6, this.color = Lb.danger});

  final double dot;
  final Color color;

  static const rows = [
    '.##.##.',
    '#######',
    '#######',
    '.#####.',
    '..###..',
    '...#...',
  ];

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(rows.first.length * dot, rows.length * dot),
        painter: _HeartPainter(dot, color),
      );
}

class _HeartPainter extends CustomPainter {
  _HeartPainter(this.dot, this.color);

  final double dot;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, dot * 0.8);
    final on = Paint()..color = color;
    for (var y = 0; y < LedHeart.rows.length; y++) {
      final row = LedHeart.rows[y];
      for (var x = 0; x < row.length; x++) {
        if (row[x] != '#') continue;
        final c = Offset((x + 0.5) * dot, (y + 0.5) * dot);
        canvas.drawCircle(c, dot * 0.6, glow);
        canvas.drawCircle(c, dot * 0.4, on);
      }
    }
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.dot != dot || old.color != color;
}

/// Rail header: the channel name in lit LED dots, a mono count and
/// "See all". The channel you're surfing lights up in the room colour.
class RailHeader extends StatelessWidget {
  const RailHeader({super.key, required this.channel, this.onSeeAll});

  final Channel channel;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final id = TuneScope.of(context).channel.id;
    final tuned = id == channel.id || id == '${channel.id}/all';
    final accent = AmbientScope.of(context).accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Lb.gutter, 26, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    header: true,
                    label: channel.name,
                    child: LedText(channel.name.toUpperCase(), dot: 3, color: tuned ? accent : Lb.text),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${channel.all.length}', style: LbType.label),
              const Spacer(),
              if (onSeeAll != null)
                InkWell(
                  onTap: onSeeAll,
                  borderRadius: BorderRadius.circular(Lb.rControl),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text('SEE ALL', style: LbType.label.copyWith(color: Lb.text2)),
                  ),
                ),
            ],
          ),
          if (channel.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(channel.note!.toUpperCase(), style: LbType.label.copyWith(fontSize: 10)),
            ),
        ],
      ),
    );
  }
}

/// A channel as a lazy horizontal row of tiles.
class ChannelRail extends StatelessWidget {
  const ChannelRail({super.key, required this.channel, this.onSeeAll});

  static const tileWidth = 112.0;

  final Channel channel;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RailHeader(channel: channel, onSeeAll: onSeeAll),
        const SizedBox(height: 10),
        SizedBox(
          height: tileWidth + tileTextHeight,
          child: ListView.separated(
            key: PageStorageKey('rail:${channel.id}'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Lb.gutter),
            itemCount: channel.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(
              width: tileWidth,
              child: LedTile(entry: channel.items[i], channel: channel),
            ),
          ),
        ),
      ],
    );
  }
}

/// A grid of tiles sized so the panel stays square at any width.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.channel, required this.entries, this.onTuned});

  final Channel channel;
  final List<TuneEntry> entries;
  final VoidCallback? onTuned;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, constraints) {
      final w = constraints.crossAxisExtent - 2 * Lb.gutter;
      final cols = (w / 116).floor().clamp(3, 8);
      final tile = (w - (cols - 1) * 12) / cols;
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(Lb.gutter, 8, Lb.gutter, 32),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            mainAxisExtent: tile + tileTextHeight,
          ),
          itemCount: entries.length,
          itemBuilder: (context, i) => LedTile(entry: entries[i], channel: channel, onTuned: onTuned),
        ),
      );
    });
  }
}
