// StepLayout takes its body before the action buttons, in reading order.
// ignore_for_file: sort_child_properties_last

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/device/setup/setup_controller.dart';
import '../../features/device/widgets/common.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'panel_diagram.dart';
import 'setup_parts.dart';

/// "How big is your display?": common sizes as drawn tiles, or any size.
class SizeScreen extends StatefulWidget {
  const SizeScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  State<SizeScreen> createState() => _SizeScreenState();
}

class _SizeScreenState extends State<SizeScreen> {
  late bool _other = _isOther();

  bool _isOther() {
    final c = widget.controller;
    return c.hasSize && !commonSizes.contains((c.draftWidth!, c.draftHeight!));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final w = c.draftWidth, h = c.draftHeight;
    return StepLayout(
      title: 'How big is your display?',
      line: 'Count the lights across and down.',
      gap: 20,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            const gap = 8.0;
            final tile = (box.maxWidth - 2 * gap) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (tw, th) in commonSizes)
                  SizedBox(
                    width: tile,
                    child: _SizeTile(
                      w: tw,
                      h: th,
                      selected: !_other && w == tw && h == th,
                      onTap: () {
                        setState(() => _other = false);
                        c.setSize(tw, th);
                      },
                    ),
                  ),
                SizedBox(
                  width: tile,
                  child: _OtherTile(
                    selected: _other,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _other = true);
                      if (!c.hasSize) c.setSize(16, 16, click: false);
                    },
                  ),
                ),
              ],
            );
          },
        ),
        AnimatedSize(
          duration: Lb.fast,
          curve: Lb.ease,
          alignment: Alignment.topCenter,
          child: _other && c.hasSize
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Stepper(label: 'Across', value: w!, onChanged: (v) => c.setSize(v, h!, click: false)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Stepper(label: 'Down', value: h!, onChanged: (v) => c.setSize(w, v, click: false)),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 20),
        Text('Your device is set for ${c.deviceLeds} LEDs.', style: LbType.small),
        if (c.changesLeds) ...[
          const SizedBox(height: 10),
          Note(color: Lb.phosphor, lit: true, text: 'Glyph will set it to ${c.draftLeds} LEDs.'),
        ],
      ],
      primary: SetupPrimary('Next', onPressed: c.hasSize ? c.sizeNext : null),
    );
  }
}

class _SizeTile extends StatelessWidget {
  const _SizeTile({required this.w, required this.h, required this.selected, required this.onTap});

  final int w, h;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$w by $h',
    excludeSemantics: true,
    onTap: onTap,
    child: Material(
      color: selected ? Lb.raised : Lb.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Lb.rPanel),
        side: BorderSide(color: selected ? Lb.text : Lb.line, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 56,
                child: Center(
                  child: PanelDiagram(width: w, height: h, maxHeight: 52, dotColor: selected ? Lb.phosphor : Lb.text3),
                ),
              ),
              const SizedBox(height: 8),
              MonoLabel('$w×$h', color: selected ? Lb.text : null),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OtherTile extends StatelessWidget {
  const _OtherTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    excludeSemantics: true,
    label: 'Other size',
    onTap: onTap,
    child: Material(
      color: selected ? Lb.raised : Lb.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Lb.rPanel),
        side: BorderSide(color: selected ? Lb.text : Lb.line, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 92),
          child: Center(
            child: Text('Other size', textAlign: TextAlign.center, style: LbType.bodyStrong),
          ),
        ),
      ),
    ),
  );
}

/// − value + with press-and-hold repeat, 1 to 128.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MonoLabel(label),
      const SizedBox(height: 8),
      Row(
        children: [
          _HoldKey(icon: Icons.remove_sharp, label: 'Fewer $label'.toLowerCase(), onStep: () => onChanged(value - 1)),
          Expanded(
            child: Semantics(
              label: '$label $value',
              excludeSemantics: true,
              child: Text('$value', textAlign: TextAlign.center, style: LbType.title),
            ),
          ),
          _HoldKey(icon: Icons.add_sharp, label: 'More $label'.toLowerCase(), onStep: () => onChanged(value + 1)),
        ],
      ),
    ],
  );
}

class _HoldKey extends StatefulWidget {
  const _HoldKey({required this.icon, required this.label, required this.onStep});

  final IconData icon;
  final String label;
  final VoidCallback onStep;

  @override
  State<_HoldKey> createState() => _HoldKeyState();
}

class _HoldKeyState extends State<_HoldKey> {
  Timer? _hold;
  bool _down = false;

  void _start() {
    setState(() => _down = true);
    HapticFeedback.selectionClick();
    widget.onStep();
    _hold = Timer(const Duration(milliseconds: 450), () {
      _hold = Timer.periodic(const Duration(milliseconds: 90), (_) => widget.onStep());
    });
  }

  void _stop() {
    _hold?.cancel();
    _hold = null;
    if (mounted && _down) setState(() => _down = false);
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    excludeSemantics: true,
    onTap: widget.onStep,
    child: Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: Container(
        width: Lb.touch,
        height: Lb.touch,
        decoration: BoxDecoration(
          color: _down ? Lb.text : Lb.raised,
          border: Border.all(color: Lb.line),
          borderRadius: BorderRadius.circular(Lb.rControl),
        ),
        child: Icon(widget.icon, size: 20, color: _down ? Lb.ink : Lb.text),
      ),
    ),
  );
}
