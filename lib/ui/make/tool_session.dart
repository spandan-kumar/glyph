import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/background.dart';
import '../../app/playback.dart';
import '../../engine/clip.dart';
import '../../engine/generator.dart';
import '../actions.dart';
import '../scope.dart';

/// Sends a clip to the device; returns the message shown to the person.
typedef ToolClipSender = Future<String?> Function(BuildContext context, FrameClip clip, String title);

/// A Make tool's visit (Draw, Write, Clock, Timer, Bring a GIF, Music, a
/// game). What a tool plays only lasts as long as the visit: when the screen
/// goes away, anything it started that wasn't sent to the device stops — the
/// stream ends (the matrix goes back to its own saved look), the phone stops
/// playing it, and with it the mic and background service — so the Display
/// stage no longer shows the tool's content.
///
/// Something sent during the visit is left alone: the matrix plays the saved
/// GIF on its own. So is anything the tool set running in the background
/// ([keepAfterLeaving]): the person asked for it to outlive the screen. Whatever was playing before the tool opened is left alone
/// too, unless the tool replaced it.
///
/// Tools tell the session what they play ([toolPlays], [toolOwns],
/// [playClipInTool]) and what they send ([sendClipFromTool], [noteSent]).
mixin ToolSession<T extends StatefulWidget> on State<T> {
  /// How [sendClipFromTool] sends; tests swap in a fake.
  @visibleForTesting
  static ToolClipSender clipSender = GlyphActions.saveClipToDevice;

  final Set<Generator> _toolOwned = Set.identity();
  bool _toolSent = false;
  AppScope? _toolScope;
  BuildContext? _toolRoot;

  /// Whether what this tool plays should keep going after the screen closes
  /// (e.g. "Keep running in background" is on and running). Read on leaving.
  bool get keepAfterLeaving => false;

  /// Only Now Playing allows brief alerts while its screen is open.
  bool get allowsNotificationAlerts => false;

  /// Whether something was sent to the device since this tool last started
  /// playing.
  bool get sentFromTool => _toolSent;

  PlaybackController get _playback => (_toolScope ?? AppScope.of(context)).playback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _toolScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (!allowsNotificationAlerts) _toolScope?.playback.blockAlerts(this);
    // Outlives this screen, so the cleanup can still reach the app's actions.
    _toolRoot = Navigator.maybeOf(context, rootNavigator: true)?.context;
  }

  /// [g] is this tool's and has just started playing (a fresh play: anything
  /// sent before no longer describes what's on).
  void toolPlays(Generator g) {
    _toolOwned.add(g);
    _toolSent = false;
  }

  /// [g] is this tool's (e.g. a re-render of what it already plays) without
  /// counting as a fresh play.
  void toolOwns(Generator g) => _toolOwned.add(g);

  /// Plays [clip] like [GlyphActions.playClip], as this tool's.
  Future<void> playClipInTool(FrameClip clip, String title) {
    final started = GlyphActions.playClip(context, clip, title);
    // playClip swaps the generator before its first await.
    final g = _playback.generator;
    if (g != null) toolPlays(g);
    return started;
  }

  /// Sends [clip] to the device and remembers whether it got there.
  Future<String?> sendClipFromTool(FrameClip clip, String title) async =>
      noteSent(await clipSender(context, clip, title));

  /// Records a send's outcome: success messages start with "Sent".
  String? noteSent(String? message) {
    if (message != null && message.startsWith('Sent')) _toolSent = true;
    return message;
  }

  @override
  void dispose() {
    _toolScope?.playback.unblockAlerts(this);
    _endToolSession();
    super.dispose();
  }

  void _endToolSession() {
    final scope = _toolScope;
    if (scope == null || keepAfterLeaving) return;
    final pb = scope.playback, g = pb.generator;
    if (_toolSent || g == null || !_toolOwned.contains(g)) return;
    final root = _toolRoot, devices = scope.devices;
    // Deferred: notifying listeners while the tree is torn down throws.
    scheduleMicrotask(() {
      // Gone with the whole app (or something else took over): nothing to do.
      if (root == null || !root.mounted || !identical(pb.generator, g)) return;
      if (devices.isConnected) {
        unawaited(GlyphActions.stopStreaming(root));
      } else {
        unawaited(pb.stopStreaming());
        unawaited(BackgroundStreaming.stop());
      }
      pb.stop();
    });
  }
}
