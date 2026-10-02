import 'package:flutter/material.dart';

import '../../app/devices.dart';
import '../../ui/scope.dart';
import '../../ui/theme.dart';
import 'catalog.dart';
import 'core/game.dart';
import 'game_page.dart';
import 'high_scores.dart';
import 'widgets/attract_preview.dart';

/// Size previews to the connected matrix (16×16 without one), shrunk to the
/// same logical grid the game would use on big panels.
(int, int) previewSize(DeviceStore devices) {
  final caps = devices.caps;
  if (caps == null || caps.height < 4 || caps.width < 4) return (16, 16);
  final s = (caps.width < caps.height ? caps.width : caps.height) ~/ 16;
  return s > 1 ? (caps.width ~/ s, caps.height ~/ s) : (caps.width, caps.height);
}

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  final _best = <String, int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final g in gameDefs) {
      final v = await HighScores.get(HighScores.key(g.id));
      if (!mounted) return;
      setState(() => _best[g.id] = v);
    }
  }

  Future<void> _open(GameDef def) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GamePage(def: def)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final devices = AppScope.of(context).devices;
    return Scaffold(
      appBar: AppBar(title: const Text('Games')),
      body: ListenableBuilder(
        listenable: devices,
        builder: (context, _) {
          final (w, h) = previewSize(devices);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: gameDefs.length,
            itemBuilder: (context, i) {
              final def = gameDefs[i];
              return _GameCard(
                def: def,
                width: w,
                height: h,
                best: _best[def.id] ?? 0,
                onTap: () => _open(def),
              );
            },
          );
        },
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.def,
    required this.width,
    required this.height,
    required this.best,
    required this.onTap,
  });

  final GameDef def;
  final int width, height, best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: GlyphColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: GlyphColors.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: AttractPreview(def: def, width: width, height: height),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Text(def.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (best > 0)
                    Text('$best',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: GlyphColors.warning)),
                ]),
                Text(def.blurb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: GlyphColors.textMuted)),
              ],
            ),
          ),
        ),
      );
}
