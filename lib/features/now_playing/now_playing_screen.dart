import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/background.dart';
import '../../app/playback.dart';
import '../../ui/actions.dart';
import '../../ui/design/parts.dart';
import '../../ui/design/toggle.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/demos.dart';
import '../../ui/make/led_loop.dart';
import '../../ui/make/studio_kit.dart';
import '../../ui/make/tool_session.dart';
import '../../ui/scope.dart';
import '../../ui/widgets/led_matrix_view.dart';
import 'now_playing.dart';
import 'now_playing_generator.dart';
import 'now_playing_service.dart';

// Remembered for the session so revisiting the screen keeps the choices.
final _style = NowPlayingStyle();
// On by default: the whole point is to be in the music app meanwhile.
bool _wantBackground = true;

/// Now Playing: the cover of whatever the phone is playing, with a progress
/// bar, live on the device.
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key, this.service});

  /// Defaults to [NowPlayingService.shared]; tests pass their own.
  final NowPlayingService? service;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with WidgetsBindingObserver, ToolSession<NowPlayingScreen> {
  late final NowPlayingService _service = widget.service ?? NowPlayingService.shared;
  late NowPlayingGenerator _generator = NowPlayingGenerator(_service, style: _style);
  late final _demo = nowPlayingDemo();
  bool _inited = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.acquire(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    // Coming back while it's on the device: keep driving the same one.
    final g = AppScope.of(context).playback.generator;
    if (g is NowPlayingGenerator && identical(g.feed, _service)) _generator = g;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.release(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the settings page: access may have just been granted.
    if (state == AppLifecycleState.resumed && _service.access != NowPlayingAccess.granted) {
      _service.refresh();
    }
  }

  bool _isOurs(PlaybackController p) => identical(p.generator, _generator);

  // Background on: the cover keeps following songs after the screen closes,
  // until it's stopped from the notification or something else plays.
  @override
  bool get keepAfterLeaving => _wantBackground && BackgroundStreaming.isRunning;

  @override
  bool get allowsNotificationAlerts => true;

  Future<void> _play() async {
    final s = AppScope.of(context);
    HapticFeedback.mediumImpact(); // starts changing the device's display
    s.playback.playGenerator(_generator);
    toolPlays(_generator);
    _CoverFollower.bind(_service, s.playback);
    await GlyphActions.ensureStreaming(context);
    if (_wantBackground && s.playback.isStreaming && mounted) await _startBackground();
  }

  Future<void> _stop() async {
    HapticFeedback.selectionClick();
    AppScope.of(context).playback.pause();
    await GlyphActions.stopStreaming(context);
  }

  Future<void> _startBackground() async {
    final s = AppScope.of(context);
    final playback = s.playback, devices = s.devices;
    final ok = await BackgroundStreaming.start(
      title: 'Showing what\'s playing on ${devices.info?.name ?? 'your device'}',
      text: _songLine(_service.current) ?? 'Waiting for music',
      onStop: () {
        playback.pause();
        playback.stopStreaming();
        devices.client?.exitLive().catchError((_) {});
      },
    );
    BackgroundStreaming.watch(playback);
    if (!ok && mounted) studioToast(context, 'Couldn\'t keep running in the background.');
  }

  Future<void> _toggleBackground(bool on) async {
    setState(() => _wantBackground = on);
    final playback = AppScope.of(context).playback;
    if (!on) {
      await BackgroundStreaming.stop();
    } else if (_isOurs(playback) && playback.isPlaying && playback.isStreaming) {
      await _startBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback, devices = scope.devices;
    return StudioScaffold(
      title: 'Now Playing',
      body: ListenableBuilder(
        listenable: Listenable.merge([_service, playback, devices, BackgroundStreaming.running]),
        builder: (context, _) {
          final playing = _isOurs(playback) && playback.isPlaying;
          final access = _service.access;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 32),
            children: [
              if (access == NowPlayingAccess.unsupported)
                const _Notice(
                  title: 'Android only for now',
                  body: 'iPhones don\'t let apps see what other apps are playing yet.',
                )
              else if (access == NowPlayingAccess.denied)
                _AccessCard(onAllow: _service.openSettings),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: playing
                      ? LedMatrixView(
                          frame: playback.frame,
                          repaint: playback.frameTick,
                          glow: true,
                          bezel: true,
                          borderRadius: Lb.rControl,
                        )
                      : LedLoop(
                          // Before access is granted, show what it would look like.
                          key: ValueKey(access == NowPlayingAccess.granted),
                          generator: access == NowPlayingAccess.granted ? _generator : _demo,
                          width: playback.frame.width,
                          height: playback.frame.height,
                          glow: true,
                          bezel: true,
                          borderRadius: Lb.rControl,
                        ),
                ),
              ),
              const SizedBox(height: 16),
              _TrackInfo(np: _service.current, waiting: access == NowPlayingAccess.granted),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: playing && playback.isStreaming ? null : _play,
                    icon: const Icon(Icons.play_arrow_sharp),
                    label: Text(
                      playing
                          ? (playback.isStreaming ? 'Showing on device' : 'Showing here')
                          : devices.isConnected
                              ? 'Show on device'
                              : 'Show here',
                    ),
                  ),
                ),
                if (playing) ...[
                  const SizedBox(width: 10),
                  IconButton.outlined(
                    tooltip: 'Stop',
                    style: IconButton.styleFrom(
                        side: Lb.hairline, minimumSize: const Size(48, 48), shape: studioShape),
                    onPressed: _stop,
                    icon: const Icon(Icons.stop_sharp),
                  ),
                ],
              ]),
              if (!devices.isConnected)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No device connected · showing it here on your phone',
                    textAlign: TextAlign.center,
                    style: LbType.small.copyWith(color: Lb.text3),
                  ),
                ),
              const SizedBox(height: 22),
              StudioGroup(
                label: 'Look',
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Column(children: [
                  LbToggleTile(
                    title: 'Progress bar',
                    subtitle: 'Along the bottom, in the cover\'s colour',
                    value: _style.bar,
                    onChanged: (v) => setState(() => _style.bar = v),
                  ),
                  LbToggleTile(
                    title: 'Song name',
                    subtitle: 'Scrolls across when a new song starts',
                    value: _style.title,
                    onChanged: (v) => setState(() => _style.title = v),
                  ),
                ]),
              ),
              StudioGroup(
                label: 'Colour',
                child: StudioKnobRow(knobs: [
                  StudioKnob(
                    label: 'Vivid',
                    value: _style.vivid,
                    valueText: '${(_style.vivid * 100).round()}%',
                    onChanged: (v) => setState(() => _style.vivid = v),
                  ),
                ]),
              ),
              if (BackgroundStreaming.supported)
                StudioGroup(
                  label: 'While playing',
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                  child: LbToggleTile(
                    title: 'Keep running in background',
                    subtitle: _wantBackground && BackgroundStreaming.isRunning
                        ? 'Running · stop it from the notification'
                        : devices.isConnected
                            ? 'Keeps following your songs while you\'re in your music app'
                            : 'Connect a device to use this',
                    value: _wantBackground,
                    onChanged: devices.isConnected ? _toggleBackground : null,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Covers are shown live and never saved, on your phone or your device.',
                  textAlign: TextAlign.center,
                  style: LbType.small.copyWith(color: Lb.text3),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String? _songLine(NowPlaying? np) =>
    np == null ? null : (np.artist.isEmpty ? np.title : '${np.title} · ${np.artist}');

/// Keeps the media sessions followed for as long as playback runs a Now
/// Playing cover (so it keeps changing after this screen closes), keeps the
/// background notification naming the song, and lets go once something
/// else plays.
class _CoverFollower {
  _CoverFollower(this.service, this.playback) {
    playback.addListener(_onPlayback);
    service.addListener(_onSong);
    _onPlayback();
  }

  static _CoverFollower? _current;

  final NowPlayingService service;
  final PlaybackController playback;
  String? _song;

  static void bind(NowPlayingService service, PlaybackController playback) {
    final c = _current;
    if (c != null && identical(c.service, service) && identical(c.playback, playback)) return;
    c?._detach();
    _current = _CoverFollower(service, playback);
  }

  bool get _ours {
    final g = playback.generator;
    return g is NowPlayingGenerator && identical(g.feed, service);
  }

  void _onPlayback() {
    if (_ours && playback.isPlaying) {
      service.acquire(this);
    } else {
      service.release(this);
    }
    if (!_ours) _detach();
  }

  void _onSong() {
    final line = _songLine(service.current);
    if (line == _song || !_ours) return;
    _song = line;
    unawaited(BackgroundStreaming.update(text: line ?? 'Waiting for music'));
  }

  void _detach() {
    playback.removeListener(_onPlayback);
    service.removeListener(_onSong);
    service.release(this);
    if (identical(_current, this)) _current = null;
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.onAllow});

  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: LbPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.album_sharp, color: readAccent(context)),
              const SizedBox(width: 10),
              Expanded(child: Text('Let Glyph see what\'s playing', style: LbType.heading)),
            ]),
            const SizedBox(height: 8),
            Text(
              'Glyph shows the cover of whatever your phone is playing — Spotify, '
              'YouTube Music, podcasts, any player. Android calls this '
              'Notification access: turn on Glyph Now Playing, then come back. '
              'Glyph only reads what\'s playing; nothing is saved or sent anywhere.',
              style: LbType.small,
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onAllow, child: const Text('Allow access')),
          ]),
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.body});

  final String title, body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: LbPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: LbType.heading),
            const SizedBox(height: 6),
            Text(body, style: LbType.small),
          ]),
        ),
      );
}

/// The song, its app, and where it's up to — ticking along once a second.
class _TrackInfo extends StatefulWidget {
  const _TrackInfo({required this.np, required this.waiting});

  final NowPlaying? np;

  /// Access is granted; nothing is playing yet.
  final bool waiting;

  @override
  State<_TrackInfo> createState() => _TrackInfoState();
}

class _TrackInfoState extends State<_TrackInfo> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.np?.playing ?? false) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final np = widget.np;
    if (np == null) {
      return Text(
        widget.waiting
            ? 'Nothing playing. Start a song in any music app.'
            : 'The cover of whatever\'s playing shows up here.',
        textAlign: TextAlign.center,
        style: LbType.small.copyWith(color: Lb.text2),
      );
    }
    final now = DateTime.now();
    final progress = np.progressAt(now);
    final sub = [np.artist, np.app].where((s) => s.isNotEmpty).join(' · ');
    return Column(children: [
      Text(np.title,
          maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: LbType.heading),
      if (sub.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: LbType.small.copyWith(color: Lb.text2)),
      ],
      if (progress != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          Text(formatTrackTime(np.positionAt(now)), style: LbType.mono.copyWith(fontSize: 11)),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Lb.rTile),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                color: readAccent(context),
                backgroundColor: Lb.line,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(formatTrackTime(np.durationMs), style: LbType.mono.copyWith(fontSize: 11)),
        ]),
      ],
      if (!np.playing) ...[
        const SizedBox(height: 6),
        Text('PAUSED', style: LbType.label.copyWith(color: Lb.text3)),
      ],
    ]);
  }
}

@visibleForTesting
void debugResetNowPlayingScreen() {
  _CoverFollower._current?._detach();
  _style
    ..bar = true
    ..title = true
    ..vivid = 0.5;
  _wantBackground = true;
}
