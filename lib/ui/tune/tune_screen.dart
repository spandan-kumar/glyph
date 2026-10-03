import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/devices.dart';
import '../../library/user_library.dart';
import '../actions.dart';
import '../design/ambient.dart';
import '../design/stage.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import '../screens/home_shell.dart';
import '../widgets/live_preview.dart';
import 'beam.dart';
import 'channels.dart';
import 'mini_stage.dart';
import 'pages.dart';
import 'stage_deck.dart';
import 'tiles.dart';
import 'tune_controller.dart';
import 'tweak_panel.dart';

/// Home: the Stage (a live mirror of the matrix) with the transport under
/// it, then Channels as rails. Swipe the Stage to surf, tap to Tweak,
/// Keep to beam the look onto the matrix. See docs/design/UX.md (J2–J4).
class TuneScreen extends StatefulWidget {
  const TuneScreen({super.key, this.now});

  /// Overrides the clock for "Right now" (tests, screenshots).
  final DateTime? now;

  /// shared_preferences key counting sessions that showed the swipe hint.
  static const swipeHintKey = 'tune.swipeHintSessions';

  @override
  State<TuneScreen> createState() => _TuneScreenState();
}

class _TuneScreenState extends State<TuneScreen> with TickerProviderStateMixin {
  final _scroll = ScrollController();
  final _stackKey = GlobalKey();
  final _stageKey = GlobalKey();
  final _glyphKey = GlobalKey();
  final _miniPanelKey = GlobalKey();
  final _mini = ValueNotifier(false);
  final UserLibrary _library = UserLibrary.shared;

  late final _tweak = AnimationController(vsync: this, duration: Lb.medium);
  late final _beam = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final _charge = AnimationController(vsync: this);
  late final _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  AppScope? _scope;
  TuneController? _tune;
  CatalogChannels? _base;
  List<Channel> _channels = const [];

  bool _tweakOpen = false;
  bool _hint = false;
  KeepState _keep = KeepState.idle;
  (Rect, Offset)? _beamPath;
  String? _autoId, _lastMarked;
  double _pull = 0;

  TuneController get tune => _tune!;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _library.addListener(_rebuildChannels);
    _library.load();
    _loadHint();
  }

  Future<void> _loadHint() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = p.getInt(TuneScreen.swipeHintKey) ?? 0;
      if (n >= 2) return;
      await p.setInt(TuneScreen.swipeHintKey, n + 1);
      if (mounted) setState(() => _hint = true);
    } catch (_) {
      // No prefs, no hint.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    if (identical(scope.playback, _scope?.playback) && identical(scope.catalog, _scope?.catalog)) {
      _scope = scope;
      return;
    }
    _scope?.playback.removeListener(_onPlayback);
    _scope?.creations.removeListener(_rebuildChannels);
    _scope?.devices.removeListener(_mirrorMatrix);
    _scope = scope;
    scope.playback.addListener(_onPlayback);
    scope.creations.addListener(_rebuildChannels);
    scope.devices.addListener(_mirrorMatrix);
    _base = CatalogChannels(scope.catalog, widget.now ?? DateTime.now());
    _tune?.dispose();
    _tune = TuneController(_base!.nowChannel, playback: scope.playback, library: _library)
      ..onTunedFrom = _flyFrom;
    _rebuildChannels();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoTune());
  }

  /// The Stage is never dead: with nothing playing, tune to the first
  /// "Right now" pick (on the phone only — we don't take over a matrix that
  /// may be playing something it keeps). If something is already playing,
  /// surf from the channel it belongs to.
  void _autoTune() {
    if (!mounted) return;
    final p = tune.playback;
    if (p.generator == null) {
      final first = _base!.nowChannel.items.firstOrNull;
      if (first is ItemEntry) {
        _autoId = first.item.id;
        p.playItem(first.item);
      }
      _mirrorMatrix();
      return;
    }
    for (final c in _channels) {
      final i = c.indexOfPlaying(p);
      if (i >= 0) return tune.adopt(c, index: i);
    }
  }

  /// The phone mirrors the matrix: if it's playing something Glyph kept and
  /// the user hasn't picked anything yet, show that instead of the
  /// automatic pick (so opening the app doesn't contradict the room).
  void _mirrorMatrix() {
    final scope = _scope;
    if (!mounted || scope == null) return;
    final p = scope.playback, gif = scope.devices.playingGif;
    if (gif == null || p.isStreaming || p.item?.id != _autoId) return;
    final match = scope.catalog.items.where((i) => keptFileName(i.title) == gif).firstOrNull;
    if (match == null || match.id == p.item?.id) return;
    _autoId = match.id;
    p.playItem(match);
    for (final c in _channels) {
      final k = c.indexOfPlaying(p);
      if (k >= 0) return tune.adopt(c, index: k);
    }
  }

  void _rebuildChannels() {
    final base = _base, scope = _scope;
    if (base == null || scope == null) return;
    final next = assembleChannels(
      base: base,
      favourites: _library.favourites,
      recents: _library.recents,
      creations: scope.creations.items,
    );
    if (mounted) setState(() => _channels = next);
  }

  /// Anything played from anywhere lands in "Lately" — except the
  /// automatic first pick and the Surprise reel.
  void _onPlayback() {
    final id = _scope?.playback.item?.id;
    if (id == null || id == _lastMarked || tune.shuffling) return;
    _lastMarked = id;
    if (id == _autoId) return;
    _library.markPlayed(id);
  }

  void _onScroll() {
    final box = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    bool show;
    if (box == null || !box.attached || !box.hasSize) {
      show = _scroll.offset > 420;
    } else {
      // Where the Stage sits in scroll terms (valid even when it's off-screen).
      final stageTop = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
      show = _scroll.offset > stageTop + box.size.height * 0.7;
    }
    if (show != _mini.value) _mini.value = show;
  }

  Future<void> _toTop() async {
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    await _scroll.animateTo(0, duration: Lb.slow, curve: Lb.ease);
  }

  // ---- Tweak ---------------------------------------------------------------

  void _openTweak() {
    if (tune.playback.generator == null || _tweakOpen) return;
    HapticFeedback.selectionClick();
    if (_scroll.hasClients && _scroll.offset > 0) _scroll.jumpTo(0);
    setState(() => _tweakOpen = true);
    HomeShell.dockHidden.value = true;
    _tweak.forward();
  }

  Future<void> _closeTweak() async {
    if (!_tweakOpen) return;
    HomeShell.dockHidden.value = false;
    await _tweak.reverse();
    if (mounted) setState(() => _tweakOpen = false);
  }

  // ---- Keep (AHA #5) ---------------------------------------------------------

  void _toast(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action, duration: const Duration(seconds: 4)));
  }

  Future<void> _keepIt() async {
    final s = AppScope.of(context);
    final d = s.devices;
    if (!d.isConnected) {
      return _toast('Connect a matrix to keep this on it.',
          action: SnackBarAction(label: 'Connect', onPressed: () => HomeShell.go(context, 2)));
    }
    if (!(d.caps?.canPlayGifs ?? false)) {
      return _toast('This matrix can only show looks live from your phone — it can’t keep them.');
    }
    if (s.playback.generator == null || _keep == KeepState.beaming) return;
    HapticFeedback.lightImpact();
    await _toTop();
    if (!mounted) return;
    setState(() {
      _keep = KeepState.beaming;
      _beamPath = _measureBeam();
    });
    _beam.repeat();
    _charge.value = 0;
    _charge.animateTo(0.88, duration: const Duration(seconds: 5), curve: Curves.easeOutCubic);

    final msg = await GlyphActions.saveToDevice(context);
    if (!mounted) return;
    final ok = msg != null && msg.startsWith('Kept');
    _beam.stop();
    // saveToDevice reports in its own words; ours replace it before it paints.
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      _keep = ok ? KeepState.kept : KeepState.failed;
      _beamPath = null;
    });
    if (ok) {
      _charge.value = 1;
      HapticFeedback.lightImpact();
      _toast('Kept on your matrix. Unplug your phone — it keeps playing.');
    } else {
      _charge.value = 0;
      _toast(_friendly(msg), action: SnackBarAction(label: 'Try again', onPressed: _keepIt));
    }
    await _flash.forward(from: 0);
    if (!mounted) return;
    _charge.value = 0;
    setState(() => _keep = KeepState.idle);
  }

  static String _friendly(String? msg) {
    if (msg == null) return 'Couldn’t keep this one. Try again?';
    if (msg.contains('space')) return 'Your matrix is full. Make room in Matrix → Kept.';
    if (msg.contains('GIF')) return 'This matrix can only show looks live from your phone.';
    final why = msg.replaceFirst(RegExp(r"^Couldn['’]t keep it: "), '');
    return 'Couldn’t keep this one — your matrix still shows it live. $why';
  }

  Offset _local(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  (Rect, Offset)? _measureBeam() {
    final stage = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    final glyph = _glyphKey.currentContext?.findRenderObject() as RenderBox?;
    if (stage == null || glyph == null || !stage.hasSize || !glyph.hasSize) return null;
    final s = _local(stage.localToGlobal(Offset.zero)) & Size(stage.size.width, stage.size.height * 0.85);
    final g = _local(glyph.localToGlobal(glyph.size.center(Offset.zero)));
    return (s, g);
  }

  // ---- Tile → Stage flight ---------------------------------------------------

  void _flyFrom(Rect from, TuneEntry entry) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final key = _mini.value ? _miniPanelKey : _stageKey;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final o = box.localToGlobal(Offset.zero);
    final w = box.size.width;
    final f = tune.playback.frame;
    final to = Rect.fromLTWH(o.dx, o.dy, w, min(box.size.height, w * f.height / f.width));
    final overlay = Overlay.of(context);
    late final OverlayEntry e;
    e = OverlayEntry(builder: (_) => _Flight(from: from, to: to, entry: entry, onDone: () => e.remove()));
    overlay.insert(e);
  }

  // ---- Pull down to search ---------------------------------------------------

  bool _onNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is OverscrollNotification && n.overscroll < 0 && n.dragDetails != null) {
      _pull -= n.overscroll;
      if (_pull > 90) {
        _pull = -1e9; // once per gesture
        _search();
      }
    } else if (n is ScrollEndNotification) {
      _pull = 0;
    }
    return false;
  }

  Future<void> _search() async {
    HapticFeedback.selectionClick();
    final tuned = await openSearch(context, tune);
    if (tuned == true && mounted) _toTop();
  }

  @override
  void dispose() {
    _scope?.playback.removeListener(_onPlayback);
    _scope?.creations.removeListener(_rebuildChannels);
    _scope?.devices.removeListener(_mirrorMatrix);
    _library.removeListener(_rebuildChannels);
    _scroll.dispose();
    _mini.dispose();
    _tweak.dispose();
    _beam.dispose();
    _charge.dispose();
    _flash.dispose();
    _tune?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top;
    return TuneScope(
      controller: tune,
      child: PopScope(
        canPop: !_tweakOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _closeTweak();
        },
        child: Stack(
          key: _stackKey,
          children: [
            // The page.
            Positioned.fill(
              child: FadeTransition(
                opacity: ReverseAnimation(_tweak),
                child: IgnorePointer(
                  ignoring: _tweakOpen,
                  child: TickerMode(
                    enabled: !_tweakOpen,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onNotification,
                      child: CustomScrollView(
                        controller: _scroll,
                        slivers: [
                          SliverToBoxAdapter(child: SizedBox(height: top)),
                          SliverToBoxAdapter(child: _Header(glyphKey: _glyphKey, onSearch: _search, keep: this)),
                          SliverToBoxAdapter(
                            child: StageDeck(
                              stageKey: _stageKey,
                              onTweak: _openTweak,
                              onKeep: _keepIt,
                              keepState: _keep,
                              showHint: _hint,
                              onSwiped: () {
                                if (_hint) setState(() => _hint = false);
                              },
                            ),
                          ),
                          SliverList.builder(
                            itemCount: _channels.length,
                            itemBuilder: (context, i) {
                              final c = _channels[i];
                              return ChannelRail(
                                key: ValueKey(c.id),
                                channel: c,
                                onSeeAll: c.all.length > 1 ? () => openChannelPage(context, c) : null,
                              );
                            },
                          ),
                          SliverToBoxAdapter(child: SizedBox(height: media.padding.bottom + 32)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // AHA #5: the beam from Stage to the header's matrix glyph.
            if (_keep == KeepState.beaming && _beamPath != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Builder(
                    builder: (context) => CustomPaint(
                      painter: BeamPainter(
                        progress: _beam,
                        from: _beamPath!.$1,
                        to: _beamPath!.$2,
                        color: AmbientScope.of(context).accent,
                      ),
                    ),
                  ),
                ),
              ),

            // Mini-stage, pinned when the Stage scrolls away.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: _mini,
                builder: (context, show, child) => IgnorePointer(
                  ignoring: !show || _tweakOpen,
                  child: AnimatedSlide(
                    offset: show && !_tweakOpen ? Offset.zero : const Offset(0, -1.05),
                    duration: Lb.medium,
                    curve: Lb.ease,
                    child: child,
                  ),
                ),
                child: ColoredBox(
                  color: Lb.panel.withValues(alpha: 0.96),
                  child: Padding(
                    padding: EdgeInsets.only(top: top),
                    child: MiniStage(panelKey: _miniPanelKey, onTap: _toTop),
                  ),
                ),
              ),
            ),

            // Tweak: the Stage stays up top, the control surface slides up.
            if (_tweakOpen) Positioned.fill(child: _TweakLayer(animation: _tweak, onClose: _closeTweak)),
          ],
        ),
      ),
    );
  }
}

class _TweakLayer extends StatelessWidget {
  const _TweakLayer({required this.animation, required this.onClose});

  final Animation<double> animation;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final h = media.size.height;
    final top = media.padding.top;
    final panelH = min(h * 0.56, h - top - 190).clamp(240.0, 560.0);
    final stageH = h - panelH - top - 16;
    final playback = AppScope.of(context).playback;
    final tune = TuneScope.of(context);
    final curved = CurvedAnimation(parent: animation, curve: Lb.ease, reverseCurve: Curves.easeInCubic);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onClose),
        ),
        Positioned(
          top: top + 8,
          left: 0,
          right: 0,
          height: stageH,
          child: FadeTransition(
            opacity: curved,
            child: ListenableBuilder(
              listenable: playback,
              builder: (context, _) {
                final f = playback.frame;
                final w = min(stageWidthFor(media.size, f.width / f.height), (stageH - 44) * f.width / f.height);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stage(
                      frame: f,
                      repaint: playback.frameTick,
                      maxWidth: max(80, w),
                      onTap: onClose,
                      onSwipe: (dir) => tune.surf(context, dir),
                    ),
                    const SizedBox(height: 10),
                    Text(captionTitle(tune),
                        style: LbType.heading, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: panelH,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
            child: TweakPanel(onClose: onClose),
          ),
        ),
      ],
    );
  }
}

/// Header: the word, the matrix status (with the little matrix glyph the
/// Keep beam lands in) and the search glyph.
class _Header extends StatelessWidget {
  const _Header({required this.glyphKey, required this.onSearch, required this.keep});

  final GlobalKey glyphKey;
  final VoidCallback onSearch;
  final _TuneScreenState keep;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final devices = scope.devices, playback = scope.playback;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Lb.gutter, 14, 12, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tune', style: LbType.display),
                const SizedBox(height: 10),
                ListenableBuilder(
                  listenable: Listenable.merge([devices, playback]),
                  builder: (context, _) {
                    final (text, VoidCallback? onTap) = _status(context);
                    return Semantics(
                      button: onTap != null,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            AnimatedBuilder(
                              animation: Listenable.merge([keep._charge, keep._flash]),
                              builder: (context, _) {
                                final f = keep._flash.value;
                                // Up fast, hold, fade.
                                final flash = f == 0 ? 0.0 : (f < 0.12 ? f / 0.12 : (f > 0.7 ? (1 - f) / 0.3 : 1.0));
                                return MatrixGlyph(
                                  key: glyphKey,
                                  frame: playback.frame,
                                  repaint: playback.frameTick,
                                  live: playback.isStreaming,
                                  accent: AmbientScope.of(context).accent,
                                  charge: keep._charge.value,
                                  flash: flash,
                                  error: keep._keep == KeepState.failed,
                                );
                              },
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(text.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: LbType.label.copyWith(color: devices.isConnected ? Lb.text2 : Lb.text3)),
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Tooltip(
              message: 'Search',
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(side: Lb.hairline),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onSearch,
                  child: const SizedBox.square(
                    dimension: 44,
                    child: Icon(Icons.search_rounded, size: 22, color: Lb.text),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  (String, VoidCallback?) _status(BuildContext context) {
    final scope = AppScope.of(context);
    final d = scope.devices, p = scope.playback;
    void connect() => HomeShell.go(context, 2);
    if (d.isConnected) {
      final name = d.info!.name;
      if (p.isStreaming) return ('$name · live', connect);
      final title = p.item?.title ?? p.generator?.name;
      if (title != null && d.isPlayingKept(title)) return ('$name · kept · playing on its own', connect);
      return ('$name · tap to show this', () => GlyphActions.ensureStreaming(context));
    }
    if (d.selected != null) {
      return d.isLoading ? ('Looking for ${d.selected!.name}…', null) : ('${d.selected!.name} · offline · tap to fix', connect);
    }
    return ('No matrix · tap to connect', connect);
  }
}

/// A tile's panel flying up into the Stage (or the mini-stage).
class _Flight extends StatefulWidget {
  const _Flight({required this.from, required this.to, required this.entry, required this.onDone});

  final Rect from, to;
  final TuneEntry entry;
  final VoidCallback onDone;

  @override
  State<_Flight> createState() => _FlightState();
}

class _FlightState extends State<_Flight> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 340))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final preview = switch (e) {
      ItemEntry(:final item) => LivePreview(item: item),
      CreationEntry() => LivePreview.generator(generator: e.generator, previewKey: e.key),
    };
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = Curves.easeInOutCubic.transform(_c.value);
          final r = Rect.lerp(widget.from, widget.to, t)!;
          return Stack(children: [
            Positioned.fromRect(
              rect: r,
              child: Opacity(opacity: (1 - Curves.easeInExpo.transform(_c.value)).clamp(0.0, 1.0), child: child),
            ),
          ]);
        },
        child: preview,
      ),
    );
  }
}
