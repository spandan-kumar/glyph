import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/community.dart';
import '../community/glyph_menu.dart';

import '../../app/creations.dart';
import '../../engine/clip.dart';
import '../../features/editor/editor_screen.dart';
import '../../features/import/sharing.dart';
import '../../features/text/text_studio_screen.dart';
import '../actions.dart';
import '../design/parts.dart';
import '../design/toggle.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import 'led_loop.dart';
import 'community_share.dart';
import 'studio_kit.dart';
import '../design/route.dart';

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
/// device; the share key beside its name shares it; long-press opens all
/// its actions.
class CreationTile extends StatelessWidget {
  const CreationTile({super.key, required this.creation});

  static const shareKeyId = ValueKey('creation-share');

  final Creation creation;

  @override
  Widget build(BuildContext context) {
    final c = creation;
    return Semantics(
      button: true,
      label: '${c.title}, ${creationKindLabel(c)}',
      child: InkWell(
        borderRadius: BorderRadius.circular(Lb.rTile),
        onTap: () => _play(context, c),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LbType.small.copyWith(color: Lb.text)),
                    Text(creationKindLabel(c).toUpperCase(),
                        maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: LbType.label),
                  ]),
                ),
                // Kept small so three tiles still fit across a 360 px phone;
                // a near miss lands on the tile and only plays it.
                SizedBox(
                  width: 44,
                  height: 36,
                  child: IconButton(
                    key: shareKeyId,
                    tooltip: 'Share',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    color: Lb.text2,
                    onPressed: () => showCreationShare(context, c),
                    icon: const Icon(Icons.ios_share_sharp),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Plays a creation; buzzes harder when the device itself changes.
void _play(BuildContext context, Creation c) {
  AppScope.of(context).devices.isConnected
      ? HapticFeedback.mediumImpact()
      : HapticFeedback.lightImpact();
  GlyphActions.playClip(context, c.clip, c.title);
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

/// Play, Edit, Send to device, Share, (community), Delete.
Future<void> showCreationActions(BuildContext context, Creation c) {
  final editable = c.kind == 'drawing' || c.kind == 'text';
  return showStudioActions(
    context,
    header: _sheetHeader(c),
    actions: [
      StudioAction(Icons.play_arrow_sharp, 'Play', () => _play(context, c)),
      if (editable) StudioAction(Icons.edit_sharp, 'Edit', () => openCreation(context, c)),
      StudioAction(Icons.save_alt_sharp, 'Send to device', () => keepOnMatrix(context, c),
          subtitle: 'Plays without your phone'),
      StudioAction(Icons.ios_share_sharp, 'Share', () => showCreationShare(context, c),
          subtitle: 'As a GIF, a Glyph file or on Discord'),
      if (c.kind == 'drawing')
        StudioAction(Icons.public_sharp, 'Share with the community', () => showCommunityShare(context, c),
            subtitle: 'Everyone with Glyph can play it'),
      StudioAction(Icons.delete_outline_sharp, 'Delete', () => deleteCreation(context, c), danger: true),
    ],
  );
}

Widget _sheetHeader(Creation c) => Row(children: [
      SizedBox.square(dimension: 56, child: Center(child: _ClipLoop(clip: c.clip, title: c.title))),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: LbType.title),
          const SizedBox(height: 4),
          MonoLabel('${creationKindLabel(c)} · ${c.clip.width}×${c.clip.height}'),
        ]),
      ),
    ]);

/// Share a creation: as a GIF through the system sheet (with an optional
/// caption and link, remembered), as an editable Glyph file, or on the
/// Glyph Discord. The art itself is never watermarked.
Future<void> showCreationShare(BuildContext context, Creation c) async {
  final caption = ValueNotifier(await ShareCaptionPref.get());
  if (!context.mounted) return caption.dispose();
  await showStudioActions(
    context,
    header: _sheetHeader(c),
    extra: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ValueListenableBuilder(
        valueListenable: caption,
        builder: (context, on, _) => LbToggleTile(
          title: 'Add a caption',
          subtitle: '“$shareCaption” and a link',
          value: on,
          onChanged: (v) {
            caption.value = v;
            ShareCaptionPref.set(v);
          },
        ),
      ),
    ),
    actions: [
      StudioAction(Icons.gif_box_sharp, 'Share as GIF', () => shareCreationAsGif(context, c, caption: caption.value),
          subtitle: 'Plays in any chat'),
      StudioAction(Icons.description_outlined, 'Share Glyph file',
          () => shareCreationFile(context, c, caption: caption.value),
          subtitle: 'Opens editable in Glyph'),
      StudioAction(Icons.photo_camera_sharp, 'Post in Show and tell',
          () => openCommunityLink(context, Community.showAndTell),
          subtitle: 'On the Glyph Discord'),
    ],
  );
  caption.dispose();
}

/// Opens the tool a creation was made with.
void openCreation(BuildContext context, Creation c) {
  final page = switch (c.kind) {
    'drawing' => EditorScreen(initial: c),
    'text' => TextStudioScreen(initial: c, mode: c.meta['mode'] as String? ?? 'text'),
    _ => null,
  };
  if (page != null) Navigator.of(context).push(lbRoute((_) => page));
}

Future<void> keepOnMatrix(BuildContext context, Creation c) async {
  if (AppScope.of(context).devices.caps == null) {
    studioNoDevice(context);
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
