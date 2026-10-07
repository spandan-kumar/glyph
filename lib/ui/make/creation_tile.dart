import 'package:flutter/material.dart';

import '../../app/community.dart';
import '../community/glyph_menu.dart';

import '../../app/creations.dart';
import '../../engine/clip.dart';
import '../../features/editor/editor_screen.dart';
import '../../features/import/sharing.dart';
import '../../features/text/text_studio_screen.dart';
import '../actions.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import 'led_loop.dart';
import 'studio_kit.dart';

/// What kind of thing a creation is, in plain words.
String creationKindLabel(Creation c) => switch (c.kind) {
      'drawing' => 'Drawing',
      'text' => switch (c.meta['mode']) {
          'clock' => 'Clock',
          'countdown' => 'Timer',
          _ => 'Words',
        },
      'import' => 'GIF',
      _ => c.kind,
    };

/// A creation as a small LED panel playing itself. Tap plays it on the
/// device; long-press opens its actions.
class CreationTile extends StatelessWidget {
  const CreationTile({super.key, required this.creation});

  final Creation creation;

  @override
  Widget build(BuildContext context) {
    final c = creation;
    return Semantics(
      button: true,
      label: '${c.title}, ${creationKindLabel(c)}',
      child: InkWell(
        borderRadius: BorderRadius.circular(Lb.rTile),
        onTap: () => GlyphActions.playClip(context, c.clip, c.title),
        onLongPress: () => showCreationActions(context, c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Lb.panel,
                  borderRadius: BorderRadius.circular(Lb.rTile),
                  border: Border.fromBorderSide(Lb.hairline),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(child: _ClipLoop(clip: c.clip, title: c.title)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LbType.small.copyWith(color: Lb.text)),
            Text(creationKindLabel(c).toUpperCase(),
                maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: LbType.label),
          ],
        ),
      ),
    );
  }
}

class _ClipLoop extends StatelessWidget {
  const _ClipLoop({required this.clip, required this.title});

  final FrameClip clip;
  final String title;

  @override
  Widget build(BuildContext context) => LedLoop(
        generator: ClipGenerator(clip, title: title),
        width: clip.width,
        height: clip.height,
        resetKey: clip,
      );
}

/// Play, Edit, Send to device, Share as GIF, Share Glyph file, Delete.
Future<void> showCreationActions(BuildContext context, Creation c) {
  final editable = c.kind == 'drawing' || c.kind == 'text';
  return showStudioActions(
    context,
    header: Row(children: [
      SizedBox.square(dimension: 56, child: Center(child: _ClipLoop(clip: c.clip, title: c.title))),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: LbType.title),
          const SizedBox(height: 4),
          MonoLabel('${creationKindLabel(c)} · ${c.clip.width}×${c.clip.height}'),
        ]),
      ),
    ]),
    actions: [
      StudioAction(Icons.play_arrow_sharp, 'Play',
          () => GlyphActions.playClip(context, c.clip, c.title)),
      if (editable) StudioAction(Icons.edit_sharp, 'Edit', () => openCreation(context, c)),
      StudioAction(Icons.save_alt_sharp, 'Send to device', () => keepOnMatrix(context, c),
          subtitle: 'Plays without your phone'),
      StudioAction(Icons.gif_box_sharp, 'Share as GIF', () => shareCreationAsGif(context, c)),
      StudioAction(Icons.ios_share_sharp, 'Share Glyph file', () => shareCreationFile(context, c),
          subtitle: 'Opens editable in Glyph'),
      StudioAction(Icons.photo_camera_sharp, 'Show it off', () => openCommunityLink(context, Community.showAndTell),
          subtitle: 'Post it in Show and tell'),
      StudioAction(Icons.delete_outline_sharp, 'Delete', () => deleteCreation(context, c), danger: true),
    ],
  );
}

/// Opens the tool a creation was made with.
void openCreation(BuildContext context, Creation c) {
  final page = switch (c.kind) {
    'drawing' => EditorScreen(initial: c),
    'text' => TextStudioScreen(initial: c, mode: c.meta['mode'] as String? ?? 'text'),
    _ => null,
  };
  if (page != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

Future<void> keepOnMatrix(BuildContext context, Creation c) async {
  if (AppScope.of(context).devices.caps == null) {
    studioToast(context, 'Connect a device to send this to it.',
        action: SnackBarAction(label: 'Connect', onPressed: () => goToMatrix(context)));
    return;
  }
  await GlyphActions.saveClipToDevice(context, c.clip, c.title);
}

Future<void> deleteCreation(BuildContext context, Creation c) async {
  final store = AppScope.of(context).creations;
  final messenger = ScaffoldMessenger.maybeOf(context);
  await store.delete(c.id);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Deleted “${c.title}”'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () =>
            store.save(id: c.id, title: c.title, kind: c.kind, clip: c.clip, meta: c.meta),
      ),
    ));
}
