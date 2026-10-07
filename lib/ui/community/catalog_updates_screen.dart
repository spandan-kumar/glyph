import 'package:flutter/material.dart';

import '../../app/community.dart';
import '../../library/catalog_store.dart';
import '../design/led_text.dart';
import '../design/parts.dart';
import '../design/toggle.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../make/studio_kit.dart';
import '../scope.dart';
import 'glyph_menu.dart';

/// New animations without an app update: how many there are, whether this
/// copy is up to date, a check-now button and the once-a-day switch. New
/// arrivals show up on Display's "Just added" shelf.
class CatalogUpdatesScreen extends StatelessWidget {
  const CatalogUpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).catalogStore;
    if (store == null) return const StudioScaffold(title: 'New animations', body: SizedBox());
    return ListenableBuilder(listenable: store, builder: (context, _) => _content(context, store));
  }

  Widget _content(BuildContext context, CatalogStore store) {
    final accent = readAccent(context);
    final (status, statusColor) = !store.enabled
        ? ('New animations arrive with app updates for now.', Lb.text2)
        : store.checking
            ? ('Checking…', Lb.text2)
            : store.needsNewerApp
                ? ('There are new animations for a newer Glyph.', Lb.phosphor)
                : store.failed
                    ? ('Couldn\'t check — are you online?', Lb.text2)
                    : store.lastAttempt == null
                        ? ('Not checked yet.', Lb.text2)
                        : ('Up to date · checked ${_ago(store.lastAttempt!)}', Lb.text2);
    return StudioScaffold(
      title: 'New animations',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Lb.gutter, 8, Lb.gutter, 40),
        children: [
          Center(child: LedText('${store.catalog.items.length}', dot: 7, color: accent)),
          const SizedBox(height: 10),
          Center(child: MonoLabel('animations on this phone')),
          if (store.downloaded > 0) ...[
            const SizedBox(height: 4),
            Center(child: MonoLabel('${store.downloaded} added since your last update')),
          ],
          const SizedBox(height: 22),
          Text(status, textAlign: TextAlign.center, style: LbType.body.copyWith(color: statusColor)),
          if (store.message case final message? when !store.failed && !store.needsNewerApp) ...[
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center, style: LbType.small),
          ],
          const SizedBox(height: 20),
          if (store.needsNewerApp)
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => openCommunityLink(context, Community.latestRelease),
              icon: const Icon(Icons.open_in_new_sharp, size: 18),
              label: const Text('Get the latest Glyph'),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: store.enabled && store.ready && !store.checking ? store.check : null,
              icon: store.checking ? const LedSpinner(size: 16) : const Icon(Icons.refresh_sharp, size: 18),
              label: Text(store.checking ? 'Checking…' : 'Check now'),
            ),
          const SizedBox(height: 16),
          LbPanel(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: LbToggleTile(
              title: 'Check once a day',
              subtitle: 'Only while Glyph is open',
              value: store.automatic,
              onChanged: store.enabled && store.ready ? store.setAutomatic : null,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            store.enabled
                ? 'New animations come from ${store.remote!.url.host} and are signed, so only official Glyph '
                    'animations get in. Glyph sends nothing about you or your device; like any download, the '
                    'server sees your connection\'s address.'
                : 'When this switches on, new animations will download straight into your library — no app '
                    'update needed.',
            style: LbType.small.copyWith(color: Lb.text3),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return d.inDays == 1 ? 'yesterday' : '${d.inDays} days ago';
  }
}
