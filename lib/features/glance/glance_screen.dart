import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/background.dart';
import '../../engine/generator.dart';
import '../../ui/design/parts.dart';
import '../../ui/design/toggle.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/led_loop.dart';
import '../../ui/make/studio_kit.dart';
import '../../ui/scope.dart';
import '../../ui/widgets/led_matrix_view.dart';
import 'glance_model.dart';
import 'glance_session.dart';
import 'glance_store.dart';
import 'phone_show_editor.dart';
import 'weather.dart';

class GlanceScreen extends StatefulWidget {
  const GlanceScreen({super.key});
  @override
  State<GlanceScreen> createState() => _GlanceScreenState();
}

class _GlanceScreenState extends State<GlanceScreen>
    with WidgetsBindingObserver {
  GlanceSession? _session;
  bool _visible = true, _starting = false;
  final _owned = Set<Generator>.identity();
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
        if (identical(session.playback.generator, generator)) {
          unawaited(session.stop());
        }
      });
    }
    super.dispose();
  }

  Future<void> _play(Generator g) async {
    final s = _session!;
    if (!s.devices.isConnected) {
      goToMatrix(context);
      return;
    }
    setState(() => _starting = true);
    _owned.add(g);
    final ok = await s.start(g);
    if (!mounted) return;
    setState(() => _starting = false);
    if (!ok) {
      studioToast(
        context,
        'Couldn\'t show it. Check that your device is on and reachable.',
      );
    }
  }

  Future<void> _edit({
    GlanceCard? card,
    GlanceKind kind = GlanceKind.counter,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GlanceCardEditor(
          session: _session!,
          card: card,
          kind: card?.kind ?? kind,
        ),
      ),
    );
  }

  void _show([PhoneShow? show]) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PhoneShowEditor(session: _session!, show: show),
    ),
  );
  Future<void> _delete(String id, bool show) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(show ? 'Delete this Show?' : 'Delete this card?'),
        content: Text(
          show
              ? 'The items in it stay in Glyph.'
              : 'Shows will skip this card until you remove its entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (show) {
      await _session!.store.deleteShow(id);
    } else {
      await _session!.store.deleteCard(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) {
      return const StudioScaffold(title: 'Glance', body: SizedBox());
    }
    return StudioScaffold(
      title: 'Glance',
      body: ListenableBuilder(
        listenable: Listenable.merge([
          s,
          s.weather,
          s.devices,
          BackgroundStreaming.running,
        ]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 32),
          children: [
            Text('Little things, live', style: LbType.heading),
            const SizedBox(height: 6),
            Text(
              'Weather, days that matter, and Shows that bring them together. Needs your phone on your device\'s Wi-Fi.',
              style: LbType.body,
            ),
            const SizedBox(height: 18),
            if (s.ownsPlayback) ...[
              Center(
                child: SizedBox(
                  width: 200,
                  child: LedMatrixView(
                    frame: s.playback.frame,
                    repaint: s.playback.frameTick,
                    glow: true,
                    bezel: true,
                    borderRadius: Lb.rControl,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(s.playback.generator!.name, style: LbType.bodyStrong),
              Text(
                s.playing && s.playback.isStreaming
                    ? 'On your device · needs your phone'
                    : 'Stopped',
                style: LbType.small,
              ),
              if (s.playing)
                OutlinedButton.icon(
                  onPressed: s.stop,
                  icon: const Icon(Icons.stop_sharp),
                  label: const Text('Stop'),
                ),
              if (BackgroundStreaming.supported)
                LbToggleTile(
                  title: 'Keep running in background',
                  subtitle: s.background
                      ? 'Running · Stop is also in the phone notification'
                      : 'Off · stops when you leave this screen or background Glyph',
                  value: s.background || s.startingBackground,
                  onChanged:
                      s.playing &&
                          s.playback.isStreaming &&
                          !s.startingBackground
                      ? (v) async {
                          final ok = await s.setBackground(v);
                          if (!ok && context.mounted) {
                            studioToast(
                              context,
                              'Couldn\'t start background playback. Keep Glyph open to show this.',
                            );
                          }
                        }
                      : null,
                ),
              Text(
                'Closing Glyph from recent apps ends playback. Your device returns to its own look. Start again here next time.',
                style: LbType.small,
              ),
              const SizedBox(height: 24),
            ],
            StudioGroup(
              label: 'Cards',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!s.store.loaded)
                    const Text('Loading…')
                  else if (s.store.cards.isEmpty)
                    Text(
                      'Add a place or a date to begin.',
                      style: LbType.small,
                    ),
                  for (final card in s.store.cards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 60,
                                child: LedLoop(
                                  generator: s.cardGenerator(card),
                                  resetKey: card,
                                  glow: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(card.title, style: LbType.bodyStrong),
                                    Text(
                                      cardStatus(s, card),
                                      style: LbType.small,
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Card options',
                                shape: studioMenuShape,
                                onSelected: (v) => v == 'edit'
                                    ? _edit(card: card)
                                    : _delete(card.id, false),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: _starting
                                ? null
                                : () => _play(s.cardGenerator(card)),
                            icon: const Icon(Icons.play_arrow_sharp),
                            label: const Text('Show on device'),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: s.store.loaded && s.store.cards.length < 24
                            ? () => _edit(kind: GlanceKind.weather)
                            : null,
                        icon: const Icon(Icons.wb_sunny_outlined),
                        label: const Text('Add weather'),
                      ),
                      OutlinedButton.icon(
                        onPressed: s.store.loaded && s.store.cards.length < 24
                            ? () => _edit()
                            : null,
                        icon: const Icon(Icons.event_sharp),
                        label: const Text('Add counter'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            StudioGroup(
              label: 'Shows · needs your phone',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Line up cards, library looks and things you made. Unavailable entries are skipped; if none can play, the display shows -- and retries.',
                    style: LbType.small,
                  ),
                  for (final show in s.store.shows) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(show.title, style: LbType.bodyStrong),
                              Text(
                                '${show.entries.length} items · loops · needs your phone',
                                style: LbType.small,
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Phone Show options',
                          shape: studioMenuShape,
                          onSelected: (v) => v == 'edit'
                              ? _show(show)
                              : _delete(show.id, true),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: _starting
                          ? null
                          : () => _play(s.showGenerator(show)),
                      icon: const Icon(Icons.play_arrow_sharp),
                      label: const Text('Show on device'),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: s.store.loaded && s.store.shows.length < 12
                        ? () => _show()
                        : null,
                    icon: const Icon(Icons.add_sharp),
                    label: const Text('New phone Show'),
                  ),
                  Text(
                    'Shows in Device → Shows run on your device without the phone.',
                    style: LbType.small,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String cardStatus(GlanceSession s, GlanceCard c) {
  if (c.kind == GlanceKind.counter) {
    return '${c.counterLabel(DateTime.now())} · phone timezone';
  }
  final w = s.weather.snapshot(c.place!),
      status = s.weather.freshness(c.place!);
  if (status == WeatherFreshness.unavailable) {
    return s.weather.refreshing(c.place!)
        ? 'Fetching weather…'
        : 'Weather unavailable · check connection';
  }
  final time = w!.observed.toLocal();
  return '${w.temperature(c.fahrenheit).round()}°${c.fahrenheit ? 'F' : 'C'} · ${weatherDescription(w.code)}\n${status == WeatherFreshness.stale ? 'Last known · ' : ''}${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class GlanceCardEditor extends StatefulWidget {
  const GlanceCardEditor({
    super.key,
    required this.session,
    required this.kind,
    this.card,
  });
  final GlanceSession session;
  final GlanceKind kind;
  final GlanceCard? card;
  @override
  State<GlanceCardEditor> createState() => _GlanceCardEditorState();
}

class _GlanceCardEditorState extends State<GlanceCardEditor>
    with WidgetsBindingObserver {
  late final _title = TextEditingController(
    text:
        widget.card?.title ??
        (widget.kind == GlanceKind.weather ? 'Weather' : 'Days to go'),
  );
  final _query = TextEditingController(),
      _lat = TextEditingController(),
      _lon = TextEditingController();
  late final _id = widget.card?.id ?? GlanceStore.newId();
  late WeatherPlace? _place = widget.card?.place;
  late DateTime _date =
      widget.card?.date ?? DateTime.now().add(const Duration(days: 30));
  late CounterMode _mode = widget.card?.mode ?? CounterMode.until;
  late bool _fahrenheit = widget.card?.fahrenheit ?? false;
  List<WeatherPlace> _results = [];
  bool _searching = false, _saving = false, _manual = false;
  int _searchGeneration = 0;
  String? _error;
  GlanceCard get _card => GlanceCard(
    id: _id,
    title: _title.text.trim(),
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
    if (_place != null) {
      _query.text = _place!.name;
      _lat.text = '${_place!.latitude}';
      _lon.text = '${_place!.longitude}';
      _choose(_place!);
    }
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
    _title.dispose();
    _query.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });
    try {
      final places = await widget.session.weather.api.search(_query.text);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = places;
        if (places.isEmpty) {
          _error = 'No places found. Try a nearby city or coordinates.';
        }
      });
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        setState(
          () =>
              _error = 'Couldn\'t search. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  void _coordinates() {
    final place = WeatherPlace(
      _query.text.trim(),
      double.tryParse(_lat.text) ?? double.nan,
      double.tryParse(_lon.text) ?? double.nan,
    );
    if (!place.valid) {
      setState(
        () => _error = 'Enter a place name, latitude (−90 to 90) and longitude (−180 to 180).',
      );
      return;
    }
    setState(() {
      _error = null;
      _choose(place);
    });
  }

  Future<void> _save() async {
    if (!_card.valid) {
      setState(
        () => _error =
            'Give this card a title and ${widget.kind == GlanceKind.weather ? 'choose a place' : 'choose a date'}.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.store.saveCard(_card);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn\'t save this card. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => StudioScaffold(
    title: widget.kind == GlanceKind.weather ? 'Weather card' : 'Days counter',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 32),
      children: [
        if (widget.kind == GlanceKind.counter || _place != null) ...[
          Center(
            child: SizedBox(
              width: 180,
              child: LedLoop(
                generator: widget.session.cardGenerator(_card),
                resetKey: _card.toJson().toString(),
                glow: true,
                bezel: true,
                borderRadius: Lb.rControl,
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        StudioGroup(
          label: 'Card',
          child: TextField(
            controller: _title,
            maxLength: 64,
            decoration: const InputDecoration(labelText: 'Title'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (widget.kind == GlanceKind.counter)
          StudioGroup(
            label: 'Date · phone timezone',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<CounterMode>(
                  style: studioSegmentStyle,
                  segments: const [
                    ButtonSegment(
                      value: CounterMode.until,
                      label: Text('Until'),
                    ),
                    ButtonSegment(
                      value: CounterMode.since,
                      label: Text('Since'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() => _mode = v.first),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime(_date.year, _date.month, _date.day),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200, 12, 31),
                    );
                    if (date != null && mounted) setState(() => _date = date);
                  },
                  icon: const Icon(Icons.event_sharp),
                  label: Text(
                    '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                  ),
                ),
                Text(
                  '${_card.counterLabel(DateTime.now())}. Updates at midnight in the phone\'s timezone, even if you travel. Works offline.',
                  style: LbType.small,
                ),
              ],
            ),
          )
        else ...[
          StudioGroup(
            label: 'Place',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Search and weather refresh send the chosen place or coordinates to Open-Meteo. No phone location permission is used.',
                  style: LbType.small,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _query,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'City or place name',
                  ),
                  onChanged: (_) {
                    _searchGeneration++;
                    setState(() {
                      _searching = false;
                      _results = [];
                    });
                  },
                ),
                LbToggleTile(
                  title: 'Use coordinates',
                  value: _manual,
                  onChanged: (v) => setState(() {
                    _manual = v;
                    _searchGeneration++;
                    _searching = false;
                    _results = [];
                    _error = null;
                  }),
                ),
                if (_manual) ...[
                  TextField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                  ),
                  TextField(
                    controller: _lon,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                  ),
                  OutlinedButton(
                    onPressed: _coordinates,
                    child: const Text('Use this place'),
                  ),
                ] else
                  OutlinedButton.icon(
                    onPressed: _searching || _query.text.trim().length < 2
                        ? null
                        : _search,
                    icon: _searching
                        ? const LedSpinner(size: 18)
                        : const Icon(Icons.search_sharp),
                    label: Text(_searching ? 'Searching…' : 'Search'),
                  ),
                for (final place in _results)
                  InkWell(
                    onTap: () => setState(() {
                      _choose(place);
                      _results = [];
                      _error = null;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(place.name, style: LbType.body),
                    ),
                  ),
                if (_place != null) ...[
                  const SizedBox(height: 8),
                  Text('Chosen: ${_place!.name}', style: LbType.bodyStrong),
                ],
              ],
            ),
          ),
          StudioGroup(
            label: 'Weather',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  style: studioSegmentStyle,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Celsius')),
                    ButtonSegment(value: true, label: Text('Fahrenheit')),
                  ],
                  selected: {_fahrenheit},
                  onSelectionChanged: (v) =>
                      setState(() => _fahrenheit = v.first),
                ),
                if (_place != null)
                  ListenableBuilder(
                    listenable: widget.session.weather,
                    builder: (context, _) {
                      final weather = widget.session.weather,
                          w = weather.snapshot(_place!);
                      String degrees(double n) =>
                          '${(_fahrenheit ? n * 9 / 5 + 32 : n).round()}°';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          Text(
                            cardStatus(widget.session, _card),
                            style: LbType.body,
                          ),
                          if (w != null &&
                              w.dailyIsToday(DateTime.now()) &&
                              weather.freshness(_place!) !=
                                  WeatherFreshness.unavailable &&
                              (w.high != null || w.low != null))
                            Text(
                              'Today${w.high == null ? '' : ' · high ${degrees(w.high!)}'}${w.low == null ? '' : ' · low ${degrees(w.low!)}'}',
                              style: LbType.small,
                            ),
                          OutlinedButton(
                            onPressed: weather.refreshing(_place!)
                                ? null
                                : () => weather.refresh(_place!, force: true),
                            child: const Text('Refresh weather'),
                          ),
                        ],
                      );
                    },
                  ),
                Text(
                  'Refreshes every 15 minutes while used; manual refresh is limited to once a minute. Offline readings show OLD; after two hours they become unavailable. Weather follows the chosen place\'s local day.',
                  style: LbType.small,
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () =>
                          launchUrl(Uri.parse('https://open-meteo.com/')),
                      child: const Text('Weather by Open-Meteo'),
                    ),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(
                          'https://creativecommons.org/licenses/by/4.0/',
                        ),
                      ),
                      child: const Text('CC BY 4.0'),
                    ),
                    TextButton(
                      onPressed: () =>
                          launchUrl(Uri.parse('https://www.geonames.org/')),
                      child: const Text('Places by GeoNames'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: LbType.small.copyWith(color: Lb.danger),
            ),
          ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save card'),
        ),
        const SizedBox(height: 8),
        Text(
          'Saved on your phone. Show it live from Glance; it needs your phone to stay current.',
          style: LbType.small,
        ),
      ],
    ),
  );
}
