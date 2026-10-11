import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/community.dart';
import '../actions.dart';
import '../design/tokens.dart';
import '../scope.dart';
import 'stage_deck.dart';
import 'tune_screen.dart' show friendlySendError, sendSuccessMessage;

/// A square key in the bottom-right corner that runs a long page back to
/// the top. It slides in once [showAfter] pixels have scrolled by and out
/// again near the top.
class BackToTopKey extends StatelessWidget {
  const BackToTopKey({super.key, required this.scroll, this.showAfter = 0, this.onTop});

  final ScrollController scroll;

  /// How far the page must have scrolled before it shows.
  final double showAfter;

  /// Runs instead of the plain scroll (Display also expands the Stage).
  final VoidCallback? onTop;

  void _go() {
    HapticFeedback.selectionClick();
    if (onTop != null) return onTop!();
    if (!scroll.hasClients) return;
    scroll.animateTo(0, duration: Lb.slow * 1.5, curve: Lb.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scroll,
      builder: (context, child) {
        final shown = scroll.hasClients && scroll.offset > showAfter + 40;
        return IgnorePointer(
          ignoring: !shown,
          child: AnimatedSlide(
            offset: Offset(0, shown ? 0 : 0.6),
            duration: Lb.medium,
            curve: Lb.ease,
            child: AnimatedOpacity(opacity: shown ? 1 : 0, duration: Lb.fast, child: child),
          ),
        );
      },
      child: Tooltip(
        message: 'Back to the top',
        child: Semantics(
          button: true,
          label: 'Back to the top',
          excludeSemantics: true,
          child: Material(
            color: Lb.panel.withValues(alpha: 0.94),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(Lb.rControl)),
              side: Lb.hairline,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _go,
              child: const SizedBox.square(
                dimension: 42,
                child: Icon(Icons.vertical_align_top_sharp, size: 20, color: Lb.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Send for pages without the Stage (a channel's See all): the compact key's
/// state, with the same checks and the same words as Display.
mixin PageSend<T extends StatefulWidget> on State<T> {
  KeepState keep = KeepState.idle;
  int _request = 0;

  void _say(String msg, {SnackBarAction? action}) => ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), action: action, duration: const Duration(seconds: 4)));

  Future<void> send() async {
    final s = AppScope.of(context);
    if (s.playback.generator == null || keep == KeepState.checking || keep == KeepState.beaming) return;
    final request = ++_request;
    HapticFeedback.lightImpact();
    setState(() => keep = KeepState.checking);
    try {
      final result = await GlyphActions.sendToDevice(context, onUpload: () async {
        if (mounted && request == _request) setState(() => keep = KeepState.beaming);
      });
      if (!mounted || request != _request) return;
      switch (result) {
        case AlreadyOnDevice() || Cancelled():
          // Each already said its piece.
          setState(() => keep = KeepState.idle);
          return;
        case Sent():
          HapticFeedback.lightImpact();
          setState(() => keep = KeepState.kept);
          _say(sendSuccessMessage);
        case Failed(:final message, :final liveOnly):
          setState(() => keep = KeepState.failed);
          if (!liveOnly) LastError.record('Send from a channel page failed: $message');
          _say(friendlySendError(message),
              action: liveOnly ? null : SnackBarAction(label: 'Try again', onPressed: send));
      }
      // The key shows ✓ or ↻ for a moment, then is ready again.
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (mounted && request == _request) setState(() => keep = KeepState.idle);
    } catch (_) {
      if (mounted && request == _request) setState(() => keep = KeepState.idle);
      rethrow;
    }
  }
}
