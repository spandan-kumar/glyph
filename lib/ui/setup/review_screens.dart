// StepLayout takes its body before the action buttons, in reading order.
// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/device/setup/setup_controller.dart';
import '../../features/device/widgets/common.dart';
import '../../wled/panel_setup.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'setup_parts.dart';

/// "Ready to set it up": what will change, and the optional power limit.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final setup = c.draftSetup;
    Widget value(String v) => Text(v, style: LbType.mono.copyWith(color: Lb.text));
    final limit = c.newLimitMa;
    return StepLayout(
      title: 'Ready to set it up',
      line: 'Takes a few seconds. You can undo it.',
      gap: 20,
      children: [
        if (setup != null)
          RowGroup(
            children: [
              Row1(title: 'Size', trailing: value('${setup.width}×${setup.height}')),
              Row1(title: 'Wiring', subtitle: setup.wiring.describe()),
              Row1(
                title: 'LEDs',
                trailing: c.changesLeds
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          value('${c.deviceLeds}'),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward_sharp, size: 14, color: Lb.text2),
                          ),
                          value('${c.draftLeds}'),
                        ],
                      )
                    : value('${c.draftLeds}'),
              ),
              Row1(
                title: 'Power limit',
                subtitle: 'Optional',
                trailing: value(switch ((limit, c.currentLimitMa)) {
                  (final int chosen, _) => '$chosen mA',
                  (_, final int cur) when cur > 0 => '$cur mA',
                  (_, 0) => 'No limit',
                  _ => 'Not set',
                }),
                onTap: () => showPowerSheet(context, c),
              ),
            ],
          ),
      ],
      primary: SetupPrimary('Set up device', onPressed: c.apply),
    );
  }
}

/// "What powers it?": the supply's amps give a brightness limit.
Future<void> showPowerSheet(BuildContext context, SetupController c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PowerSheet(controller: c),
  );
}

class _PowerSheet extends StatefulWidget {
  const _PowerSheet({required this.controller});

  final SetupController controller;

  @override
  State<_PowerSheet> createState() => _PowerSheetState();
}

class _PowerSheetState extends State<_PowerSheet> {
  static const _amps = [1.0, 2.0, 3.0, 4.0, 5.0, 10.0];
  late double? _value = widget.controller.supplyAmps;
  late bool _other = _value != null && !_amps.contains(_value);
  final _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_other) _field.text = '$_value';
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.controller.currentLimitMa;
    final v = _value;
    final limit = v == null ? null : recommendedLimitMa(v, cur);
    final keeps = v != null && cur != null && cur > 0 && recommendedLimitMa(v, null) > cur;
    final now = cur == null ? '' : (cur <= 0 ? ' (now no limit)' : ' (now $cur mA)');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetTitle('What powers it?', subtitle: 'Pick the amps on its power supply.'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in _amps)
                    SetupChip(
                      label: '${a.toInt()} A',
                      selected: !_other && _value == a,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _other = false;
                          _value = a;
                        });
                      },
                    ),
                  SetupChip(
                    label: 'Other',
                    selected: _other,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _other = true;
                        _value = double.tryParse(_field.text);
                      });
                    },
                  ),
                ],
              ),
              if (_other) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _field,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: LbType.body,
                  decoration: fieldDecoration('Amps'),
                  onChanged: (t) {
                    final a = double.tryParse(t);
                    setState(() => _value = a != null && a > 0 && a <= 100 ? a : null);
                  },
                ),
              ],
              const SizedBox(height: 16),
              if (limit != null) ...[
                Text('Brightness limit $limit mA$now', style: LbType.bodyStrong),
                if (keeps) ...[
                  const SizedBox(height: 8),
                  const Note(text: 'Your current limit is lower, so Glyph keeps it.'),
                ],
                const SizedBox(height: 12),
              ],
              SetupPrimary(
                'Use this limit',
                onPressed: limit == null
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        widget.controller.setSupply(_value);
                        Navigator.pop(context);
                      },
              ),
              const SizedBox(height: 8),
              SetupSecondary(
                'Leave as it is',
                onPressed: () {
                  widget.controller.setSupply(null);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The steps of the write, each with an LED that lights when it is done.
class ApplyingScreen extends StatelessWidget {
  const ApplyingScreen({super.key, required this.controller});

  final SetupController controller;

  static String label(ApplyPhase p) => switch (p) {
    ApplyPhase.backup => 'Saving a backup',
    ApplyPhase.leds => 'Setting the LEDs',
    ApplyPhase.layout => 'Setting the size and wiring',
    ApplyPhase.verify => 'Checking it worked',
  };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final phases = c.applyPhases;
    final at = phases.indexOf(c.applyPhase);
    return StepLayout(
      title: 'Setting up your device',
      line: 'Keep the app open.',
      children: [
        for (var i = 0; i < phases.length; i++)
          StepStatusRow(
            label: label(phases[i]),
            state: i < at
                ? ProgressState.done
                : i == at
                ? ProgressState.current
                : ProgressState.waiting,
          ),
      ],
    );
  }
}

/// Everything written was rolled back; try again or finish.
class ApplyFailedScreen extends StatelessWidget {
  const ApplyFailedScreen({super.key, required this.controller, required this.onDone, required this.onUndo});

  final SetupController controller;
  final VoidCallback onDone, onUndo;

  @override
  Widget build(BuildContext context) {
    final failed = controller.rollbackFailed;
    return StepLayout(
      title: 'Couldn\'t finish setting it up',
      line: failed ? 'Some changes couldn\'t be undone.' : 'Glyph put everything back.',
      primary: failed
          ? SetupPrimary('Undo setup', onPressed: onUndo)
          : SetupPrimary('Try again', onPressed: controller.apply),
      secondary: SetupSecondary('Done', onPressed: onDone),
    );
  }
}
