import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/clip.dart';
import '../../engine/generators/intro.dart';
import '../../features/device/widgets/device_settings.dart';
import '../../features/text/fonts.dart';
import '../../wled/layout.dart';
import '../actions.dart';
import '../design/led_text.dart';
import '../design/stage.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import 'orientation.dart';
import 'setup_clips.dart';

/// Plays [clip] on the phone and, when connected, on the device. Doesn't
/// wait for the stream to open.
void playSetupClip(BuildContext context, FrameClip Function(int w, int h) build, String title) {
  final caps = AppScope.of(context).devices.caps;
  final clip = build(caps?.width ?? fallbackSize, caps?.height ?? fallbackSize);
  unawaited(GlyphActions.playClip(context, clip, title));
}

/// Plays the Glyph intro (the boot screen Glyph installs on every device)
/// on the phone and, when connected, on the device. It plays once and then
/// holds the logo.
void playIntro(BuildContext context) {
  AppScope.of(context).playback.playGenerator(GlyphIntro());
  unawaited(GlyphActions.ensureStreaming(context));
}

/// Saves [layout] for the selected device and restarts the live stream so
/// it takes effect straight away.
Future<void> applyLayout(BuildContext context, MatrixLayout layout) async {
  final s = AppScope.of(context);
  await s.devices.updateLayout(layout);
  final host = s.devices.selected?.host;
  if (host != null && s.playback.isStreaming) {
    try {
      await s.playback.startStreaming(host, layout);
    } catch (_) {
      // The next ensureStreaming picks the new layout up.
    }
  }
}

enum _FixPhase { arrow, mirror, sideways }

/// "Something looks off": two plain questions, then we set the layout.
class OrientationFix extends StatefulWidget {
  const OrientationFix({super.key, required this.onDone, this.onBack});

  /// Called once the layout is saved (or nothing could be changed).
  final VoidCallback onDone;
  final VoidCallback? onBack;

  @override
  State<OrientationFix> createState() => _OrientationFixState();
}

class _OrientationFixState extends State<OrientationFix> {
  _FixPhase _phase = _FixPhase.arrow;
  late MatrixLayout _start;
  ArrowSeen? _seen;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _start = AppScope.of(context).devices.selected?.layout ?? MatrixLayout.identity;
    // Playing notifies listeners, which mustn't happen mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) playSetupClip(context, arrowClip, 'Arrow');
    });
  }

  bool get _square {
    final caps = AppScope.of(context).devices.caps;
    return caps == null || caps.width == caps.height;
  }

  Future<void> _arrow(ArrowSeen seen) async {
    HapticFeedback.selectionClick();
    _seen = seen;
    final fixed = correctedLayout(_start, seen, mirrored: false, square: _square);
    if (fixed == null) {
      setState(() => _phase = _FixPhase.sideways);
      return;
    }
    await applyLayout(context, fixed);
    if (!mounted) return;
    playSetupClip(context, letterClip, 'Letter L');
    setState(() => _phase = _FixPhase.mirror);
  }

  Future<void> _mirror(bool mirrored) async {
    HapticFeedback.selectionClick();
    if (mirrored) {
      final fixed = correctedLayout(_start, _seen!, mirrored: true, square: _square);
      if (fixed != null) await applyLayout(context, fixed);
    }
    if (mounted) widget.onDone();
  }

  void _back() {
    if (_phase == _FixPhase.arrow) {
      widget.onBack?.call();
      return;
    }
    // Start over from the layout we had.
    applyLayout(context, _start);
    playSetupClip(context, arrowClip, 'Arrow');
    setState(() => _phase = _FixPhase.arrow);
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: Lb.medium,
    switchInCurve: Lb.ease,
    child: KeyedSubtree(
      key: ValueKey(_phase),
      child: switch (_phase) {
        _FixPhase.arrow => _ArrowQuestion(onAnswer: _arrow, onBack: widget.onBack == null ? null : _back),
        _FixPhase.mirror => _MirrorQuestion(onAnswer: _mirror, onBack: _back),
        _FixPhase.sideways => _Sideways(onDone: widget.onDone, onBack: _back),
      },
    ),
  );
}

class _Frame extends StatelessWidget {
  const _Frame({required this.title, this.subtitle, required this.child, this.onBack});

  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: onBack == null
            ? const SizedBox(height: 48)
            : IconButton(tooltip: 'Back', onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
      ),
      const SizedBox(height: 8),
      Text(title, style: LbType.title),
      if (subtitle != null) ...[const SizedBox(height: 8), Text(subtitle!, style: LbType.small)],
      const SizedBox(height: 28),
      child,
    ],
  );
}

class _ArrowQuestion extends StatelessWidget {
  const _ArrowQuestion({required this.onAnswer, this.onBack});

  final ValueChanged<ArrowSeen> onAnswer;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    Widget b(ArrowSeen s, IconData icon, String label) => _ArrowButton(
      icon: icon,
      label: label,
      onTap: () => onAnswer(s),
    );
    return _Frame(
      title: 'Which way is the arrow pointing on your device?',
      subtitle: 'Look at your device, not your phone.',
      onBack: onBack,
      child: Column(
        children: [
          b(ArrowSeen.up, Icons.arrow_upward_rounded, 'Up'),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              b(ArrowSeen.left, Icons.arrow_back_rounded, 'Left'),
              const SizedBox(width: 12),
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF050403),
                  borderRadius: BorderRadius.circular(Lb.rPanel),
                  border: Border.all(color: Lb.line),
                ),
                child: const LedText('?', dot: 6, color: Lb.text3),
              ),
              const SizedBox(width: 12),
              b(ArrowSeen.right, Icons.arrow_forward_rounded, 'Right'),
            ],
          ),
          const SizedBox(height: 12),
          b(ArrowSeen.down, Icons.arrow_downward_rounded, 'Down'),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: Lb.raised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Lb.rPanel)),
        side: Lb.hairline,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Lb.rPanel),
        child: SizedBox.square(dimension: 84, child: Icon(icon, size: 40, color: Lb.text)),
      ),
    ),
  );
}

class _MirrorQuestion extends StatelessWidget {
  const _MirrorQuestion({required this.onAnswer, required this.onBack});

  final ValueChanged<bool> onAnswer;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final playback = AppScope.of(context).playback;
    return _Frame(
      title: 'Does it look mirrored?',
      subtitle: 'Your device should show a capital L, the right way round, like this:',
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: playback,
            builder: (context, _) =>
                Stage(frame: playback.frame, repaint: playback.frameTick, maxWidth: 180),
          ),
          const SizedBox(height: 12),
          Center(child: LedText('L', dot: 4, font: boldFont, color: Lb.text2)),
          const SizedBox(height: 28),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () => onAnswer(false),
            child: const Text('No, it looks right'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => onAnswer(true),
            child: const Text('Yes, it\'s backwards'),
          ),
        ],
      ),
    );
  }
}

class _Sideways extends StatelessWidget {
  const _Sideways({required this.onDone, required this.onBack});

  final VoidCallback onDone;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).devices;
    return _Frame(
      title: 'This one needs a turn in its own settings',
      subtitle: 'Your device isn\'t square, so Glyph can\'t turn it sideways. Open Device settings '
          '→ LED Preferences → 2D and change how the panel is turned.',
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: onDone,
            child: const Text('Got it'),
          ),
          if (store.isConnected) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => DeviceSettingsPage.open(context, store),
              child: const Text('Open Device settings'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The guided fix as its own page (Device → Fix orientation).
class OrientationFixPage extends StatelessWidget {
  const OrientationFixPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const OrientationFixPage()),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: OrientationFix(
        onBack: () => Navigator.pop(context),
        onDone: () {
          playIntro(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved. The Glyph logo should be the right way up now.')),
          );
          Navigator.pop(context);
        },
      ),
    ),
  );
}
