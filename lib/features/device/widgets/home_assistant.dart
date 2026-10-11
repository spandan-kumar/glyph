import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/community.dart';
import '../../../ui/design/parts.dart';
import '../../../ui/design/tokens.dart';
import '../../../ui/design/type.dart';
import '../device_manager.dart';
import 'common.dart';

/// Where the guide lives; the blueprints it describes sit next to it.
final homeAssistantGuide = Uri.parse(
  '${Community.repo}/blob/main/docs/HOME_ASSISTANT.md',
);

/// The names Home Assistant lists for this device: the stored name as the
/// device holds it (not Glyph's tidied display name), system items left out.
({List<String> looks, List<String> shows}) homeAssistantNames(DeviceManager m) {
  List<String> names(Iterable<dynamic> items) => [
    for (final p in items)
      if (p.body['n'] is String && (p.body['n'] as String).trim().isNotEmpty)
        (p.body['n'] as String).trim(),
  ];
  return (
    looks: names(keptItems(m)),
    shows: names(m.playlists.where((p) => !m.isSystem(p))),
  );
}

/// A quiet row under Saved that opens the Home Assistant sheet.
class HomeAssistantLink extends StatelessWidget {
  const HomeAssistantLink({super.key, required this.manager});

  final DeviceManager manager;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(Lb.rControl),
      onTap: () => showHomeAssistantSheet(context, manager),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Lb.touch),
        child: Row(
          children: [
            const Icon(Icons.home_outlined, size: 18, color: Lb.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Use with Home Assistant',
                style: LbType.body.copyWith(color: Lb.text2),
              ),
            ),
            const Icon(Icons.chevron_right_sharp, size: 18, color: Lb.text3),
          ],
        ),
      ),
    ),
  );
}

Future<void> showHomeAssistantSheet(
  BuildContext context,
  DeviceManager manager,
) {
  HapticFeedback.selectionClick();
  final names = homeAssistantNames(manager);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: HomeAssistantSheet(looks: names.looks, shows: names.shows),
      ),
    ),
  );
}

/// Explains the blueprint in two lines and lists the exact names to paste.
class HomeAssistantSheet extends StatelessWidget {
  const HomeAssistantSheet({
    super.key,
    required this.looks,
    required this.shows,
  });

  final List<String> looks;
  final List<String> shows;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SheetTitle(
        'Use with Home Assistant',
        subtitle:
            'Home Assistant finds your device on its own. Import the Glyph blueprint, '
            'then type one of these names exactly to play it from an automation.',
      ),
      if (looks.isEmpty && shows.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Nothing is saved on your device yet.',
            style: LbType.body.copyWith(color: Lb.text2),
          ),
        ),
      if (looks.isNotEmpty) ...[
        const MonoLabel('Saved'),
        for (final n in looks) _NameRow(name: n),
        const SizedBox(height: 12),
      ],
      if (shows.isNotEmpty) ...[
        const MonoLabel('Shows'),
        for (final n in shows) _NameRow(name: n),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 4),
      FilledButton(
        onPressed: () async {
          final ok = await Community.launcher(homeAssistantGuide);
          if (!ok && context.mounted) {
            toast(context, 'Couldn\'t open the guide');
          }
        },
        child: const Text('Open the guide'),
      ),
    ],
  );
}

class _NameRow extends StatefulWidget {
  const _NameRow({required this.name});

  final String name;

  @override
  State<_NameRow> createState() => _NameRowState();
}

class _NameRowState extends State<_NameRow> {
  Future<void> _copy() async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: widget.name));
    if (mounted) toast(context, 'Copied');
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: Lb.touch),
    decoration: const BoxDecoration(border: Border(bottom: Lb.hairline)),
    child: Row(
      children: [
        Expanded(child: Text(widget.name, style: LbType.body)),
        IconButton(
          tooltip: 'Copy ${widget.name}',
          constraints: const BoxConstraints(
            minWidth: Lb.touch,
            minHeight: Lb.touch,
          ),
          icon: const Icon(Icons.copy_sharp, size: 18, color: Lb.text2),
          onPressed: _copy,
        ),
      ],
    ),
  );
}
