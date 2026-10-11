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
import 'grid_diagram.dart';
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
        if (c.sizeProblem != null) ...[
          const SizedBox(height: 10),
          Note(color: Lb.danger, lit: true, text: c.sizeProblem!),
        ],
      ],
      primary: SetupPrimary('Next', onPressed: c.hasSize && c.sizeProblem == null ? c.sizeNext : null),
      link: SetupLink('It\'s made of several panels', onPressed: () => c.switchPanels(several: true)),
    );
  }
}

/// "Is your display one panel or several?": the first Size question.
class PanelsChoiceScreen extends StatelessWidget {
  const PanelsChoiceScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) => StepLayout(
    title: 'Is your display one panel or several?',
    line: 'Several means separate panels joined into one big display.',
    children: [
      _PanelsChoice(
        title: 'One panel',
        line: 'A single block of lights',
        diagram: const PanelDiagram(width: 8, height: 8, maxHeight: 56, dotColor: Lb.text3),
        onTap: () => controller.choosePanels(several: false),
      ),
      const SizedBox(height: 12),
      _PanelsChoice(
        title: 'Several panels',
        line: 'Panels side by side, joined together',
        diagram: const GridDiagram(cols: 3, rows: 2, panelW: 4, panelH: 4, maxHeight: 56, dotColor: Lb.text3),
        onTap: () => controller.choosePanels(several: true),
      ),
    ],
  );
}

class _PanelsChoice extends StatelessWidget {
  const _PanelsChoice({required this.title, required this.line, required this.diagram, required this.onTap});

  final String title, line;
  final Widget diagram;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$title. $line',
    excludeSemantics: true,
    onTap: onTap,
    child: LbPanel(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(width: 104, height: 84, child: Center(child: diagram)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LbType.heading),
                const SizedBox(height: 4),
                Text(line, style: LbType.small),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_sharp, color: Lb.text3),
        ],
      ),
    ),
  );
}

/// "How are the panels laid out?": one panel's size, and how many panels
/// across and down.
class GridScreen extends StatefulWidget {
  const GridScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  State<GridScreen> createState() => _GridScreenState();
}

class _GridScreenState extends State<GridScreen> {
  late bool _other = _isOther();

  bool _isOther() {
    final c = widget.controller;
    return c.hasSize && !panelSizes.contains((c.draftWidth!, c.draftHeight!));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final w = c.draftWidth, h = c.draftHeight;
    return StepLayout(
      title: 'How are the panels laid out?',
      line: 'Pick the size of one panel, then count the panels across and down.',
      gap: 20,
      children: [
        const MonoLabel('One panel is'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) {
            const gap = 8.0;
            final tile = (box.maxWidth - 2 * gap) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (tw, th) in panelSizes)
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
                        child: _Stepper(
                          label: 'Lights across',
                          value: w!,
                          onChanged: (v) => c.setSize(v, h!, click: false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Stepper(
                          label: 'Lights down',
                          value: h!,
                          onChanged: (v) => c.setSize(w, v, click: false),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 20),
        const MonoLabel('Panels'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Stepper(
                label: 'Panels across',
                value: c.draftCols,
                onChanged: (v) => c.setGrid(v, c.draftRows, click: false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Stepper(
                label: 'Panels down',
                value: c.draftRows,
                onChanged: (v) => c.setGrid(c.draftCols, v, click: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (c.hasSize)
          Center(
            child: GridDiagram(
              cols: c.draftCols,
              rows: c.draftRows,
              panelW: w!,
              panelH: h!,
              maxHeight: 220,
              label:
                  'Display diagram, ${c.draftCols} by ${c.draftRows} panels of $w by $h lights, '
                  '${c.displayWidth} by ${c.displayHeight} in all',
            ),
          ),
        const SizedBox(height: 12),
        if (c.hasSize)
          Text(
            '${c.draftCols} × ${c.draftRows} panels of $w×$h is ${c.draftLeds} LEDs, '
            '${c.displayWidth}×${c.displayHeight} in all.',
            style: LbType.small,
          ),
        const SizedBox(height: 6),
        Text('Your device is set for ${c.deviceLeds} LEDs.', style: LbType.small),
        if (c.changesLeds && c.sizeProblem == null) ...[
          const SizedBox(height: 10),
          Note(color: Lb.phosphor, lit: true, text: 'Glyph will set it to ${c.draftLeds} LEDs.'),
        ],
        if (c.sizeProblem != null) ...[
          const SizedBox(height: 10),
          Note(color: Lb.danger, lit: true, text: c.sizeProblem!),
        ],
        if (c.draftCols * c.draftRows < 2) ...[
          const SizedBox(height: 10),
          const Note(text: 'Add at least two panels. For one panel, use the link below.'),
        ],
      ],
      primary: SetupPrimary('Next', onPressed: c.canGridNext ? c.gridNext : null),
      link: SetupLink('It\'s one panel', onPressed: () => c.switchPanels(several: false)),
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
