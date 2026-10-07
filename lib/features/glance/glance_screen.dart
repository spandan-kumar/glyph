import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/background.dart';
import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../../ui/design/parts.dart';
import '../../ui/design/toggle.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/led_loop.dart';
import '../../ui/make/studio_kit.dart';
import '../../ui/scope.dart';
import '../../ui/widgets/led_matrix_view.dart';
import 'glance_generator.dart';
import 'glance_model.dart';
import 'glance_session.dart';
import 'glance_store.dart';
import 'phone_show_editor.dart';
import 'weather.dart';

// Remembered for the session: Glance is mostly glanced at from across the
// room, so by default it keeps running after you leave the screen.
bool _wantBackground = true;

/// What the stage is showing when nothing of Glance is on the device yet.
sealed class _Focus {
  const _Focus();
}

class _CardFocus extends _Focus {
  const _CardFocus(this.id);
  final String id;
  @override
  bool operator ==(Object other) => other is _CardFocus && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class _RotationFocus extends _Focus {
  const _RotationFocus(this.id);
  final String id;
  @override
  bool operator ==(Object other) => other is _RotationFocus && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Glance: little live cards — the weather somewhere, the days to (or since)
/// something — and Rotations that cycle cards and looks.
///
/// Journey: see a card on the stage → put it on the device → add your own
/// (search a city, pick a date) → line several up in a Rotation.
class GlanceScreen extends StatefulWidget {
  const GlanceScreen({super.key});
  @override
  State<GlanceScreen> createState() => _GlanceScreenState();
}

class _GlanceScreenState extends State<GlanceScreen> with WidgetsBindingObserver {
  GlanceSession? _session;
  bool _visible = true, _starting = false;
  _Focus? _focus;
  final _owned = Set<Generator>.identity();
  // One generator per focused thing, so the stage doesn't restart on rebuild.
  Generator? _stageGenerator;
  Object? _stageKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) return;
    _session = AppScope.of(context).glance;
    _session?.store.addListener(_watch);
    _watch();
  }

  void _watch() {
    final s = _session;
    if (s == null || !_visible) return;
    s.weather.watch(this, [
      for (final c in s.store.cards)
        if (c.kind == GlanceKind.weather) c.place!,
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (_visible) {
      _watch();
    } else {
      _session?.weather.release(this);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.store.removeListener(_watch);
    _session?.weather.release(this);
    final session = _session, generator = session?.playback.generator;
    if (session != null && !session.background && _owned.contains(generator)) {
      scheduleMicrotask(() {
        if (identical(session.playback.generator, generator)) unawaited(session.stop());
      });
    }
    super.dispose();
  }

  GlanceCard? _card(String id) => _session!.store.cards.where((c) => c.id == id).firstOrNull;
  PhoneShow? _rotation(String id) => _session!.store.shows.where((s) => s.id == id).firstOrNull;

  /// The focused thing, falling back to the first card or rotation.
  _Focus? _current() {
    final s = _session!;
    final f = _focus;
    if (f is _CardFocus && _card(f.id) != null) return f;
    if (f is _RotationFocus && _rotation(f.id) != null) return f;
    if (s.store.cards.isNotEmpty) return _CardFocus(s.store.cards.first.id);
    if (s.store.shows.isNotEmpty) return _RotationFocus(s.store.shows.first.id);
    return null;
  }

  Generator? _generatorFor(_Focus? f) {
    final s = _session!;
    final key = switch (f) {
      _CardFocus(:final id) => _card(id),
      _RotationFocus(:final id) => _rotation(id),
      null => null,
    };
    if (key == null) return null;
    if (!identical(key, _stageKey)) {
      _stageKey = key;
      _stageGenerator = switch (key) {
        GlanceCard c => s.cardGenerator(c),
        PhoneShow r => s.showGenerator(r),
        _ => null,
      };
    }
    return _stageGenerator;
  }

  Future<void> _play(Generator g) async {
    final s = _session!;
    if (!s.devices.isConnected) return goToMatrix(context);
    HapticFeedback.mediumImpact(); // changes what the device shows
    setState(() => _starting = true);
    _owned.add(g);
    final ok = await s.start(g);
    if (!mounted) return;
    setState(() => _starting = false);
    if (!ok) {
      studioToast(context, 'Couldn\'t show it. Check that your device is on and reachable.');
      return;
    }
    if (_wantBackground && BackgroundStreaming.supported && !s.background) {
      await s.setBackground(true);
    }
  }

  Future<void> _toggleBackground(bool on) async {
    _wantBackground = on;
    final ok = await _session!.setBackground(on);
    if (!ok && on && mounted) {
      studioToast(context, 'Couldn\'t keep it running. Keep Glyph open to show this.');
    }
    if (mounted) setState(() {});
  }

  Future<void> _editCard({GlanceCard? card, GlanceKind kind = GlanceKind.counter}) async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => GlanceCardEditor(session: _session!, card: card, kind: card?.kind ?? kind),
      ),
    );
    if (id != null && mounted) setState(() => _focus = _CardFocus(id));
  }

  Future<void> _editRotation([PhoneShow? rotation]) async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => RotationEditor(session: _session!, show: rotation)),
    );
    if (id != null && mounted) setState(() => _focus = _RotationFocus(id));
  }

  Future<void> _delete(_Focus f) async {
    final s = _session!;
    final rotation = f is _RotationFocus;
    final name = switch (f) {
      _CardFocus(:final id) => _card(id)?.title,
      _RotationFocus(:final id) => _rotation(id)?.title,
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “$name”?'),
        content: Text(rotation ? 'The cards and looks in it stay.' : 'Rotations that use it will skip it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    switch (f) {
      case _CardFocus(:final id):
        await s.store.deleteCard(id);
      case _RotationFocus(:final id):
        await s.store.deleteShow(id);
    }
    if (mounted) setState(() => _focus = null);
  }

  void _actions(_Focus f) {
    final g = _generatorFor(f);
    showStudioActions(context, actions: [
      if (g != null) StudioAction(Icons.play_arrow_sharp, 'Show on device', () => _play(g)),
      StudioAction(Icons.edit_sharp, 'Edit', () {
        switch (f) {
          case _CardFocus(:final id):
            _editCard(card: _card(id));
          case _RotationFocus(:final id):
            _editRotation(_rotation(id));
        }
      }),
      StudioAction(Icons.delete_outline_sharp, 'Delete', () => _delete(f), danger: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) return const StudioScaffold(title: 'Glance', body: SizedBox());
    return StudioScaffold(
      title: 'Glance',
      body: ListenableBuilder(
        listenable: Listenable.merge([s, s.store, s.weather, s.devices, BackgroundStreaming.running]),
        builder: (context, _) {
          final focus = _current();
          final generator = _generatorFor(focus);
          final live = s.ownsPlayback && s.playing;
          final showingFocus = live && identical(s.playback.generator, generator);
          final (title, line) = switch (focus) {
            _CardFocus(:final id) => (_card(id)!.title, cardStatus(s, _card(id)!)),
            _RotationFocus(:final id) => (_rotation(id)!.title, rotationLine(_rotation(id)!)),
            null => ('Weather and the days that matter', 'Add a city or a date to make your first card.'),
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: live
                      ? LedMatrixView(
                          frame: s.playback.frame,
                          repaint: s.playback.frameTick,
                          glow: true,
                          bezel: true,
                          borderRadius: Lb.rControl,
                        )
                      : LedLoop(
                          key: ValueKey(generator ?? 'demo'),
                          generator: generator ?? glanceDemo(),
                          width: s.playback.frame.width,
                          height: s.playback.frame.height,
                          glow: true,
                          bezel: true,
                          borderRadius: Lb.rControl,
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(live ? s.playback.generator!.name : title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.title),
                    const SizedBox(height: 4),
                    if (live)
                      LivePulse(label: s.background ? 'On your device · keeps going' : 'On your device')
                    else
                      Text(line, style: LbType.small.copyWith(color: Lb.text2)),
                  ]),
                ),
                if (focus != null && !live)
                  IconButton(
                    style: studioIconStyle,
                    tooltip: 'More',
                    onPressed: () => _actions(focus),
                    icon: const Icon(Icons.more_horiz_sharp),
                  ),
              ]),
              const SizedBox(height: 16),
              if (live)
                Row(children: [
                  if (!showingFocus && generator != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _starting ? null : () => _play(generator),
                        icon: const Icon(Icons.play_arrow_sharp),
                        label: Text('Show “$title” instead', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          s.stop();
                        },
                        icon: const Icon(Icons.stop_sharp, size: 18),
                        label: const Text('Stop'),
                      ),
                    ),
                ])
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _starting
                      ? null
                      : generator == null
                          ? () => _editCard(kind: GlanceKind.weather)
                          : () => _play(generator),
                  icon: Icon(generator == null ? Icons.add_sharp : Icons.play_arrow_sharp),
                  label: Text(generator == null
                      ? 'Add your first card'
                      : s.devices.isConnected
                          ? 'Show on device'
                          : 'Connect a device to show it'),
                ),
              if (live && BackgroundStreaming.supported) ...[
                const SizedBox(height: 8),
                _BackgroundRow(
                  value: s.background || s.startingBackground,
                  enabled: s.playback.isStreaming && !s.startingBackground,
                  onChanged: _toggleBackground,
                ),
              ],
              const SizedBox(height: 28),
              Row(children: [
                const Expanded(child: MonoLabel('Your cards')),
                if (s.store.cards.isNotEmpty) MonoLabel('${s.store.cards.length}'),
              ]),
              const SizedBox(height: 10),
              _CardGrid(
                session: s,
                focus: focus,
                onFocus: (id) => setState(() => _focus = _CardFocus(id)),
                onActions: (id) => _actions(_CardFocus(id)),
                onAdd: s.store.loaded && s.store.cards.length < 24 ? (k) => _editCard(kind: k) : null,
              ),
              const SizedBox(height: 28),
              const MonoLabel('Rotations'),
              const SizedBox(height: 6),
              Text('Cycle cards, animations and things you made, a few seconds each.',
                  style: LbType.small.copyWith(color: Lb.text2)),
              const SizedBox(height: 10),
              _RotationList(
                session: s,
                focus: focus,
                onFocus: (id) => setState(() => _focus = _RotationFocus(id)),
                onActions: (id) => _actions(_RotationFocus(id)),
                onNew: s.store.loaded && s.store.shows.length < 12 ? () => _editRotation() : null,
              ),
              const SizedBox(height: 24),
              Text(
                'Glance plays live from your phone, so keep it on your device\'s Wi-Fi. '
                'For something that plays on its own, use Send on Display.',
                style: LbType.small.copyWith(color: Lb.text3),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BackgroundRow extends StatelessWidget {
  const _BackgroundRow({required this.value, required this.enabled, required this.onChanged});
  final bool value, enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => LbPanel(
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
        child: LbToggleTileCompat(
          title: 'Keep showing after you leave',
          subtitle: value ? 'Stop it here or from the notification' : 'Stops when you leave this screen',
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      );
}

/// Cards as LED tiles, plus the two ways to add one.
class _CardGrid extends StatelessWidget {
  const _CardGrid({
    required this.session,
    required this.focus,
    required this.onFocus,
    required this.onActions,
    required this.onAdd,
  });
  final GlanceSession session;
  final _Focus? focus;
  final ValueChanged<String> onFocus, onActions;
  final ValueChanged<GlanceKind>? onAdd;

  @override
  Widget build(BuildContext context) {
    final accent = readAccent(context);
    final cards = session.store.cards;
    final tiles = <Widget>[
      for (final c in cards)
        _Tile(
          key: ValueKey(c.id),
          selected: focus == _CardFocus(c.id),
          accent: accent,
          label: c.title,
          line: cardShortLine(session, c),
          onTap: () {
            HapticFeedback.selectionClick();
            onFocus(c.id);
          },
          onLongPress: () => onActions(c.id),
          child: LedLoop(generator: session.cardGenerator(c), resetKey: c, borderRadius: Lb.rTile),
        ),
      _AddTile(icon: Icons.wb_sunny_sharp, label: 'Weather', onTap: onAdd == null ? null : () => onAdd!(GlanceKind.weather)),
      _AddTile(icon: Icons.event_sharp, label: 'Countdown', onTap: onAdd == null ? null : () => onAdd!(GlanceKind.counter)),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 10,
      childAspectRatio: 0.72,
      children: tiles,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.selected,
    required this.accent,
    required this.label,
    required this.line,
    required this.onTap,
    required this.onLongPress,
    required this.child,
  });
  final bool selected;
  final Color accent;
  final String label, line;
  final VoidCallback onTap, onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: AnimatedContainer(
                duration: Lb.fast,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Lb.rControl),
                  border: Border.all(color: selected ? accent : Lb.line, width: selected ? 1.5 : 1),
                ),
                child: Center(child: AspectRatio(aspectRatio: 1, child: child)),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.small.copyWith(color: Lb.text)),
            Text(line.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.label),
          ]),
        ),
      );
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Add $label',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Lb.panel,
                  borderRadius: BorderRadius.circular(Lb.rControl),
                  border: Border.all(color: Lb.line),
                ),
                alignment: Alignment.center,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_sharp, size: 18, color: onTap == null ? Lb.text3 : Lb.text2),
                  const SizedBox(width: 4),
                  Icon(icon, size: 18, color: onTap == null ? Lb.text3 : Lb.text2),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: LbType.small.copyWith(color: Lb.text2)),
            Text('ADD', style: LbType.label),
          ]),
        ),
      );
}

class _RotationList extends StatelessWidget {
  const _RotationList({
    required this.session,
    required this.focus,
    required this.onFocus,
    required this.onActions,
    required this.onNew,
  });
  final GlanceSession session;
  final _Focus? focus;
  final ValueChanged<String> onFocus, onActions;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final accent = readAccent(context);
    return LbPanel(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (final r in session.store.shows) ...[
          InkWell(
            onTap: () => onFocus(r.id),
            onLongPress: () => onActions(r.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Lb.rTile),
                    border: Border.all(color: focus == _RotationFocus(r.id) ? accent : Lb.line),
                  ),
                  child: LedLoop(generator: session.showGenerator(r), resetKey: r, borderRadius: Lb.rTile),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.body),
                    Text(rotationLine(r), style: LbType.small),
                  ]),
                ),
                IconButton(
                  style: studioIconStyle,
                  tooltip: 'More',
                  onPressed: () => onActions(r.id),
                  icon: const Icon(Icons.more_horiz_sharp, color: Lb.text3),
                ),
              ]),
            ),
          ),
          const Divider(height: 1),
        ],
        InkWell(
          onTap: onNew,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.add_sharp, color: onNew == null ? Lb.text3 : Lb.text2),
              const SizedBox(width: 14),
              Text('New rotation', style: LbType.body.copyWith(color: onNew == null ? Lb.text3 : Lb.text)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// A toggle row without the default vertical padding of LbToggleTile.
class LbToggleTileCompat extends StatelessWidget {
  const LbToggleTileCompat({super.key, required this.title, this.subtitle, required this.value, this.onChanged});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: LbType.body),
                if (subtitle != null) Text(subtitle!, style: LbType.small),
              ]),
            ),
            const SizedBox(width: 12),
            LbToggle(value: value, onChanged: onChanged),
          ]),
        ),
      );
}

String rotationLine(PhoneShow r) {
  final total = r.entries.fold(0, (a, e) => a + e.seconds);
  final loop = total >= 60 ? '${(total / 60).toStringAsFixed(total % 60 == 0 ? 0 : 1)} min' : '$total s';
  return '${r.entries.length} ${r.entries.length == 1 ? 'item' : 'items'} · $loop loop';
}

/// One line for a card tile: "24° Goa", "12 days".
String cardShortLine(GlanceSession s, GlanceCard c) {
  if (c.kind == GlanceKind.counter) {
    final n = c.days(DateTime.now());
    return '$n ${n.abs() == 1 ? 'day' : 'days'}';
  }
  final w = s.weather.snapshot(c.place!);
  if (w == null || s.weather.freshness(c.place!) == WeatherFreshness.unavailable) return c.place!.name;
  return '${w.temperature(c.fahrenheit).round()}° ${c.place!.name}';
}

/// Status under the stage for a card.
String cardStatus(GlanceSession s, GlanceCard c) {
  if (c.kind == GlanceKind.counter) return c.counterLabel(DateTime.now());
  final place = c.place!;
  final w = s.weather.snapshot(place), status = s.weather.freshness(place);
  if (status == WeatherFreshness.unavailable) {
    return s.weather.refreshing(place) ? 'Getting the weather…' : 'No weather yet · check your connection';
  }
  final t = w!.fetched.toLocal();
  final at = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return '${w.temperature(c.fahrenheit).round()}°${c.fahrenheit ? 'F' : 'C'} · ${weatherDescription(w.code)} · '
      '${status == WeatherFreshness.stale ? 'last seen' : 'updated'} $at';
}

/// The stage's demo before there are any cards: a sunny day, then a
/// countdown — made-up values, never fetched.
Generator glanceDemo() => _GlanceDemo();

class _DemoWeather implements WeatherFeed {
  _DemoWeather();
  final _at = DateTime.now();
  @override
  WeatherSnapshot? snapshot(WeatherPlace place) =>
      WeatherSnapshot(observed: _at, fetched: _at, celsius: 29, code: 0, isDay: true, high: 31, low: 24);
  @override
  bool failed(WeatherPlace place) => false;
}

/// Alternates a made-up sunny city and a countdown, five seconds each.
class _GlanceDemo extends Generator {
  @override
  String get id => '_glance_demo';
  @override
  String get name => 'Glance';
  @override
  EffectInstance create(int width, int height, int seed) {
    final feed = _DemoWeather();
    final cards = [
      GlanceCardGenerator(
        GlanceCard(id: 'demo-w', title: 'Goa', kind: GlanceKind.weather, place: const WeatherPlace('Goa', 15.5, 73.8)),
        feed,
      ),
      GlanceCardGenerator(
        GlanceCard(
          id: 'demo-c',
          title: 'Trip',
          kind: GlanceKind.counter,
          date: DateTime.now().add(const Duration(days: 12)),
        ),
        feed,
      ),
    ];
    return _DemoInstance([for (final c in cards) c.create(width, height, seed)]);
  }
}

class _DemoInstance extends EffectInstance {
  _DemoInstance(this.parts);
  final List<EffectInstance> parts;
  @override
  void render(Frame out, double t, double dt, Params p, Palette pal) =>
      parts[(t ~/ 5) % parts.length].render(out, t, dt, p, pal);
}

/// Edits one card. Weather is search-first: type a city, pick a result, see
/// it on the stage. A countdown is a name and a date.
class GlanceCardEditor extends StatefulWidget {
  const GlanceCardEditor({super.key, required this.session, required this.kind, this.card});
  final GlanceSession session;
  final GlanceKind kind;
  final GlanceCard? card;
  @override
  State<GlanceCardEditor> createState() => _GlanceCardEditorState();
}

class _GlanceCardEditorState extends State<GlanceCardEditor> with WidgetsBindingObserver {
  late final _title = TextEditingController(text: widget.card?.title ?? '');
  final _query = TextEditingController(), _lat = TextEditingController(), _lon = TextEditingController();
  late final _id = widget.card?.id ?? GlanceStore.newId();
  late WeatherPlace? _place = widget.card?.place;
  late DateTime _date = widget.card?.date ?? DateTime.now().add(const Duration(days: 30));
  late CounterMode _mode = widget.card?.mode ?? CounterMode.until;
  late bool _fahrenheit = widget.card?.fahrenheit ?? false;
  // The title follows the city until someone types their own.
  late bool _titleEdited = widget.card != null;
  List<WeatherPlace> _results = [];
  bool _searching = false, _saving = false, _manual = false;
  int _searchGeneration = 0;
  Timer? _debounce;
  String? _error;

  bool get _weather => widget.kind == GlanceKind.weather;

  String get _effectiveTitle {
    final t = _title.text.trim();
    if (t.isNotEmpty) return t;
    if (_weather) return _place == null ? 'Weather' : shortPlace(_place!.name);
    return _mode == CounterMode.until ? 'Big day' : 'Since';
  }

  GlanceCard get _card => GlanceCard(
        id: _id,
        title: _effectiveTitle,
        kind: widget.kind,
        place: _place,
        fahrenheit: _fahrenheit,
        date: _date,
        mode: _mode,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_place != null) _choose(_place!);
  }

  void _choose(WeatherPlace place) {
    _place = place;
    widget.session.weather.watch(this, [place]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _place != null) {
      _choose(_place!);
    } else {
      widget.session.weather.release(this);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.weather.release(this);
    _debounce?.cancel();
    _title.dispose();
    _query.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  void _queryChanged(String text) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    if (text.trim().length < 2) {
      setState(() {
        _results = [];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(generation));
  }

  Future<void> _search(int generation) async {
    try {
      final places = await widget.session.weather.api.search(_query.text);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = places;
        _error = places.isEmpty ? 'No places found. Try a nearby city.' : null;
      });
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _error = 'Couldn\'t search. Check your connection.');
      }
    } finally {
      if (mounted && generation == _searchGeneration) setState(() => _searching = false);
    }
  }

  void _pick(WeatherPlace place) {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() {
      _choose(place);
      _results = [];
      _error = null;
      _query.clear();
      if (!_titleEdited) _title.clear();
    });
  }

  void _coordinates() {
    final place = WeatherPlace(
      _query.text.trim().isEmpty ? 'My place' : _query.text.trim(),
      double.tryParse(_lat.text) ?? double.nan,
      double.tryParse(_lon.text) ?? double.nan,
    );
    if (!place.valid) {
      setState(() => _error = 'Latitude is −90 to 90 and longitude −180 to 180.');
      return;
    }
    _pick(place);
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (!_card.valid) {
      setState(() => _error = _weather ? 'Search for a city first.' : 'Pick a date.');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.store.saveCard(_card);
      if (mounted) Navigator.pop(context, _id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn\'t save. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final ready = !_weather || _place != null;
    return StudioScaffold(
      title: widget.card == null ? (_weather ? 'New weather card' : 'New countdown') : 'Edit card',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: ready
                  ? LedLoop(
                      generator: s.cardGenerator(_card),
                      resetKey: _card.toJson().toString(),
                      width: s.playback.frame.width,
                      height: s.playback.frame.height,
                      glow: true,
                      bezel: true,
                      borderRadius: Lb.rControl,
                    )
                  : LedLoop(
                      generator: glanceDemo(),
                      width: s.playback.frame.width,
                      height: s.playback.frame.height,
                      glow: true,
                      bezel: true,
                      borderRadius: Lb.rControl,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (_weather && _place != null)
            ListenableBuilder(
              listenable: s.weather,
              builder: (context, _) => Text(
                cardStatus(s, _card),
                textAlign: TextAlign.center,
                style: LbType.small.copyWith(color: Lb.text2),
              ),
            )
          else if (!_weather)
            Text(_card.counterLabel(DateTime.now()),
                textAlign: TextAlign.center, style: LbType.small.copyWith(color: Lb.text2))
          else
            Text('Search for a city to see its weather here.',
                textAlign: TextAlign.center, style: LbType.small.copyWith(color: Lb.text2)),
          const SizedBox(height: 24),
          if (_weather) ..._weatherFields(s) else ..._counterFields(),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: LbType.small.copyWith(color: Lb.danger)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saving || !ready ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save card'),
          ),
          if (_weather) ...[
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
              _Credit('Weather by Open-Meteo', 'https://open-meteo.com/'),
              _Credit('CC BY 4.0', 'https://creativecommons.org/licenses/by/4.0/'),
              _Credit('Places by GeoNames', 'https://www.geonames.org/'),
            ]),
          ],
        ],
      ),
    );
  }

  List<Widget> _weatherFields(GlanceSession s) => [
        if (_place != null) ...[
          const MonoLabel('Place'),
          const SizedBox(height: 8),
          LbPanel(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            child: Row(children: [
              const Icon(Icons.place_sharp, size: 18, color: Lb.text2),
              const SizedBox(width: 10),
              Expanded(child: Text(_place!.name, style: LbType.body)),
              TextButton(
                onPressed: () => setState(() => _place = null),
                child: const Text('Change'),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          SegmentedButton<bool>(
            style: studioSegmentStyle,
          showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('°C')),
              ButtonSegment(value: true, label: Text('°F')),
            ],
            selected: {_fahrenheit},
            onSelectionChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _fahrenheit = v.first);
            },
          ),
          const SizedBox(height: 18),
          const MonoLabel('Name on the card'),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            maxLength: 64,
            decoration: InputDecoration(hintText: shortPlace(_place!.name), counterText: ''),
            onChanged: (_) => setState(() => _titleEdited = true),
          ),
        ] else ...[
          const MonoLabel('Which city?'),
          const SizedBox(height: 8),
          TextField(
            controller: _query,
            autofocus: widget.card == null,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search a city or town',
              prefixIcon: const Icon(Icons.search_sharp),
              suffixIcon: _searching
                  ? const Padding(padding: EdgeInsets.all(14), child: LedSpinner(size: 16))
                  : null,
            ),
            onChanged: _queryChanged,
            onSubmitted: (_) => _queryChanged(_query.text),
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 8),
            LbPanel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final (i, p) in _results.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  InkWell(
                    onTap: () => _pick(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(children: [
                        const Icon(Icons.place_sharp, size: 18, color: Lb.text3),
                        const SizedBox(width: 10),
                        Expanded(child: Text(p.name, style: LbType.body)),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 8),
          if (!_manual)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _manual = true),
                child: const Text('Can\'t find it? Enter coordinates'),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lon,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _coordinates, child: const Text('Use these coordinates')),
          ],
          const SizedBox(height: 8),
          Text(
            'Only the city you search for is sent to the weather service — Glyph never asks for your location.',
            style: LbType.small.copyWith(color: Lb.text3),
          ),
        ],
      ];

  List<Widget> _counterFields() => [
        const MonoLabel('What\'s the day?'),
        const SizedBox(height: 8),
        TextField(
          controller: _title,
          maxLength: 64,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Goa trip, Mia\'s birthday…', counterText: ''),
          onChanged: (_) => setState(() => _titleEdited = true),
        ),
        const SizedBox(height: 18),
        SegmentedButton<CounterMode>(
          style: studioSegmentStyle,
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: CounterMode.until, label: Text('Counting down to')),
            ButtonSegment(value: CounterMode.since, label: Text('Counting up since')),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _pickDate,
          icon: const Icon(Icons.event_sharp, size: 18),
          label: Text(friendlyDate(context, _date)),
        ),
        const SizedBox(height: 8),
        Text('Ticks over at midnight. Works without the internet.',
            style: LbType.small.copyWith(color: Lb.text3)),
      ];
}

class _Credit extends StatelessWidget {
  const _Credit(this.label, this.url);
  final String label, url;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => launchUrl(Uri.parse(url)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label.toUpperCase(), style: LbType.label),
        ),
      );
}

/// "Goa, Goa, India" → "Goa".
String shortPlace(String name) => name.split(',').first.trim();

/// "Fri, 6 Nov 2026" in the phone's locale.
String friendlyDate(BuildContext context, DateTime d) =>
    MaterialLocalizations.of(context).formatMediumDate(d) +
    (d.year == DateTime.now().year ? '' : ' ${d.year}');
