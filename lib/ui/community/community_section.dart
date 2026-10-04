import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/community.dart';
import '../../app/whats_new.dart';
import '../../features/device/widgets/common.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import 'whats_new_sheet.dart';

/// Device tab → Community: feedback, ideas and setups on GitHub, plus the
/// app's version. Needs no device.
class CommunitySection extends StatelessWidget {
  const CommunitySection({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  static const _out = Icon(Icons.open_in_new_sharp, color: Lb.text3, size: 18);
  static const _more = Icon(Icons.chevron_right_sharp, color: Lb.text3);

  static Widget _icon(IconData i) => Icon(i, color: Lb.text2, size: 20);

  @override
  Widget build(BuildContext context) {
    final discord = Community.discordInvite;
    return PanelSection(
      label: 'Community',
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RowGroup(
            children: [
              Row1(
                leading: _icon(Icons.bug_report_sharp),
                title: 'Send feedback',
                subtitle: 'Something not right? Tell us on GitHub',
                trailing: _more,
                onTap: () => sendFeedback(context),
              ),
              Row1(
                leading: _icon(Icons.auto_awesome_sharp),
                title: 'Suggest an animation',
                subtitle: 'Something you\'d love to see on your device',
                trailing: _out,
                onTap: () => _withEnv(context, (d) => Community.animationRequest(d)),
              ),
              Row1(
                leading: _icon(Icons.grid_on_sharp),
                title: 'Request support for your display',
                subtitle: 'A panel or controller Glyph doesn\'t handle yet',
                trailing: _out,
                onTap: () => openCommunityLink(context, Community.displayRequest()),
              ),
              Row1(
                leading: _icon(Icons.photo_camera_sharp),
                title: 'Share your setup',
                subtitle: 'Show what yours looks like',
                trailing: _out,
                onTap: () => openCommunityLink(context, Community.showAndTell),
              ),
              Row1(
                leading: _icon(Icons.map_sharp),
                title: 'Roadmap',
                subtitle: 'What\'s coming next',
                trailing: _out,
                onTap: () => openCommunityLink(context, Community.roadmap),
              ),
              if (discord != null)
                Row1(
                  leading: _icon(Icons.forum_sharp),
                  title: 'Chat on Discord',
                  trailing: _out,
                  onTap: () => openCommunityLink(context, Uri.parse(discord)),
                ),
              Row1(
                leading: _icon(Icons.new_releases_sharp),
                title: 'What\'s new',
                trailing: _more,
                onTap: () => _showNotes(context),
              ),
            ],
          ),
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
    );
  }

  static Future<void> _withEnv(BuildContext context, Uri Function(Diagnostics) build) async {
    final s = AppScope.of(context);
    final env = await Community.env();
    if (!context.mounted) return;
    await openCommunityLink(context, build(Diagnostics.capture(env, s.devices, streaming: s.playback.isStreaming)));
  }

  /// This version's notes, or the latest ones bundled.
  static Future<void> _showNotes(BuildContext context) async {
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
