import 'package:flutter/material.dart';

import '../../library/catalog_store.dart';
import '../../features/device/widgets/common.dart';
import '../design/parts.dart';
import '../design/toggle.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../make/studio_kit.dart';
import '../scope.dart';

class CatalogUpdatesScreen extends StatelessWidget {
  const CatalogUpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).catalogStore;
    if (store == null) {
      return const StudioScaffold(title: 'New animations', body: SizedBox());
    }
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => _content(context, store),
    );
  }

  Widget _content(BuildContext context, CatalogStore store) => StudioScaffold(
    title: 'New animations',
    body: ListView(
      padding: const EdgeInsets.all(Lb.gutter),
      children: [
        Text('More light, without an app update.', style: LbType.title),
        const SizedBox(height: 12),
        Text(
          store.enabled
              ? 'Checks contact ${store.remote!.url.host}, the static animation catalog. '
                    'Glyph sends no device details, notifications or analytics. '
                    'Downloaded animations stay available offline.'
              : 'Catalog delivery is being prepared. The bundled library is available offline.',
          style: LbType.body,
        ),
        const SizedBox(height: 24),
        LbPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MonoLabel('Library'),
              const SizedBox(height: 8),
              Text(
                '${store.catalog.items.length} looks · ${store.downloaded} downloaded',
                style: LbType.body,
              ),
              if (store.revision > 0)
                Text('Content revision ${store.revision}', style: LbType.small),
              if (store.lastAttempt case final date?)
                Text('Last check: ${_date(date)}', style: LbType.small),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: store.enabled && store.ready && !store.checking
                    ? store.check
                    : null,
                icon: Icon(
                  store.checking
                      ? Icons.hourglass_top_sharp
                      : Icons.refresh_sharp,
                  size: 18,
                ),
                label: Text(
                  store.checking ? 'Checking…' : 'Check for new animations',
                ),
              ),
              if (store.message case final message?) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  style: LbType.small.copyWith(
                    color: store.failed ? Lb.text2 : Lb.text,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        LbToggleTile(
          title: 'Daily automatic checks',
          subtitle: 'Off by default. Checks once a day while Glyph is open; no background service.',
          value: store.automatic,
          onChanged: store.enabled && store.ready ? store.setAutomatic : null,
        ),
        if (store.dropped.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            '${store.dropped.length} entries need a newer app or a corrected catalog. '
            'Compatible animations are available.',
            style: LbType.small,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Lb.gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SheetTitle('Skipped entries'),
                      SelectableText(
                        store.dropped.join('\n'),
                        style: LbType.mono,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            child: const Text('View skipped entries'),
          ),
        ],
      ],
    ),
  );

  static String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}
