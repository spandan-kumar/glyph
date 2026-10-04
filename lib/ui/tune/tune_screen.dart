import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/devices.dart';
import '../../library/user_library.dart';
import '../actions.dart';
import '../design/ambient.dart';
import '../design/parts.dart';
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
import 'stage_morph.dart';
import 'tiles.dart';
import 'tune_controller.dart';
import 'tweak_panel.dart';

/// Home ("Display"): the Stage (a live mirror of the device) with the
/// transport under it, then Channels as rails. Swipe the Stage to surf, tap
/// to Tweak, Send to beam the look onto the device. Scrolling morphs the
/// Stage into the mini-stage thumbnail (see [StageMorph]).
/// See docs/design/UX.md (J2–J4).
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
  final _stageKey = GlobalKey(); // the Stage's home slot in the page
  final _floatKey = GlobalKey(); // the one live Stage, floating above it
  final _glyphKey = GlobalKey();
  final _morph = StageMorph();
  double _topInset = 0;
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
    // A Make tool stopped its content: show what the device plays again
    // (or the automatic pick) instead of a blank stage.
    if (_scope?.playback.generator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scope?.playback.generator == null) _autoTune();
      });
      return;
    }
    final id = _scope?.playback.item?.id;
    if (id == null || id == _lastMarked || tune.shuffling) return;
    _lastMarked = id;
    if (id == _autoId) return;
    _library.markPlayed(id);
  }

  void _onScroll() {
    // Scroll offsets can change while the viewport lays out; measure after.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _syncMorph());
    } else {
      _syncMorph();
    }
  }

  /// Measures the Stage's home (where it sits with the page at the top) and
  /// the mini thumbnail slot, and moves the morph to the scroll offset.
  void _syncMorph() {
    if (!mounted) return;
    final slot = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (slot == null || stack == null || !slot.attached || !slot.hasSize || !stack.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(slot);
    if (viewport == null) return;
    // Content position: valid even while the slot is scrolled off-screen.
    final top = viewport.getOffsetToReveal(slot, 0).offset;
    final left = stack.globalToLocal(slot.localToGlobal(Offset.zero)).dx;
    final f = tune.playback.frame;
    _morph.update(
      home: Rect.fromLTWH(left, top, slot.size.width, slot.size.height),
      mini: MiniStage.panelRect(top: _topInset, aspect: f.width / f.height),
      barBottom: _topInset + MiniStage.height,
      offset: _scroll.hasClients ? _scroll.offset : 0,
    );
  }

  void _tapStage() => _morph.t > 0.5 ? _toTop() : _openTweak();

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

  // ---- Send (AHA #5) ---------------------------------------------------------

  void _toast(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action, duration: const Duration(seconds: 4)));
  }

  Future<void> _keepIt() async {
    final s = AppScope.of(context);
    final d = s.devices;
    if (!d.isConnected) {
      return _toast('Connect a device to send this to it.',
          action: SnackBarAction(label: 'Connect', onPressed: () => HomeShell.go(context, 2)));
    }
    if (!(d.caps?.canPlayGifs ?? false)) {
      return _toast('This device can only show looks live from your phone — it can’t save them.');
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
    final ok = msg != null && (msg.startsWith('Sent') || msg.startsWith('Kept'));
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
      _toast(sendSuccessMessage);
    } else {
      _charge.value = 0;
      _toast(friendlySendError(msg),
          action: msg == liveOnlyMessage ? null : SnackBarAction(label: 'Try again', onPressed: _keepIt));
    }
    await _flash.forward(from: 0);
    if (!mounted) return;
    _charge.value = 0;
    setState(() => _keep = KeepState.idle);
  }

  Offset _local(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  (Rect, Offset)? _measureBeam() {
    final stage = _floatKey.currentContext?.findRenderObject() as RenderBox?;
    final glyph = _glyphKey.currentContext?.findRenderObject() as RenderBox?;
    if (stage == null || glyph == null || !stage.hasSize || !glyph.hasSize) return null;
    final s = _local(stage.localToGlobal(Offset.zero)) & stage.size;
    final g = _local(glyph.localToGlobal(glyph.size.center(Offset.zero)));
    return (s, g);
  }

  // ---- Tile → Stage flight ---------------------------------------------------

  void _flyFrom(Rect from, TuneEntry entry) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    // Wherever the Stage is right now: full size or the mini thumbnail.
    final box = _floatKey.currentContext?.findRenderObject() as RenderBox?;
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
    if (n is ScrollStartNotification && n.dragDetails != null) _dragged = true;
    if (n is ScrollUpdateNotification && (n.scrollDelta ?? 0) != 0) _collapsing = n.scrollDelta! > 0;
    if (n is OverscrollNotification && n.overscroll < 0 && n.dragDetails != null) {
      _pull -= n.overscroll;
      if (_pull > 90) {
        _pull = -1e9; // once per gesture
        _search();
      }
    } else if (n is ScrollEndNotification) {
      _pull = 0;
      if (_dragged) _snapMorph();
      _dragged = false;
    }
    return false;
  }

  bool _dragged = false;
  bool _collapsing = false;

  /// Coming to rest mid-collapse would leave a half-shrunk Stage beside its
  /// empty slot, so finish the way it was going (a small nudge falls back).
  void _snapMorph() {
    if (!_morph.between || !_scroll.hasClients) return;
    final collapse = _collapsing ? _morph.t > 0.2 : _morph.t > 0.8;
    final target = collapse ? _morph.travel : 0.0;
    // After this notification: starting a scroll from inside it is unsafe.
    Future.microtask(() {
      if (!mounted || !_scroll.hasClients || !_morph.between) return;
      _scroll.animateTo(target, duration: Lb.medium, curve: Lb.ease);
    });
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
    _morph.dispose();
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
    _topInset = top;
    // Header or insets may have moved the Stage's home.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMorph());
    final hidden = ReverseAnimation(_tweak);

    // The one live Stage. Built here, placed by the morph below, so
    // scrolling only moves it (no rebuilds of it or of the page).
    final stage = FadeTransition(
      opacity: hidden,
      child: IgnorePointer(
        ignoring: _tweakOpen,
        child: RepaintBoundary(
          child: MorphingStage(
            key: _floatKey,
            morph: _morph,
            scroll: _scroll,
            onTap: _tapStage,
            onSwiped: () {
              if (_hint) setState(() => _hint = false);
            },
          ),
        ),
      ),
    );

    // The pinned bar the Stage collapses into; its slot is left empty for it.
    final bar = RepaintBoundary(
      child: ColoredBox(
        color: Lb.panel.withValues(alpha: 0.96),
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: MiniStage(onTap: _toTop, livePanel: false),
        ),
      ),
    );

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
                opacity: hidden,
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
                              onLayout: _syncMorph,
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

            // The mini-stage bar fades in as the Stage arrives in its slot.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: hidden,
                child: ListenableBuilder(
                  listenable: _morph,
                  child: bar,
                  builder: (context, child) {
                    final o = _morph.fade(0.55, 1);
                    return IgnorePointer(
                      ignoring: !_morph.collapsed || _tweakOpen,
                      child: o <= 0 ? const SizedBox.shrink() : Opacity(opacity: o, child: child),
                    );
                  },
                ),
              ),
            ),

            // The Stage itself, morphing between its home and the thumbnail.
            ListenableBuilder(
              listenable: _morph,
              child: stage,
              builder: (context, child) {
                final ready = _morph.ready;
                return Positioned.fromRect(
                  rect: ready ? _morph.rect : const Rect.fromLTWH(0, 0, 1, 1),
                  child: Offstage(offstage: !ready, child: child),
                );
              },
            ),

            // AHA #5: the beam from Stage to the header's device glyph.
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

            // Tweak: the Stage stays up top, the control surface slides up.
            if (_tweakOpen) Positioned.fill(child: _TweakLayer(animation: _tweak, onClose: _closeTweak)),
          ],
        ),
      ),
    );
  }
}

/// What Display says once a look is saved on the device.
const sendSuccessMessage = 'Sent to your device. It keeps playing without your phone.';

/// Our words for what went wrong sending a look (from saveToDevice's).
String friendlySendError(String? msg) {
  if (msg == null) return 'Couldn’t send this one. Try again?';
  if (msg == liveOnlyMessage) return msg;
  if (msg.contains('space')) return 'Your device is full. Make room in Device → Storage.';
  if (msg.contains('GIF')) return 'This device can only show looks live from your phone.';
  final why = msg.replaceFirst(RegExp(r"^Couldn['’]t (keep|send)( it| this)?: "), '');
  return 'Couldn’t send this one — your device still shows it live. $why';
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

/// Header: the word, the device status (with the little device glyph the
/// Send beam lands in), the power key and the search key.
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
                Text('Display', style: LbType.display),
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
          const Padding(padding: EdgeInsets.only(top: 2), child: PowerKey()),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SquareKey(icon: Icons.search_sharp, label: 'Search', onTap: onSearch),
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
      if (d.isOn == false) return ('Device · off', () => PowerKey.set(context, true));
      if (p.isStreaming) return ('Device · live', connect);
      final title = p.item?.title ?? p.generator?.name;
      if (title != null && d.isPlayingKept(title)) return ('Device · playing on its own', connect);
      return ('Device · tap to show this', () => GlyphActions.ensureStreaming(context));
    }
    if (d.selected != null) {
      return d.isLoading ? ('Looking for ${d.selected!.name}…', null) : ('Device · offline · tap to fix', connect);
    }
    return ('No device · tap to connect', connect);
  }
}

/// The device's power switch as a square hardware key: lit (green LED, room
/// colour frame) while the device is on, dark when it's off, dimmed with
/// "Connect a device" when there's nothing to switch.
class PowerKey extends StatelessWidget {
  const PowerKey({super.key});

  static const keyId = ValueKey('display-power');

  /// Switches the device; says so if it can't be reached.
  static Future<void> set(BuildContext context, bool on) async {
    final d = AppScope.of(context).devices;
    if (!d.isConnected) return;
    HapticFeedback.mediumImpact();
    try {
      await d.setPower(on);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Couldn’t reach your device. Try again?')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = AppScope.of(context).devices;
    final accent = AmbientScope.of(context).accent;
    return ListenableBuilder(
      listenable: devices,
      builder: (context, _) {
        final connected = devices.isConnected;
        final on = connected && devices.isOn != false;
        return Tooltip(
          message: !connected ? 'Connect a device' : (on ? 'Turn off' : 'Turn on'),
          child: Semantics(
            button: true,
            enabled: connected,
            toggled: on,
            label: 'Power',
            child: AnimatedOpacity(
              opacity: connected ? 1 : 0.4,
              duration: Lb.fast,
              child: Material(
                key: keyId,
                color: on ? Lb.raised : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(Lb.rControl)),
                  side: BorderSide(color: on ? accent.withValues(alpha: 0.65) : Lb.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: connected ? () => set(context, !on) : null,
                  child: SizedBox.square(
                    dimension: 44,
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(Icons.power_settings_new_sharp,
                              size: 20, color: on ? Lb.text : Lb.text3),
                        ),
                        Positioned(top: 6, right: 6, child: StatusDot(on: on, size: 5)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
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
