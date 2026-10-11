// StepLayout takes its body before the action buttons, in reading order.
// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';

import '../../features/device/setup/setup_controller.dart';
import '../../features/device/widgets/common.dart';
import '../../wled/panel_setup.dart';
import '../design/parts.dart';
import '../design/toggle.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../make/studio_kit.dart';
import 'panel_diagram.dart';
import 'setup_parts.dart';

/// The three wiring questions. Each one lights real LEDs on the device and
/// draws the display as a dim grid to answer on.
class WiringQuestionScreen extends StatelessWidget {
  const WiringQuestionScreen({super.key, required this.controller, required this.question});

  final SetupController controller;
  final SetupStep question;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final w = c.draftWidth ?? 8, h = c.draftHeight ?? 8;
    final (title, line) = switch (question) {
      SetupStep.wiringQ1 => ('Which corner lit up?', 'One light is on at the start of the wiring. Tap that corner.'),
      SetupStep.wiringQ2 => (
        'Which way is it moving?',
        'The lights run from that corner. Pick the way the arrows point.',
      ),
      _ => ('Where did the light jump to?', 'This is where the second row of wiring starts.'),
    };
    final diagram = switch (question) {
      SetupStep.wiringQ1 => PanelDiagram(
        width: w,
        height: h,
        onCorner: c.pickCorner,
        label: 'Display diagram, $w by $h lights. Tap the corner that lit up.',
      ),
      SetupStep.wiringQ2 => PanelDiagram(
        width: w,
        height: h,
        corner: c.answerCorner,
        zoom: true,
        showRunArrows: true,
        label: 'Display diagram, starting at the ${c.answerCorner?.label} corner. Pick the way the lights move below.',
      ),
      _ => PanelDiagram(
        width: w,
        height: h,
        corner: c.answerCorner,
        alongWidth: c.answerAlongWidth,
        zoom: true,
        onJump: (far) => c.pickJump(farEnd: far),
        label: 'Display diagram. Tap where the light jumped to, or pick below.',
      ),
    };
    final showHelp = c.testNeedsMoreLeds || (c.deviceLeds < c.draftLeds && question == SetupStep.wiringQ3);
    return StepLayout(
      title: title,
      line: line,
      gap: 16,
      children: [
        if (c.wiringNote != null) Note(color: Lb.phosphor, lit: true, text: c.wiringNote!),
        Center(child: diagram),
        if (question != SetupStep.wiringQ1) ...[const SizedBox(height: 16), ..._options(c)],
        const SizedBox(height: 12),
        Center(child: _DeviceStatus(controller: c)),
        if (showHelp) ...[
          const SizedBox(height: 16),
          Note(
            color: Lb.phosphor,
            lit: true,
            text: 'Your device is set for ${c.deviceLeds} LEDs, so this light can\'t show yet.',
          ),
          if (c.changesLeds) SetupSecondary('Set it to ${c.draftLeds} LEDs now', onPressed: c.setLedsNow),
        ],
      ],
      link: question == SetupStep.wiringQ1
          ? SetupLink('Nothing lit up', onPressed: () => _nothingLit(context, c))
          : null,
    );
  }
}

List<Widget> _options(SetupController c) {
  final corner = c.answerCorner ?? StartCorner.topLeft;
  final rows = <Widget>[];
  if (c.step == SetupStep.wiringQ2) {
    rows
      ..add(
        _OptionRow(
          icon: corner.isRight ? Icons.arrow_back_sharp : Icons.arrow_forward_sharp,
          label: 'Across',
          onTap: () => c.pickRun(alongWidth: true),
        ),
      )
      ..add(
        _OptionRow(
          icon: corner.isBottom ? Icons.arrow_upward_sharp : Icons.arrow_downward_sharp,
          label: corner.isBottom ? 'Up' : 'Down',
          onTap: () => c.pickRun(alongWidth: false),
        ),
      );
  } else {
    // The near end is the same end the first run started at (straight); the
    // far end is the zig-zag.
    final rowsRun = c.answerAlongWidth ?? true;
    final (nearIcon, nearLabel, farIcon, farLabel) = rowsRun
        ? corner.isRight
              ? (Icons.arrow_forward_sharp, 'On the right', Icons.arrow_back_sharp, 'On the left')
              : (Icons.arrow_back_sharp, 'On the left', Icons.arrow_forward_sharp, 'On the right')
        : corner.isBottom
        ? (Icons.arrow_downward_sharp, 'At the bottom', Icons.arrow_upward_sharp, 'At the top')
        : (Icons.arrow_upward_sharp, 'At the top', Icons.arrow_downward_sharp, 'At the bottom');
    final near = _OptionRow(icon: nearIcon, label: nearLabel, onTap: () => c.pickJump(farEnd: false));
    final far = _OptionRow(icon: farIcon, label: farLabel, onTap: () => c.pickJump(farEnd: true));
    // Fixed order: left before right, top before bottom.
    final nearFirst = rowsRun ? !corner.isRight : !corner.isBottom;
    rows.addAll(nearFirst ? [near, far] : [far, near]);
  }
  return [
    for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 8), rows[i]],
  ];
}

/// A full-width answer: icon and label in a panel, at least 56px tall.
class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: LbPanel(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Lb.text, size: 24),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: LbType.bodyStrong)),
          ],
        ),
      ),
    ),
  );
}

class _DeviceStatus extends StatelessWidget {
  const _DeviceStatus({required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.testError != null) {
      return Text(
        c.testError!,
        textAlign: TextAlign.center,
        style: LbType.small.copyWith(color: Lb.danger),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(on: c.testRunning, color: Lb.phosphor),
        const SizedBox(width: 8),
        Flexible(child: MonoLabel(c.testRunning ? 'Lit on your device' : 'Starting the test')),
      ],
    );
  }
}

Future<void> _nothingLit(BuildContext context, SetupController c) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle('Nothing lit up?'),
          const Note(text: 'Check it\'s plugged in and switched on in Glyph.'),
          const Note(
            text: 'Its LED output may be set to the wrong pin. Change it in WLED firmware settings, then LED preferences.',
          ),
          Note(text: 'Your device is set for ${c.deviceLeds} LEDs.'),
          const SizedBox(height: 8),
          if (c.changesLeds && c.deviceLeds < c.draftLeds) ...[
            SetupSecondary(
              'Set it to ${c.draftLeds} LEDs now',
              onPressed: () {
                Navigator.pop(ctx);
                c.setLedsNow();
              },
            ),
            const SizedBox(height: 8),
          ],
          SetupPrimary(
            'Try again',
            onPressed: () {
              Navigator.pop(ctx);
              c.retryTest();
            },
          ),
        ],
      ),
    ),
  ),
);

/// "Here's how it's wired": the LED path drawn through the display.
class WiringResultScreen extends StatelessWidget {
  const WiringResultScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final w = c.draftWidth ?? 8, h = c.draftHeight ?? 8;
    final wiring = c.draftWiring ?? const PanelWiring();
    return StepLayout(
      title: 'Here\'s how it\'s wired',
      line: wiring.describe(),
      children: [
        Center(
          child: PanelDiagram(
            width: w,
            height: h,
            wiring: wiring,
            showPath: true,
            label: 'Display diagram showing the wiring. ${wiring.describe()}',
          ),
        ),
      ],
      primary: SetupPrimary('Looks right', onPressed: c.looksRight),
      secondary: SetupSecondary('Test again', onPressed: c.testAgain),
      link: SetupLink('Choose it myself', onPressed: c.chooseManual),
    );
  }
}

/// Picking the wiring by hand with a live diagram.
class WiringManualScreen extends StatelessWidget {
  const WiringManualScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final w = c.draftWidth ?? 8, h = c.draftHeight ?? 8;
    final wiring = c.draftWiring ?? const PanelWiring();
    return StepLayout(
      title: 'How is it wired?',
      line: wiring.describe(),
      gap: 16,
      children: [
        Center(
          child: PanelDiagram(
            width: w,
            height: h,
            wiring: wiring,
            showPath: true,
            label: 'Display diagram showing the wiring. ${wiring.describe()}',
          ),
        ),
        const SizedBox(height: 20),
        const MonoLabel('Starts at'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in StartCorner.values)
              SetupChip(
                label: _cap(k.label),
                selected: wiring.corner == k,
                onTap: () => c.setManualWiring(corner: k),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const MonoLabel('Runs along'),
        const SizedBox(height: 10),
        StudioSegments<bool>(
          options: const [(false, 'Rows'), (true, 'Columns')],
          selected: wiring.vertical,
          onChanged: (v) => c.setManualWiring(vertical: v),
        ),
        const SizedBox(height: 8),
        LbToggleTile(
          title: 'Zig-zag',
          subtitle: 'Every second run turns back',
          value: wiring.zigzag,
          onChanged: (v) => c.setManualWiring(zigzag: v),
        ),
      ],
      primary: SetupPrimary('Use this', onPressed: c.looksRight),
    );
  }
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);
