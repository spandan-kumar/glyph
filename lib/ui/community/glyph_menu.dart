import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/community.dart';
import '../../app/whats_new.dart';
import '../../features/device/widgets/common.dart';
import '../design/parts.dart';
import '../tune/stage_deck.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import 'whats_new_sheet.dart';
import 'catalog_updates_screen.dart';

/// The Glyph menu: community, help and the app itself, one tap from every
/// tab (top-right of each header). The same links also appear where they're
/// needed: Report on errors, Suggest one when a search finds nothing, Show
/// it off after a send, Request support when setting up a device.
class GlyphMenuKey extends StatelessWidget {
  const GlyphMenuKey({super.key});

  @override
  Widget build(BuildContext context) =>
      SquareKey(icon: Icons.more_horiz_sharp, label: 'Community & help', onTap: () => showGlyphMenu(context));
}

Future<void> showGlyphMenu(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _GlyphMenu(parent: context),
    );

class _GlyphMenu extends StatelessWidget {
  const _GlyphMenu({required this.parent});

  /// Outlives the sheet: actions run on it after the sheet closes.
  final BuildContext parent;

  static const _out = Icon(Icons.open_in_new_sharp, color: Lb.text3, size: 18);
  static const _more = Icon(Icons.chevron_right_sharp, color: Lb.text3);

  static Widget _icon(IconData i) => Icon(i, color: Lb.text2, size: 20);

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String title, String? subtitle, Widget trailing, void Function(BuildContext) action) =>
        Row1(
          leading: _icon(icon),
          title: title,
          subtitle: subtitle,
          trailing: trailing,
          onTap: () {
            Navigator.pop(context);
            if (parent.mounted) action(parent);
          },
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetTitle('Glyph', subtitle: 'Free and open source, made with the community.'),
            const MonoLabel('Community'),
            const SizedBox(height: 8),
            RowGroup(children: [
              row(Icons.forum_sharp, 'Chat on Discord', 'Help, ideas and beta builds', _out,
                  (c) => openCommunityLink(c, Community.discord)),
              row(Icons.photo_camera_sharp, 'Share your setup', 'Show what yours looks like', _out,
                  (c) => openCommunityLink(c, Community.showAndTell)),
              row(Icons.map_sharp, 'Roadmap', 'What\'s coming next', _out,
                  (c) => openCommunityLink(c, Community.roadmap)),
            ]),
            const SizedBox(height: 20),
            const MonoLabel('Help & feedback'),
            const SizedBox(height: 8),
            RowGroup(children: [
              row(Icons.bug_report_sharp, 'Send feedback', 'Something not right? Tell us on GitHub', _more,
                  sendFeedback),
              row(Icons.auto_awesome_sharp, 'Suggest an animation', 'Something you\'d love to see', _out,
                  (c) => suggestAnimation(c)),
              row(Icons.grid_on_sharp, 'Request display support', 'A panel or controller Glyph doesn\'t handle yet',
                  _out, requestDisplaySupport),
            ]),
            const SizedBox(height: 20),
            const MonoLabel('Glyph'),
            const SizedBox(height: 8),
            RowGroup(children: [
              row(Icons.download_sharp, 'New animations', 'Catalog updates & daily checks', _more,
                  (c) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const CatalogUpdatesScreen()))),
              row(Icons.new_releases_sharp, 'What\'s new', null, _more, showWhatsNew),
              row(Icons.code_sharp, 'Source code', 'MIT licence · GitHub', _out,
                  (c) => openCommunityLink(c, Uri.parse(Community.repo))),
            ]),
            const SizedBox(height: 14),
            FutureBuilder(
              future: Community.env(),
              builder: (context, snap) {
                final v = snap.data?.version ?? '';
                return Text(
                  '${v.isEmpty ? 'Glyph' : 'Glyph $v'} · Free & open source · MIT',
                  textAlign: TextAlign.center,
                  style: LbType.mono.copyWith(color: Lb.text3),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the animation request form, pre-filled with the panel size and,
/// when given, what to draw.
Future<void> suggestAnimation(BuildContext context, {String? idea}) async {
  final s = AppScope.of(context);
  final env = await Community.env();
  if (!context.mounted) return;
  final d = Diagnostics.capture(env, s.devices, streaming: s.playback.isStreaming);
  await openCommunityLink(context, Community.animationRequest(d, idea: idea));
}

Future<void> requestDisplaySupport(BuildContext context) =>
    openCommunityLink(context, Community.displayRequest());

/// This version's notes, or the latest ones bundled.
Future<void> showWhatsNew(BuildContext context) async {
  final env = await Community.env();
  if (!context.mounted) return;
  var version = env.version;
  var lines = whatsNewNotes[version];
  if (lines == null && whatsNewNotes.isNotEmpty) {
    version = whatsNewNotes.keys.first;
    lines = whatsNewNotes[version];
  }
  if (lines == null) return toast(context, 'No notes for this version.');
  await showWhatsNewSheet(context, version, lines);
}

/// A snackbar action that opens Send feedback for what just went wrong. It
/// runs after the snackbar's own screen may be gone, so it uses the app's
/// root context.
SnackBarAction reportAction(BuildContext context) {
  final root = Navigator.maybeOf(context, rootNavigator: true)?.context ?? context;
  return SnackBarAction(label: 'Report', onPressed: () {
    if (root.mounted) sendFeedback(root);
  });
}

/// Opens [uri] in the browser; if that fails, copies it instead.
Future<void> openCommunityLink(BuildContext context, Uri uri) async {
  final ok = await Community.launcher(uri);
  if (ok || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: uri.toString()));
  if (context.mounted) toast(context, 'Couldn\'t open a browser. The link is copied.');
}

/// Gathers diagnostics and shows exactly what a report will include before
/// anything leaves the phone.
Future<void> sendFeedback(BuildContext context) async {
  final s = AppScope.of(context);
  final env = await Community.env();
  if (!context.mounted) return;
  final d = Diagnostics.capture(env, s.devices, streaming: s.playback.isStreaming);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _FeedbackSheet(diagnostics: d, parent: context),
  );
}

class _FeedbackSheet extends StatelessWidget {
  const _FeedbackSheet({required this.diagnostics, required this.parent});

  final Diagnostics diagnostics;

  /// Outlives the sheet, for opening the link and toasts after it closes.
  final BuildContext parent;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle(
            'Send feedback',
            subtitle: 'Opens a report on GitHub with these details filled in. '
                'You\'ll describe what happened there; posting needs a free GitHub account.',
          ),
          const MonoLabel('Included'),
          const SizedBox(height: 8),
          LbPanel(
            padding: const EdgeInsets.all(12),
            child: SelectableText(diagnostics.text, style: LbType.mono.copyWith(height: 1.5)),
          ),
          const SizedBox(height: 8),
          Text(
            'No names, addresses or Wi-Fi details. Nothing is sent until you post it.',
            style: LbType.small.copyWith(color: Lb.text3),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new_sharp, size: 18),
            label: const Text('Open GitHub'),
            onPressed: () {
              Navigator.pop(context);
              openCommunityLink(parent, Community.feedback(diagnostics));
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_sharp, size: 18),
            label: const Text('Copy instead'),
            onPressed: () async {
              Navigator.pop(context);
              await Clipboard.setData(ClipboardData(text: diagnostics.text));
              if (parent.mounted) toast(parent, 'Details copied.');
            },
          ),
        ],
      ),
    ),
  );
}
