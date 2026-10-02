import 'package:flutter/material.dart';

import '../../app/creations.dart';
import '../../features/audio/audio_screen.dart';
import '../../features/editor/editor_screen.dart';
import '../../features/games/games_screen.dart';
import '../../features/import/import_screen.dart';
import '../../features/text/text_studio_screen.dart';
import '../actions.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets/led_matrix_view.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  static final _tools = <(IconData, String, String, Widget Function())>[
    (Icons.brush_outlined, 'Pixel editor', 'Draw frame-by-frame', () => const EditorScreen()),
    (Icons.text_fields, 'Scrolling text', 'Messages and signs', () => const TextStudioScreen()),
    (Icons.schedule, 'Clock', 'Time, date, countdowns', () => const TextStudioScreen(mode: 'clock')),
    (Icons.gif_box_outlined, 'Import', 'Any GIF or image', () => const ImportScreen()),
    (Icons.graphic_eq, 'Music', 'Reacts to sound', () => const AudioScreen()),
    (Icons.sports_esports_outlined, 'Games', 'Phone as controller', () => const GamesScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final creations = AppScope.of(context).creations;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: creations,
        builder: (context, _) => CustomScrollView(
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Text('Create',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 112,
                ),
                itemCount: _tools.length,
                itemBuilder: (context, i) {
                  final (icon, title, subtitle, page) = _tools[i];
                  return _ToolCard(
                    icon: icon,
                    title: title,
                    subtitle: subtitle,
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => page())),
                  );
                },
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 28, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Text('MY CREATIONS',
                    style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: GlyphColors.textMuted)),
              ),
            ),
            if (creations.items.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Text('Things you draw, import or write show up here.',
                      style: TextStyle(color: GlyphColors.textMuted)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: creations.items.length,
                  itemBuilder: (context, i) => _CreationTile(creation: creations.items[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard(
      {required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: GlyphColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: GlyphColors.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: GlyphColors.primary),
                const Spacer(),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: GlyphColors.textMuted)),
              ],
            ),
          ),
        ),
      );
}

class _CreationTile extends StatelessWidget {
  const _CreationTile({required this.creation});

  final Creation creation;

  void _open(BuildContext context) {
    final page = switch (creation.kind) {
      'drawing' => EditorScreen(initial: creation),
      'text' => TextStudioScreen(
          initial: creation, mode: creation.meta['mode'] as String? ?? 'text'),
      _ => null,
    };
    if (page != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => GlyphActions.playClip(context, creation.clip, creation.title),
      onLongPress: () => showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Play'),
              onTap: () {
                Navigator.pop(ctx);
                GlyphActions.playClip(context, creation.clip, creation.title);
              },
            ),
            if (creation.kind == 'drawing' || creation.kind == 'text')
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(ctx);
                  _open(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Save to matrix'),
              onTap: () {
                Navigator.pop(ctx);
                GlyphActions.saveClipToDevice(context, creation.clip, creation.title);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: GlyphColors.danger),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                AppScope.of(context).creations.delete(creation.id);
              },
            ),
          ]),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(
              child: LedMatrixView(frame: creation.clip.frames.first, borderRadius: 10),
            ),
          ),
          const SizedBox(height: 6),
          Text(creation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
