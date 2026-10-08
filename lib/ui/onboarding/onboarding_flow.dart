import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../library/catalog.dart';
import '../../wled/discovery.dart';
import '../actions.dart';
import '../design/parts.dart';
import '../design/route.dart';
import '../design/stage.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';
import '../make/tool_session.dart';
import '../widgets/live_preview.dart';
import 'orientation_fix.dart';
import 'search_step.dart';
import 'welcome_step.dart';

export 'search_step.dart' show SetupServices;

/// First run (UX.md J1): welcome → find the device → it plays the Glyph intro →
/// (fix the orientation) → pick a first vibe. Shown once.
class OnboardingFlow extends StatelessWidget {
  const OnboardingFlow({
    super.key,
    required this.onDone,
    @visibleForTesting this.services = const SetupServices(),
  });

  final VoidCallback onDone;
  final SetupServices services;

  static const prefsKey = 'onboarding.done.v1';

  static Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool(prefsKey) ?? false;

  static Future<void> markDone() async =>
      (await SharedPreferences.getInstance()).setBool(prefsKey, true);

  @override
  Widget build(BuildContext context) => SetupFlow(
    services: services,
    onDone: () async {
      await markDone();
      onDone();
    },
  );
}

/// "Add a device": the same flow starting at the search, without the
/// welcome or the first-vibe pick.
class MatrixSetupPage extends StatelessWidget {
  const MatrixSetupPage({super.key, @visibleForTesting this.services = const SetupServices()});

  final SetupServices services;

  static Future<void> open(BuildContext context, {SetupServices services = const SetupServices()}) =>
      Navigator.of(context).push(
        lbRoute<void>((_) => MatrixSetupPage(services: services)),
      );

  @override
  Widget build(BuildContext context) => SetupFlow(
    services: services,
    start: SetupStep.search,
    withVibe: false,
    onDone: () => Navigator.of(context).maybePop(),
  );
}

enum SetupStep { welcome, search, hello, fix, vibe }

class SetupFlow extends StatefulWidget {
  const SetupFlow({
    super.key,
    required this.onDone,
    this.services = const SetupServices(),
    this.start = SetupStep.welcome,
    this.withVibe = true,
  });

  final VoidCallback onDone;
  final SetupServices services;
  final SetupStep start;
  final bool withVibe;

  @override
  State<SetupFlow> createState() => _SetupFlowState();
}

class _SetupFlowState extends State<SetupFlow> with ToolSession<SetupFlow> {
  late SetupStep _step = widget.start;
  int _dir = 1;

  /// Input is ignored while steps cross-fade, so a tap that ends one step
  /// can't land on a button of the next (e.g. "Looks right" → a vibe tile).
  bool _settling = false;
  bool _fixed = false;

  void _go(SetupStep s, {int dir = 1}) {
    setState(() {
      _dir = dir;
      _step = s;
      _settling = true;
    });
    Future<void>.delayed(Lb.medium + const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _settling = false);
    });
  }

  void _back() {
    switch (_step) {
      case SetupStep.welcome:
        return;
      case SetupStep.search:
        if (widget.start == SetupStep.search) {
          Navigator.of(context).maybePop();
        } else {
          _go(SetupStep.welcome, dir: -1);
        }
      case SetupStep.hello:
        _go(SetupStep.search, dir: -1);
      case SetupStep.fix:
        _hello(dir: -1);
      case SetupStep.vibe:
        _hello(dir: -1);
    }
  }

  void _hello({int dir = 1}) {
    playIntro(context);
    _go(SetupStep.hello, dir: dir);
  }

  Future<String?> _connect(DiscoveredDevice d) async {
    final devices = AppScope.of(context).devices;
    try {
      await devices.addAndSelect(d.host, d.name);
    } catch (_) {}
    if (!mounted) return null;
    if (!devices.isConnected) {
      return 'Couldn\'t reach ${d.name}. Is it switched on and on the same Wi-Fi?';
    }
    HapticFeedback.mediumImpact();
    _hello();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final step = switch (_step) {
      SetupStep.welcome => WelcomeStep(
        onFind: () => _go(SetupStep.search),
        onBrowse: widget.onDone,
      ),
      SetupStep.search => SearchStep(
        services: widget.services,
        onConnect: _connect,
        onBack: _back,
        title: widget.start == SetupStep.search ? 'Add a device' : 'Looking for your device',
      ),
      SetupStep.hello => HelloStep(
        fixed: _fixed,
        onWaving: () => widget.withVibe ? _go(SetupStep.vibe) : widget.onDone(),
        onOff: () => _go(SetupStep.fix),
        onBack: _back,
      ),
      SetupStep.fix => OrientationFix(
        onBack: _back,
        onDone: () {
          _fixed = true;
          _hello();
        },
      ),
      SetupStep.vibe => VibeStep(onDone: widget.onDone, onBack: _back),
    };
    return PopScope(
      canPop: _step == widget.start,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Lb.ink,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: Lb.medium,
            switchInCurve: Lb.ease,
            switchOutCurve: Lb.easeLeave,
            transitionBuilder: (child, anim) {
              final incoming = child.key == ValueKey(_step);
              final from = Offset(0.06 * _dir * (incoming ? 1 : -1), 0);
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: from, end: Offset.zero).animate(anim),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(key: ValueKey(_step), child: step),
          ).ignoringPointer(_settling),
        ),
      ),
    );
  }
}

/// AHA #1: the device plays the Glyph intro; the phone mirrors it.
class HelloStep extends StatelessWidget {
  const HelloStep({
    super.key,
    required this.onWaving,
    required this.onOff,
    this.onBack,
    this.fixed = false,
  });

  final VoidCallback onWaving, onOff;
  final VoidCallback? onBack;
  final bool fixed;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback;
    final devices = scope.devices;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: onBack == null
              ? const SizedBox(height: 48)
              : IconButton(tooltip: 'Back', onPressed: onBack, icon: const Icon(Icons.arrow_back_sharp)),
        ),
        const SizedBox(height: 4),
        ListenableBuilder(
          listenable: Listenable.merge([playback, devices]),
          builder: (context, _) => Stage(
            frame: playback.frame,
            repaint: playback.frameTick,
            deviceName: devices.info?.name ?? devices.selected?.name,
            connected: devices.isConnected,
            maxWidth: 260,
          ),
        ),
        const SizedBox(height: 32),
        if (fixed) ...[
          const Center(child: MonoLabel('Turned the right way')),
          const SizedBox(height: 10),
        ],
        // The one hero line of the flow; display type is otherwise a tab title.
        Text('Look up.', textAlign: TextAlign.center, style: LbType.display),
        const SizedBox(height: 8),
        Text('That\'s your device saying hi.', textAlign: TextAlign.center, style: LbType.title.copyWith(color: Lb.text2)),
        const SizedBox(height: 36),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Lb.cta)),
          onPressed: onWaving,
          child: const Text('Looks right'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Lb.touch)),
          onPressed: onOff,
          child: const Text('Something looks off'),
        ),
      ],
    );
  }
}

/// Picks for the first vibe, by catalog id with category fallbacks.
@visibleForTesting
List<(String, LibraryItem)> firstVibes(Catalog catalog) {
  LibraryItem? pick(List<String> ids, List<String> categories) {
    for (final id in ids) {
      final i = catalog.byId(id);
      if (i != null) return i;
    }
    for (final c in categories) {
      final list = catalog.inCategory(c);
      if (list.isNotEmpty) return list.first;
    }
    return null;
  }

  return [
    if (pick(const ['sleepy-aurora', 'ocean-plasma'], const ['Chill']) case final i?) ('Calm', i),
    if (pick(const ['disco-sparkle', 'rave-tunnel'], const ['Party']) case final i?) ('Party', i),
    if (pick(const ['steamboat-whistle-1928'], const ['Classic Cartoons', 'Retro & Digital']) case final i?)
      ('Classic', i),
  ];
}

/// Step 5: three live tiles; tapping one plays it and we're done.
class VibeStep extends StatelessWidget {
  const VibeStep({super.key, required this.onDone, this.onBack});

  final VoidCallback onDone;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final vibes = firstVibes(AppScope.of(context).catalog);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Row(
          children: [
            if (onBack != null)
              IconButton(tooltip: 'Back', onPressed: onBack, icon: const Icon(Icons.arrow_back_sharp))
            else
              const SizedBox(height: 48),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Lb.text2),
              onPressed: onDone,
              child: const Text('Skip'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Pick a first vibe', style: LbType.title),
        const SizedBox(height: 8),
        Text('It plays on your device straight away.', style: LbType.small),
        const SizedBox(height: 24),
        for (final (label, item) in vibes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _VibeTile(
              label: label,
              item: item,
              onTap: () {
                // It starts playing on the device.
                HapticFeedback.mediumImpact();
                unawaited(GlyphActions.play(context, item));
                onDone();
              },
            ),
          ),
      ],
    );
  }
}

class _VibeTile extends StatelessWidget {
  const _VibeTile({required this.label, required this.item, required this.onTap});

  final String label;
  final LibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LbPanel(
    onTap: onTap,
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        SizedBox.square(
          dimension: 104,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Lb.bezel,
              borderRadius: BorderRadius.circular(Lb.rControl),
              border: Border.all(color: Lb.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: LivePreview(item: item, borderRadius: Lb.rTile),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: LbType.title),
              const SizedBox(height: 6),
              Text(item.title.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: LbType.label),
            ],
          ),
        ),
        const Icon(Icons.play_arrow_sharp, color: Lb.text2),
      ],
    ),
  );
}

extension on Widget {
  Widget ignoringPointer(bool ignoring) => IgnorePointer(ignoring: ignoring, child: this);
}
