import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/device/setup/setup_controller.dart';
import '../../features/device/setup/setup_store.dart';
import '../../features/device/setup/setup_wifi.dart';
import '../../features/device/widgets/common.dart';
import '../design/parts.dart';
import '../design/route.dart';
import '../design/tokens.dart';
import '../onboarding/search_step.dart';
import '../scope.dart';
import 'check_screens.dart';
import 'connect_screens.dart';
import 'look_done_screens.dart';
import 'review_screens.dart';
import 'setup_parts.dart';
import 'size_screen.dart';
import 'wiring_screens.dart';

typedef SetupControllerBuilder = SetupController Function(BuildContext context);

/// The device setup wizard (docs: DEVICE_SETUP.md): connect, size, wiring,
/// check. The host draws the top bar and the step transition; every step and
/// every device write lives in [SetupController].
class SetupWizard extends StatefulWidget {
  const SetupWizard({
    super.key,
    this.entry = SetupEntry.newDevice,
    this.services = const SetupServices(),
    required this.onExit,
    required this.onDone,
    this.searchTitle = 'Looking for your device',
    this.controllerBuilder,
  });

  final SetupEntry entry;
  final SetupServices services;

  /// The wizard is left without finishing (Back at the first step, Close).
  final VoidCallback onExit;

  /// The Done step was confirmed.
  final VoidCallback onDone;

  final String searchTitle;

  /// Tests swap in a controller built on fakes.
  final SetupControllerBuilder? controllerBuilder;

  /// Device, Set up display: the selected device, from its Check step.
  static Future<void> open(
    BuildContext context, {
    SetupServices services = const SetupServices(),
    SetupControllerBuilder? controllerBuilder,
  }) =>
      Navigator.of(context)
          .push(lbRoute<void>((_) => _WizardPage(services: services, controllerBuilder: controllerBuilder)));

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _WizardPage extends StatelessWidget {
  const _WizardPage({required this.services, this.controllerBuilder});

  final SetupServices services;
  final SetupControllerBuilder? controllerBuilder;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Lb.ink,
    body: SafeArea(
      child: SetupWizard(
        entry: SetupEntry.existing,
        services: services,
        controllerBuilder: controllerBuilder,
        onExit: () => Navigator.of(context).pop(),
        onDone: () => Navigator.of(context).pop(),
      ),
    ),
  );
}

class _SetupWizardState extends State<SetupWizard> {
  SetupController? _c;
  SetupStep? _last;
  bool _settling = false;
  bool _leaving = false;

  SetupController get c => _c!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final built = widget.controllerBuilder?.call(context) ?? _defaultController(context);
    _c = built;
    _last = built.step;
    // Starting may notify; the first build hasn't happened yet.
    built
      ..begin()
      ..addListener(_onChange);
  }

  SetupController _defaultController(BuildContext context) {
    final scope = AppScope.of(context);
    final wifi = PlatformSetupWifi();
    final controller = SetupController(
      devices: scope.devices,
      playback: scope.playback,
      wifi: wifi,
      store: SetupStore(),
      entry: widget.entry,
      services: widget.services,
    );
    unawaited(wifi.probe().then((_) => controller.refreshWifi()));
    return controller;
  }

  void _onChange() {
    if (!mounted) return;
    if (c.step != _last) {
      _last = c.step;
      setState(() => _settling = true);
      Future<void>.delayed(Lb.medium + const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _settling = false);
      });
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_onChange);
    _c?.dispose();
    super.dispose();
  }

  Future<void> _back() async {
    if (_leaving || c.back()) return;
    await _exit();
  }

  /// Leaves without finishing. After a write, asks whether to keep it.
  Future<void> _exit() async {
    if (_leaving) return;
    if (c.needsDecision) {
      final keep = await showModalBottomSheet<bool>(context: context, builder: (_) => const _KeepSheet());
      if (keep == null || !mounted) return;
      if (!keep) {
        final messenger = ScaffoldMessenger.of(context);
        final ok = await c.undo();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(ok ? 'Your previous setup is back.' : 'Some changes couldn\'t be undone.')),
          );
        if (!mounted) return;
      }
    }
    _leaving = true;
    await c.cleanUp().timeout(const Duration(seconds: 4), onTimeout: () {});
    if (mounted) widget.onExit();
  }

  Future<void> _done(String? name) async {
    if (_leaving) return;
    _leaving = true;
    await c.finish(name: name).timeout(const Duration(seconds: 4), onTimeout: () {});
    if (mounted) widget.onDone();
  }

  Future<void> _undo() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await c.undoAndRestart();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(ok ? 'Put back the previous setup.' : 'Some changes couldn\'t be undone.')),
      );
  }

  Widget _screen(SetupStep step) => switch (step) {
    SetupStep.connect => ConnectScreen(controller: c),
    SetupStep.search => SearchStep(
      services: widget.services,
      onConnect: c.connectFound,
      title: widget.searchTitle,
      embedded: true,
    ),
    SetupStep.join => JoinScreen(controller: c),
    SetupStep.wifi => WifiScreen(controller: c),
    SetupStep.joining => JoiningScreen(controller: c),
    SetupStep.joinFailed => JoinFailedScreen(controller: c, services: widget.services),
    SetupStep.check => CheckScreen(controller: c),
    SetupStep.pin => PinScreen(controller: c),
    SetupStep.unsupported => UnsupportedScreen(controller: c),
    SetupStep.size => SizeScreen(controller: c),
    SetupStep.wiringQ1 ||
    SetupStep.wiringQ2 ||
    SetupStep.wiringQ3 => WiringQuestionScreen(controller: c, question: step),
    SetupStep.wiringResult => WiringResultScreen(controller: c),
    SetupStep.wiringManual => WiringManualScreen(controller: c),
    SetupStep.review => ReviewScreen(controller: c),
    SetupStep.applying => ApplyingScreen(controller: c),
    SetupStep.applyFailed => ApplyFailedScreen(controller: c, onDone: _exit, onUndo: _undo),
    SetupStep.look => LookScreen(controller: c, onUndo: _undo),
    SetupStep.done => DoneScreen(controller: c, onDone: _done),
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      c.reduceMotion = Lb.reduceMotion(context);
      final step = c.step;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Column(
          children: [
            _TopBar(
              step: step,
              showBack: step != SetupStep.applying && step != SetupStep.done,
              showClose: c.canClose,
              onBack: _back,
              onClose: _exit,
            ),
            Expanded(
              child: IgnorePointer(
                ignoring: _settling,
                child: AnimatedSwitcher(
                  duration: Lb.medium,
                  switchInCurve: Lb.ease,
                  switchOutCurve: Lb.easeLeave,
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == ValueKey(step);
                    final from = Offset(0.06 * c.direction * (incoming ? 1 : -1), 0);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: from, end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(key: ValueKey(step), child: _screen(step)),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Back, four chapter dots and Close.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.step,
    required this.showBack,
    required this.showClose,
    required this.onBack,
    required this.onClose,
  });

  final SetupStep step;
  final bool showBack, showClose;
  final VoidCallback onBack, onClose;

  static const chapters = ['Connect', 'Size', 'Wiring', 'Check'];

  /// Which chapter a step belongs to; 4 once everything is done.
  static int chapterOf(SetupStep s) => switch (s) {
    SetupStep.size => 1,
    SetupStep.wiringQ1 ||
    SetupStep.wiringQ2 ||
    SetupStep.wiringQ3 ||
    SetupStep.wiringResult ||
    SetupStep.wiringManual => 2,
    SetupStep.review || SetupStep.applying || SetupStep.applyFailed || SetupStep.look => 3,
    SetupStep.done => 4,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final at = chapterOf(step);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          SizedBox.square(
            dimension: Lb.touch,
            child: showBack
                ? IconButton(tooltip: 'Back', onPressed: onBack, icon: const Icon(Icons.arrow_back_sharp))
                : null,
          ),
          Expanded(
            child: Semantics(
              label: at >= 4 ? 'All steps done' : 'Step ${at + 1} of 4, ${chapters[at]}',
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < chapters.length; i++)
                        Expanded(
                          child: Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: at >= 4 || i == at ? Lb.phosphor : (i < at ? Lb.text2 : Lb.ledOff),
                                boxShadow: at >= 4 || i == at
                                    ? [BoxShadow(color: Lb.phosphor.withValues(alpha: 0.6), blurRadius: 6)]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  MonoLabel(chapters[at.clamp(0, 3)], color: Lb.text),
                ],
              ),
            ),
          ),
          SizedBox.square(
            dimension: Lb.touch,
            child: showClose
                ? IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close_sharp))
                : null,
          ),
        ],
      ),
    );
  }
}

/// "Keep the new setup?" after something on the device changed.
class _KeepSheet extends StatelessWidget {
  const _KeepSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle('Keep the new setup?', subtitle: 'Your device was changed. Keep it, or put it back.'),
          SetupPrimary('Keep it', onPressed: () => Navigator.pop(context, true)),
          const SizedBox(height: 8),
          SetupSecondary('Undo it', onPressed: () => Navigator.pop(context, false)),
        ],
      ),
    ),
  );
}
