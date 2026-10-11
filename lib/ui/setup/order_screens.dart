// StepLayout takes its body before the action buttons, in reading order.
// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';

import '../../features/device/setup/setup_controller.dart';
import '../../features/device/widgets/common.dart';
import '../../wled/panel_grid.dart';
import '../../wled/panel_setup.dart';
import '../design/parts.dart';
import '../design/toggle.dart';
import '../design/tokens.dart';
import '../make/studio_kit.dart';
import 'grid_diagram.dart';
import 'setup_parts.dart';
import 'wiring_screens.dart';

/// "Row 1, column 2": a panel named by where it sits, for screen readers.
String _where(int cx, int cy) => 'Panel in row ${cy + 1}, column ${cx + 1}';

/// The three panel-order questions. Each one lights the first few LEDs of
/// one panel on the device and draws the grid of panels to answer on.
class OrderQuestionScreen extends StatelessWidget {
  const OrderQuestionScreen({super.key, required this.controller, required this.question});

  final SetupController controller;
  final SetupStep question;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final w = c.draftWidth ?? 8, h = c.draftHeight ?? 8;
    final first = c.firstCell;
    final (title, line) = switch (question) {
      SetupStep.orderQ1 => ('Which panel lit up?', 'The first few lights of one panel are on. Tap that panel.'),
      SetupStep.orderQ2 => (
        'Which panel is next?',
        'The first few lights of the next panel in the chain are on. Tap it, or pick the way below.',
      ),
      _ => (
        'Where did it jump to?',
        c.answerChainAcross == false
            ? 'The first panel of the second column is lit. This is where that column starts.'
            : 'The first panel of the second row is lit. This is where that row starts.',
      ),
    };
    final jump = c.jumpCells;
    final diagram = switch (question) {
      SetupStep.orderQ1 => GridDiagram(
        cols: c.draftCols,
        rows: c.draftRows,
        panelW: w,
        panelH: h,
        targets: c.firstPanelCells,
        onPanel: c.pickFirstPanel,
        cellLabel: _where,
        label: 'Panel grid, ${c.draftCols} by ${c.draftRows}. Tap the panel that lit up.',
      ),
      SetupStep.orderQ2 => GridDiagram(
        cols: c.draftCols,
        rows: c.draftRows,
        panelW: w,
        panelH: h,
        targets: c.nextPanelCells,
        selected: {?first},
        onPanel: c.pickNextPanel,
        cellLabel: _where,
        label: 'Panel grid. The first panel is marked. Tap the one that is next.',
      ),
      _ => GridDiagram(
        cols: c.draftCols,
        rows: c.draftRows,
        panelW: w,
        panelH: h,
        targets: jump == null ? const {} : {jump.near, jump.far},
        selected: {?first},
        onPanel: (cell) => c.pickChainJump(snake: cell == jump?.far),
        cellLabel: (x, y) => (x, y) == jump?.near ? 'Same side as the first panel' : 'The far side',
        label: 'Panel grid. Tap where the chain jumped to, or pick below.',
      ),
    };
    final showHelp = c.testNeedsMoreLeds;
    return StepLayout(
      title: title,
      line: line,
      gap: 16,
      children: [
        if (c.wiringNote != null) Note(color: Lb.phosphor, lit: true, text: c.wiringNote!),
        Center(child: diagram),
        if (question != SetupStep.orderQ1) ...[const SizedBox(height: 16), ..._options(c)],
        const SizedBox(height: 12),
        Center(child: DeviceTestStatus(controller: c)),
        if (showHelp) ...[
          const SizedBox(height: 16),
          Note(
            color: Lb.phosphor,
            lit: true,
            text: 'Your device is set for ${c.deviceLeds} LEDs, so these lights can\'t show yet.',
          ),
          if (c.changesLeds) SetupSecondary('Set it to ${c.draftLeds} LEDs now', onPressed: c.setLedsNow),
        ],
      ],
      link: question == SetupStep.orderQ1
          ? SetupLink('Nothing lit up', onPressed: () => showNothingLit(context, c))
          : null,
    );
  }

  List<Widget> _options(SetupController c) {
    final corner = c.answerPanelCorner ?? StartCorner.topLeft;
    final rows = <Widget>[];
    if (question == SetupStep.orderQ2) {
      rows
        ..add(
          OptionRow(
            icon: corner.isRight ? Icons.arrow_back_sharp : Icons.arrow_forward_sharp,
            label: 'Across',
            onTap: () => c.pickChainRun(across: true),
          ),
        )
        ..add(
          OptionRow(
            icon: corner.isBottom ? Icons.arrow_upward_sharp : Icons.arrow_downward_sharp,
            label: corner.isBottom ? 'Up' : 'Down',
            onTap: () => c.pickChainRun(across: false),
          ),
        );
    } else {
      final across = c.answerChainAcross ?? true;
      final (nearIcon, nearLabel, farIcon, farLabel) = across
          ? corner.isRight
                ? (Icons.arrow_forward_sharp, 'On the right', Icons.arrow_back_sharp, 'On the left')
                : (Icons.arrow_back_sharp, 'On the left', Icons.arrow_forward_sharp, 'On the right')
          : corner.isBottom
          ? (Icons.arrow_downward_sharp, 'At the bottom', Icons.arrow_upward_sharp, 'At the top')
          : (Icons.arrow_upward_sharp, 'At the top', Icons.arrow_downward_sharp, 'At the bottom');
      final near = OptionRow(icon: nearIcon, label: nearLabel, onTap: () => c.pickChainJump(snake: false));
      final far = OptionRow(icon: farIcon, label: farLabel, onTap: () => c.pickChainJump(snake: true));
      // Fixed order: left before right, top before bottom.
      final nearFirst = across ? !corner.isRight : !corner.isBottom;
      rows.addAll(nearFirst ? [near, far] : [far, near]);
    }
    return [
      for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 8), rows[i]],
    ];
  }
}

/// "Here's the panel order": numbered panels and the path between them.
class OrderResultScreen extends StatelessWidget {
  const OrderResultScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final chain = c.draftChain ?? const PanelWiring(zigzag: true);
    return StepLayout(
      title: 'Here\'s the panel order',
      line: describeChainOf(chain, c.draftCols, c.draftRows),
      children: [
        Center(
          child: GridDiagram(
            cols: c.draftCols,
            rows: c.draftRows,
            panelW: c.draftWidth ?? 8,
            panelH: c.draftHeight ?? 8,
            chain: chain,
            numbers: true,
            showPath: true,
            label: 'Panel order diagram. ${describeChainOf(chain, c.draftCols, c.draftRows)}',
          ),
        ),
      ],
      primary: SetupPrimary('Looks right', onPressed: c.orderLooksRight),
      secondary: SetupSecondary('Test again', onPressed: c.orderTestAgain),
      link: SetupLink('Choose it myself', onPressed: c.chooseManualOrder),
    );
  }
}

class OrderConfirmScreen extends StatelessWidget {
  const OrderConfirmScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final chain = c.draftChain ?? const PanelWiring();
    final cell = c.draftPositions?[c.orderPanel] ?? chain.positionOf(c.orderPanel, c.draftCols, c.draftRows);
    return StepLayout(
      title: 'Do they follow the numbers?',
      line: 'The panels light up one by one in the order shown.',
      children: [
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: c.reduceMotion ? c.nextOrderPanel : null,
            child: GridDiagram(
              cols: c.draftCols,
              rows: c.draftRows,
              panelW: c.draftWidth!,
              panelH: c.draftHeight!,
              chain: chain,
              positions: c.draftPositions,
              numbers: true,
              selected: {cell},
              label: 'Panel ${c.orderPanel + 1} is lit',
            ),
          ),
        ),
        if (c.reduceMotion) SetupSecondary('Next panel', onPressed: c.nextOrderPanel),
        Center(child: DeviceTestStatus(controller: c)),
        if (c.testNeedsMoreLeds) ...[
          Note(text: 'Your device is set for ${c.deviceLeds} LEDs, so these lights can\'t show yet.'),
          SetupSecondary('Set it to ${c.draftLeds} LEDs now', onPressed: c.setLedsNow),
        ],
      ],
      primary: SetupPrimary('Yes, in order', onPressed: c.orderConfirmed),
      secondary: SetupSecondary('No', onPressed: c.orderIncorrect),
    );
  }
}

class OrderTapScreen extends StatelessWidget {
  const OrderTapScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return StepLayout(
      title: 'Which panel lit up?',
      line: 'Panel ${c.orderPanel + 1} of ${c.draftPanels}. Tap the panel that lit up.',
      children: [
        Center(
          child: GridDiagram(
            cols: c.draftCols,
            rows: c.draftRows,
            panelW: c.draftWidth!,
            panelH: c.draftHeight!,
            chain: const PanelWiring(),
            numbers: true,
            targets: c.untappedPanels,
            onPanel: c.pickLitPanel,
            cellLabel: _where,
          ),
        ),
        Center(child: DeviceTestStatus(controller: c)),
        if (c.testNeedsMoreLeds) ...[
          Note(text: 'Your device is set for ${c.deviceLeds} LEDs, so these lights can\'t show yet.'),
          SetupSecondary('Set it to ${c.draftLeds} LEDs now', onPressed: c.setLedsNow),
        ],
      ],
    );
  }
}

/// Picking the panel order by hand with a live diagram.
class OrderManualScreen extends StatelessWidget {
  const OrderManualScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final chain = c.draftChain ?? const PanelWiring(zigzag: true);
    final here = c.cornerCell(chain.corner);
    final both = c.draftCols > 1 && c.draftRows > 1;
    final runs = chain.vertical ? c.draftCols : c.draftRows;
    String cornerWord(StartCorner k) => c.draftRows == 1
        ? (k.isRight ? 'Right' : 'Left')
        : c.draftCols == 1
        ? (k.isBottom ? 'Bottom' : 'Top')
        : _cap(k.label);
    return StepLayout(
      title: 'How are the panels chained?',
      line: describeChainOf(chain, c.draftCols, c.draftRows),
      gap: 16,
      children: [
        Center(
          child: GridDiagram(
            cols: c.draftCols,
            rows: c.draftRows,
            panelW: c.draftWidth ?? 8,
            panelH: c.draftHeight ?? 8,
            chain: chain,
            numbers: true,
            showPath: true,
            label: 'Panel order diagram. ${describeChainOf(chain, c.draftCols, c.draftRows)}',
          ),
        ),
        const SizedBox(height: 20),
        const MonoLabel('The first panel is at'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in c.firstPanelCorners)
              SetupChip(
                label: cornerWord(k),
                selected: c.cornerCell(k) == here,
                onTap: () => c.setManualOrder(corner: k),
              ),
          ],
        ),
        if (both) ...[
          const SizedBox(height: 20),
          const MonoLabel('The chain runs'),
          const SizedBox(height: 10),
          StudioSegments<bool>(
            options: const [(false, 'Across'), (true, 'Down')],
            selected: chain.vertical,
            onChanged: (v) => c.setManualOrder(vertical: v),
          ),
        ],
        if (runs > 1) ...[
          const SizedBox(height: 8),
          LbToggleTile(
            title: 'Snake',
            subtitle: 'Every second run turns back',
            value: chain.zigzag,
            onChanged: (v) => c.setManualOrder(zigzag: v),
          ),
        ],
      ],
      primary: SetupPrimary('Use this', onPressed: c.orderLooksRight),
    );
  }
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

/// "Are any panels upside down?": every panel's first light is on at once;
/// tap the panels where it isn't in the same corner.
class OrientationScreen extends StatelessWidget {
  const OrientationScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final g = c.draftGrid;
    if (g == null) return const SizedBox.shrink();
    final base = c.draftWiring?.corner ?? StartCorner.topLeft;
    final flipped = StartCorner.of(bottom: !base.isBottom, right: !base.isRight);
    final cells = {for (var k = 0; k < g.panelCount; k++) g.cellOf(k)};
    final reference = g.cellOf(0);
    final showHelp = c.testNeedsMoreLeds;
    return StepLayout(
      title: 'Are any panels upside down?',
      line: 'Each panel\'s first light should sit in the same corner. Tap any panel where it doesn\'t.',
      gap: 16,
      children: [
        Center(
          child: GridDiagram(
            cols: c.draftCols,
            rows: c.draftRows,
            panelW: c.draftWidth ?? 8,
            panelH: c.draftHeight ?? 8,
            targets: {...cells}..remove(reference),
            selected: c.flippedCells,
            firstLights: {
              for (final cell in cells) cell: c.flippedCells.contains(cell) && cell != reference ? flipped : base,
            },
            onPanel: c.toggleFlipped,
            cellLabel: (x, y) {
              final k = g.panelAt(x, y) + 1;
              return c.flippedCells.contains((x, y)) ? 'Panel $k, marked upside down' : 'Panel $k';
            },
            label: 'Panel grid. The amber dot is where each panel\'s first light sits.',
          ),
        ),
        const SizedBox(height: 12),
        Center(child: DeviceTestStatus(controller: c)),
        if (showHelp) ...[
          const SizedBox(height: 16),
          Note(
            color: Lb.phosphor,
            lit: true,
            text: 'Your device is set for ${c.deviceLeds} LEDs, so these lights can\'t show yet.',
          ),
          if (c.changesLeds) SetupSecondary('Set it to ${c.draftLeds} LEDs now', onPressed: c.setLedsNow),
        ],
      ],
      primary: SetupPrimary('Done', onPressed: c.orientationDone),
      link: SetupLink('Panels turned sideways?', onPressed: () => _showSideways(context)),
    );
  }
}

Future<void> _showSideways(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (ctx) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle('Turned sideways?'),
          const Note(text: 'Glyph can set up panels that are the same way up, or turned upside down.'),
          const Note(text: 'A panel turned a quarter turn isn\'t supported yet. Turn it to match the others.'),
          const SizedBox(height: 8),
          SetupPrimary('OK', onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    ),
  ),
);
