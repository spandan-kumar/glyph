// StepLayout takes its body before the action buttons, in reading order.
// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';

import '../../features/device/setup/setup_controller.dart';
import '../design/parts.dart';
import '../design/stage.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../onboarding/orientation_fix.dart';
import '../scope.dart';
import 'setup_parts.dart';

/// "Does it match?": a test picture on the device and on the phone.
class LookScreen extends StatelessWidget {
  const LookScreen({super.key, required this.controller, required this.onUndo});

  final SetupController controller;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return StepLayout(
      title: 'Does it match?',
      line: 'The arrow points up and the orange block sits in the top left corner.',
      gap: 16,
      children: [
        Stage(frame: c.lookFrame, maxWidth: 220),
        const SizedBox(height: 14),
        Center(
          child: c.testError != null
              ? Text(
                  c.testError!,
                  textAlign: TextAlign.center,
                  style: LbType.small.copyWith(color: Lb.danger),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(on: c.testRunning, color: Lb.phosphor),
                    const SizedBox(width: 8),
                    Flexible(child: MonoLabel(c.testRunning ? 'On your device now' : 'Starting the picture')),
                  ],
                ),
        ),
      ],
      primary: SetupPrimary('It matches', onPressed: c.lookMatches),
      secondary: SetupSecondary('It doesn\'t match', onPressed: c.lookDoesNotMatch),
      link: c.hasSnapshot && c.wrote ? SetupLink('Undo setup', onPressed: onUndo, danger: true) : null,
    );
  }
}

/// "Your device is ready." New devices get the Glyph intro and a name.
class DoneScreen extends StatefulWidget {
  const DoneScreen({super.key, required this.controller, required this.onDone});

  final SetupController controller;
  final void Function(String? name) onDone;

  @override
  State<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends State<DoneScreen> {
  TextEditingController? _name;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final scope = AppScope.of(context);
    _name = TextEditingController(text: scope.devices.info?.name ?? scope.devices.selected?.name ?? '');
    if (widget.controller.isNewDevice) {
      // Playing notifies listeners, which mustn't happen mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) playIntro(context);
      });
    }
  }

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final isNew = widget.controller.isNewDevice;
    return StepLayout(
      title: 'Your device is ready.',
      line: isNew ? 'That\'s Glyph saying hi.' : 'Everything is set the way you chose.',
      gap: 16,
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([scope.playback, scope.devices]),
          builder: (context, _) => Stage(
            frame: scope.playback.frame,
            repaint: scope.playback.frameTick,
            deviceName: scope.devices.info?.name ?? scope.devices.selected?.name,
            connected: scope.devices.isConnected,
            maxWidth: 220,
          ),
        ),
        if (isNew) ...[
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            maxLength: 32,
            style: LbType.body,
            decoration: fieldDecoration('Name').copyWith(counterText: ''),
          ),
        ],
      ],
      primary: SetupPrimary('Done', onPressed: () => widget.onDone(isNew ? _name?.text : null)),
    );
  }
}
