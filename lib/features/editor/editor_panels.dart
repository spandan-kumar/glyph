import 'package:flutter/material.dart';

import '../../ui/design/parts.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/studio_kit.dart';
import 'editor_canvas.dart';
import 'editor_model.dart';

/// The seven drawing tools, spread evenly so they fit any phone width.
class EditorToolBar extends StatelessWidget {
  const EditorToolBar({super.key, required this.model});

  final EditorModel model;

  static const _tools = <(EditorTool, String, IconData?)>[
    (EditorTool.pencil, 'Pencil', Icons.edit_sharp),
    (EditorTool.eraser, 'Eraser', null),
    (EditorTool.fill, 'Fill', Icons.format_color_fill_sharp),
    (EditorTool.picker, 'Pick colour', Icons.colorize_sharp),
    (EditorTool.line, 'Line', Icons.horizontal_rule_sharp),
    (EditorTool.rect, 'Rectangle', Icons.crop_square_sharp),
    (EditorTool.move, 'Move', Icons.open_with_sharp),
  ];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          for (final (t, label, icon) in _tools)
            Expanded(
              child: _ToggleIcon(
                tooltip: label,
                selected: model.tool == t,
                onTap: () => model.tool = t,
                child: icon == null ? const _EraserIcon() : Icon(icon, size: 22),
              ),
            ),
        ]),
      );
}

class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon(
      {required this.tooltip, required this.selected, required this.onTap, required this.child});

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: selected,
          label: tooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(Lb.rControl),
            onTap: onTap,
            child: AnimatedContainer(
              duration: Lb.fast,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: selected ? Lb.raised : null,
                borderRadius: BorderRadius.circular(Lb.rControl),
                border: Border.all(color: selected ? Lb.line : Colors.transparent),
              ),
              child: IconTheme(
                data: IconThemeData(color: selected ? Lb.text : Lb.text3),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      );
}

class _EraserIcon extends StatelessWidget {
  const _EraserIcon();

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size.square(22),
        painter: _EraserPainter(IconTheme.of(context).color ?? Lb.text),
      );
}

class _EraserPainter extends CustomPainter {
  _EraserPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas
      ..save()
      ..translate(s / 2, s / 2)
      ..rotate(-0.785);
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: s * 0.82, height: s * 0.42),
        const Radius.circular(Lb.rTile));
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09;
    canvas.drawRRect(body, stroke);
    canvas.drawRect(
        Rect.fromLTRB(-s * 0.41, -s * 0.21, -s * 0.08, s * 0.21), Paint()..color = color);
    canvas.restore();
    canvas.drawLine(Offset(s * 0.45, s * 0.92), Offset(s * 0.95, s * 0.92), stroke);
  }

  @override
  bool shouldRepaint(_EraserPainter old) => old.color != color;
}

/// Current colour (opens the HSV picker), recently used colours, presets.
class ColorStrip extends StatelessWidget {
  const ColorStrip({super.key, required this.model, required this.onOpenPicker});

  final EditorModel model;
  final VoidCallback onOpenPicker;

  @override
  Widget build(BuildContext context) {
    final current = model.color;
    final erasing = model.tool == EditorTool.eraser;
    Widget swatch(int c) => _Swatch(
          color: c,
          selected: !erasing && c == current,
          onTap: () => model.color = c,
        );
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Tooltip(
            message: 'Colour picker',
            child: GestureDetector(
              onTap: onOpenPicker,
              child: Container(
                width: 52,
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                decoration: BoxDecoration(
                  color: Color(0xFF000000 | current),
                  borderRadius: BorderRadius.circular(Lb.rControl),
                  border: Border.all(color: Lb.text, width: 1.5),
                ),
                child: Icon(Icons.palette_sharp,
                    size: 20,
                    color: _luma(current) > 140 ? Colors.black87 : Colors.white),
              ),
            ),
          ),
          for (final c in model.recent) swatch(c),
          if (model.recent.isNotEmpty)
            const VerticalDivider(width: 16, indent: 12, endIndent: 12, color: Lb.line),
          for (final c in presetColors)
            if (!model.recent.contains(c)) swatch(c),
        ],
      ),
    );
  }

  static int _luma(int c) =>
      (((c >> 16) & 0xFF) * 299 + ((c >> 8) & 0xFF) * 587 + (c & 0xFF) * 114) ~/ 1000;
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Lb.fast,
          width: 30,
          margin: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
          decoration: BoxDecoration(
            color: Color(0xFF000000 | color),
            borderRadius: BorderRadius.circular(Lb.rTile),
            border: Border.all(
              color: selected ? Lb.text : Lb.line,
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
      );
}

/// Frame strip with playback, FPS, onion skin and frame operations.
class FrameTimeline extends StatefulWidget {
  const FrameTimeline({
    super.key,
    required this.model,
    required this.playing,
    required this.onPlay,
    required this.onFps,
    required this.onSelect,
  });

  final EditorModel model;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onFps;
  final ValueChanged<int> onSelect;

  @override
  State<FrameTimeline> createState() => _FrameTimelineState();
}

class _FrameTimelineState extends State<FrameTimeline> {
  static const _thumb = 56.0;
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FrameTimeline old) {
    super.didUpdateWidget(old);
    final m = widget.model;
    if (m.frameCount != _lastCount) {
      _lastCount = m.frameCount;
      // Keep a newly added frame in view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final target = (m.index * (_thumb + 6) - 80).clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });
    }
  }

  void _frameMenu(BuildContext context) {
    final m = widget.model;
    showStudioActions(context, header: MonoLabel('Frame ${m.index + 1} of ${m.frameCount}'), actions: [
      StudioAction(Icons.content_copy_sharp, 'Duplicate frame', m.duplicateFrame),
      StudioAction(Icons.add_box_sharp, 'Insert blank frame after', m.addFrame),
      StudioAction(Icons.layers_clear_sharp, 'Clear frame', m.clearFrame),
      StudioAction(Icons.delete_sharp, m.frameCount > 1 ? 'Delete frame' : 'Delete frame (clears it)',
          m.deleteFrame,
          danger: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final accent = readAccent(context);
    return Container(
      decoration: const BoxDecoration(
        color: Lb.panel,
        border: Border(top: Lb.hairline),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          MonoLabel('Frame ${m.index + 1} / ${m.frameCount}'),
          const Spacer(),
          IconButton(
            tooltip: 'Onion skin',
            style: studioIconStyle,
            isSelected: m.onion,
            visualDensity: VisualDensity.compact,
            onPressed: () => m.onion = !m.onion,
            icon: const Icon(Icons.layers_sharp, color: Lb.text3),
            selectedIcon: Icon(Icons.layers_sharp, color: readAccent(context)),
          ),
          TextButton(
            onPressed: widget.onFps,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, shape: studioShape),
            child: Text('${m.fps} fps', style: LbType.mono.copyWith(color: Lb.text)),
          ),
          IconButton.filled(
            tooltip: widget.playing ? 'Pause' : 'Play',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(backgroundColor: Lb.text, foregroundColor: Lb.ink, shape: studioShape),
            onPressed: widget.onPlay,
            icon: Icon(widget.playing ? Icons.pause_sharp : Icons.play_arrow_sharp),
          ),
        ]),
        SizedBox(
          height: _thumb + 4,
          child: Row(children: [
            Expanded(
              child: ReorderableListView.builder(
                scrollController: _scroll,
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                itemCount: m.frameCount,
                onReorderItem: (from, to) => m.moveFrame(from, to),
                proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                itemBuilder: (context, i) {
                  final f = m.frames[i];
                  final selected = i == m.index && !widget.playing;
                  return ReorderableDelayedDragStartListener(
                    key: ObjectKey(f),
                    index: i,
                    child: GestureDetector(
                      onTap: () => i == m.index && !widget.playing
                          ? _frameMenu(context)
                          : widget.onSelect(i),
                      child: Container(
                        width: _thumb,
                        margin: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Lb.ink,
                          borderRadius: BorderRadius.circular(Lb.rTile),
                          border: Border.all(
                            color: selected ? accent : Lb.line,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Center(child: FrameThumb(frame: f, repaint: m.pixels)),
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Duplicate frame',
              style: studioIconStyle,
              onPressed: m.duplicateFrame,
              icon: const Icon(Icons.content_copy_sharp, size: 20),
            ),
            IconButton.outlined(
              tooltip: 'Add frame',
              style: IconButton.styleFrom(side: Lb.hairline, shape: studioShape),
              onPressed: m.addFrame,
              icon: const Icon(Icons.add_sharp),
            ),
          ]),
        ),
      ]),
    );
  }
}
