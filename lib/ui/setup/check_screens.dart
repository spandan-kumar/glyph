// StepLayout takes its body before the action buttons, in reading order.
// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';

import '../../features/device/setup/setup_controller.dart';
import '../../wled/panel_setup.dart';
import '../design/type.dart';
import '../onboarding/orientation_fix.dart';
import 'setup_parts.dart';

/// "Reading your device…", or why it couldn't be read.
class CheckScreen extends StatelessWidget {
  const CheckScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) => controller.checkUnreachable
      ? StepLayout(
          title: 'Can\'t reach it right now',
          line: 'Check it\'s plugged in and on the same Wi-Fi as your phone.',
          primary: SetupPrimary('Try again', onPressed: controller.retryCheck),
        )
      : const BusyBody('Reading your device…');
}

/// "This device has a settings PIN".
class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return StepLayout(
      title: 'This device has a settings PIN',
      line: 'Enter it so Glyph can set up the display.',
      children: [
        TextField(
          controller: _pin,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          style: LbType.body,
          decoration: fieldDecoration('PIN').copyWith(errorText: c.pinError),
          onSubmitted: c.unlock,
        ),
      ],
      primary: SetupPrimary('Unlock', busy: c.pinBusy, onPressed: () => c.unlock(_pin.text)),
    );
  }
}

String unsupportedReason(SetupSupport s) => switch (s) {
  SetupSupport.multiplePanels => 'Its panels aren\'t in a simple grid.',
  SetupSupport.multipleOutputs => 'It uses more than one LED output.',
  SetupSupport.unsupportedOutput => 'Its LEDs aren\'t a type Glyph can set up.',
  SetupSupport.customMap => 'It uses a custom LED map.',
  SetupSupport.realtimeOffset => 'It has a live offset set in its settings.',
  SetupSupport.noTwoD => 'Its firmware has no 2D support.',
  SetupSupport.supported => '',
};

/// "Glyph can't set up this display yet", with the orientation fix instead.
class UnsupportedScreen extends StatelessWidget {
  const UnsupportedScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) => StepLayout(
    title: 'Glyph can\'t set up this display yet',
    line: unsupportedReason(controller.unsupportedReason),
    children: [Text('You can still turn pictures the right way round.', style: LbType.body)],
    primary: SetupPrimary('Fix orientation', onPressed: () => OrientationFixPage.open(context)),
    secondary: SetupSecondary('Done', onPressed: controller.skipToDone),
  );
}
