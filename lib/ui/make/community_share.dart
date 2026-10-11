import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/community.dart';
import '../../app/creations.dart';
import '../../engine/clip.dart';
import '../../library/community_design.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'led_loop.dart';
import 'studio_kit.dart';

/// Past this length GitHub and some browsers drop a prefilled link, so the
/// design travels on the clipboard instead.
const communityMaxUrlLength = 7000;

/// The community-design issue form, prefilled. The query keys are the field
/// ids in .github/ISSUE_TEMPLATE/community_design.yml; keep them in step.
/// A null [token] leaves the Design box empty.
Uri communityDesignUrl(String title, String? token) {
  String enc(String s) => Uri.encodeComponent(s);
  return Uri.parse(
    '${Community.repo}/issues/new?template=community_design.yml&labels=community-design'
    '&title=${enc('Community design: $title')}&name=${enc(title)}'
    '${token == null ? '' : '&design=${enc(token)}'}',
  );
}

/// Opens the share sheet for a drawing.
Future<void> showCommunityShare(BuildContext context, Creation c) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CommunityShareSheet(title: c.title, clip: c.clip),
  );
}

class CommunityShareSheet extends StatefulWidget {
  const CommunityShareSheet({
    super.key,
    required this.title,
    required this.clip,
  });

  final String title;
  final FrameClip clip;

  @override
  State<CommunityShareSheet> createState() => _CommunityShareSheetState();
}

class _CommunityShareSheetState extends State<CommunityShareSheet> {
  late final _name = TextEditingController(
    text: CommunityDesign.cleanTitle(widget.title),
  );
  bool _copied = false, _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// What would be shared right now, or why it can't be.
  (CommunityDesign?, String?) _convert() {
    try {
      return (CommunityDesign.fromClip(widget.clip, title: _name.text), null);
    } on CommunityDesignException catch (e) {
      return (null, e.message);
    }
  }

  Future<void> _continue(CommunityDesign design) async {
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    final token = design.encode();
    final full = communityDesignUrl(design.title, token);
    final long = full.toString().length > communityMaxUrlLength;
    if (long) await Clipboard.setData(ClipboardData(text: token));
    final ok = await Community.launcher(
      long ? communityDesignUrl(design.title, null) : full,
    );
    if (!mounted) return;
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: full.toString()));
      if (!mounted) return;
      setState(() => _busy = false);
      studioToast(context, 'Couldn’t open a browser. The link is copied.');
      return;
    }
    if (long) {
      setState(() {
        _busy = false;
        _copied = true;
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (design, error) = _convert();
    final empty = CommunityDesign.cleanTitle(_name.text).isEmpty;
    final preview = design?.toClip();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Share with the community', style: LbType.title),
              const SizedBox(height: 14),
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Lb.panel,
                    borderRadius: BorderRadius.circular(Lb.rPanel),
                    border: const Border.fromBorderSide(Lb.hairline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: SizedBox.square(
                      dimension: 132,
                      child: preview == null
                          ? null
                          : Center(
                              child: LedLoop(
                                generator: ClipGenerator(
                                  preview,
                                  title: design!.title,
                                ),
                                width: preview.width,
                                height: preview.height,
                                resetKey: preview,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                maxLength: CommunityDesign.maxTitle,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              Text(
                'You’ll finish on GitHub. After a quick review, everyone with Glyph can play it.',
                style: LbType.small,
              ),
              const SizedBox(height: 10),
              Text(
                'Share only drawings you made. It’s released as CC0, so anyone can use it. '
                'Your GitHub username is shown as credit unless you choose a name there.',
                style: LbType.small.copyWith(color: Lb.text3),
              ),
              if (error != null && !empty) ...[
                const SizedBox(height: 12),
                Text(error, style: LbType.small.copyWith(color: Lb.danger)),
              ],
              if (_copied) ...[
                const SizedBox(height: 12),
                Text(
                  'Your design is copied. Paste it into the Design box on GitHub.',
                  style: LbType.small.copyWith(color: Lb.ok),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                style: studioCtaStyle,
                onPressed: design == null || _busy
                    ? null
                    : () => _continue(design),
                child: Text(
                  _copied ? 'Open GitHub again' : 'Continue on GitHub',
                ),
              ),
              if (empty) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Give it a name to continue.',
                    style: LbType.small,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
