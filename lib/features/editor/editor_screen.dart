import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/creations.dart';
import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../../ui/actions.dart';
import '../../ui/scope.dart';
import '../../ui/theme.dart';
import 'color_picker.dart';
import 'editor_canvas.dart';
import 'editor_model.dart';
import 'editor_panels.dart';
import 'live_mirror.dart';
import 'start_view.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.initial});

  /// A saved creation of kind 'drawing' to keep editing.
  final Creation? initial;

  @override
  State<EditorScreen> createState() => EditorScreenState();
}

class EditorScreenState extends State<EditorScreen> {
  EditorModel? _model;
  String? _id, _title;
  bool _led = true;
  bool _mirror = false;
  bool _saving = false;
  LiveMirrorGenerator? _live;
  late AppScope _scope;

  /// Index of the frame being previewed, or null while editing.
  final _preview = ValueNotifier<int?>(null);
  Timer? _player;

  @visibleForTesting
  EditorModel? get model => _model;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    if (c != null) {
      _model = EditorModel.fromClip(c.clip, fps: (c.meta['fps'] as num?)?.toInt());
      _id = c.id;
      _title = c.title;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = AppScope.of(context);
  }

  @override
  void dispose() {
    _player?.cancel();
    _handOffPlayback();
    _preview.dispose();
    _model?.dispose();
    super.dispose();
  }

  /// The live generator reads this screen's state, so once we're gone the
  /// player gets a plain clip of the drawing instead (it keeps showing on the
  /// matrix if the mirror was on).
  void _handOffPlayback() {
    final pb = _scope.playback, live = _live, m = _model;
    if (live == null || m == null || pb.generator != live) return;
    final clip = m.toClip(), title = _title ?? 'Drawing', wasPlaying = pb.isPlaying;
    // Deferred: notifying listeners while the tree is being torn down throws.
    scheduleMicrotask(() {
      if (pb.generator != live) return;
      pb.playGenerator(ClipGenerator(clip, title: title));
      if (!wasPlaying) pb.pause();
    });
  }

  void _start(EditorModel m) {
    _stopPreview();
    final old = _model;
    setState(() {
      _model = m;
      _id = null;
      _title = null;
    });
    // Disposed after the swap so the live mirror never reads a dead model.
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  // Preview -------------------------------------------------------------------

  bool get _playing => _player != null;

  void _togglePlay() => _playing ? _stopPreview() : _startPreview();

  void _startPreview() {
    final m = _model!;
    m.strokeEnd();
    _player?.cancel();
    _preview.value ??= m.index;
    _player = Timer.periodic(Duration(microseconds: 1000000 ~/ m.fps), (_) {
      _preview.value = ((_preview.value ?? 0) + 1) % m.frameCount;
    });
    setState(() {});
  }

  void _stopPreview() {
    if (_player == null) return;
    _player!.cancel();
    _player = null;
    _preview.value = null;
    if (mounted) setState(() {});
  }

  // Live mirror ---------------------------------------------------------------

  static final _blank = Frame(16, 16);

  Frame _liveFrame() {
    final m = _model;
    if (m == null) return _blank;
    final p = _preview.value;
    return p == null ? m.frame : m.frames[p.clamp(0, m.frameCount - 1)];
  }

  bool get _mirroring => _mirror && _live != null && _scope.playback.generator == _live;

  Future<void> _toggleMirror() async {
    if (_mirroring) {
      setState(() => _mirror = false);
      await GlyphActions.stopStreaming(context);
      _scope.playback.pause();
      return;
    }
    if (!_scope.devices.isConnected) {
      _toast('Connect a matrix in the Matrix tab to mirror your drawing.');
      return;
    }
    final live = _live ??= LiveMirrorGenerator(
      source: _liveFrame,
      revision: () => (_model?.pixels.value ?? 0) * 31 + (_preview.value ?? -1),
      title: _title ?? 'Drawing',
    );
    _scope.playback.playGenerator(live);
    setState(() => _mirror = true);
    await GlyphActions.ensureStreaming(context);
  }

  // Saving --------------------------------------------------------------------

  Future<String?> _askTitle({String? initial}) async {
    final c = TextEditingController(text: initial ?? '');
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? 'Name your drawing' : 'Rename'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'My drawing'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (t == null) return null;
    final trimmed = t.trim();
    return trimmed.isEmpty ? 'My drawing' : trimmed;
  }

  Future<bool> _save() async {
    final m = _model!;
    final title = _title ?? await _askTitle();
    if (title == null || !mounted) return false;
    final saved = await _scope.creations
        .save(id: _id, title: title, kind: 'drawing', clip: m.toClip(), meta: m.meta);
    _id = saved.id;
    _title = title;
    m.markSaved();
    if (mounted) {
      setState(() {});
      _toast('Saved to My Creations');
    }
    return true;
  }

  Future<void> _rename() async {
    final t = await _askTitle(initial: _title ?? '');
    if (t == null || !mounted) return;
    setState(() => _title = t);
    if (_id != null) await _save();
  }

  Future<void> _saveToMatrix() async {
    final caps = _scope.devices.caps;
    if (caps == null) {
      _toast('Connect a matrix in the Matrix tab first.');
      return;
    }
    final title = _title ?? await _askTitle();
    if (title == null || !mounted) return;
    setState(() {
      _title = title;
      _saving = true;
    });
    final wasMirroring = _mirroring;
    await GlyphActions.saveClipToDevice(context, _model!.toClip(), title);
    if (!mounted) return;
    // Uploading ends the stream and the matrix now plays the saved preset.
    if (wasMirroring && !_scope.playback.isStreaming) {
      _mirror = false;
      _scope.playback.pause();
    }
    setState(() => _saving = false);
  }

  Future<void> _newDrawing() async {
    if (_model?.isDirty ?? false) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a new drawing?'),
          content: const Text('Unsaved changes to this one will be lost.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
          ],
        ),
      );
      if (ok != true) return;
    }
    _stopPreview();
    final old = _model;
    setState(() {
      _model = null;
      _id = null;
      _title = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  Future<void> _confirmLeave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save your drawing?'),
        content: const Text('You have unsaved changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'save' && !await _save()) return;
    _model?.markSaved();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickFps() async {
    final m = _model!;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ListenableBuilder(
            listenable: m,
            builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${m.fps} frames per second',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Slider(
                value: m.fps.toDouble(),
                min: EditorModel.minFps.toDouble(),
                max: EditorModel.maxFps.toDouble(),
                divisions: EditorModel.maxFps - EditorModel.minFps,
                label: '${m.fps}',
                onChanged: (v) {
                  m.fps = v.round();
                  if (_playing) _startPreview();
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker() async {
    final m = _model!;
    final c = await showColorPickerSheet(context, initial: m.color, onChanged: (c) => m.color = c);
    if (c != 0) m.remember(c);
    m.color = c;
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  // Build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final m = _model;
    if (m == null) {
      final caps = _scope.devices.caps;
      return Scaffold(
        appBar: AppBar(title: const Text('Pixel editor')),
        body: SafeArea(
          top: false,
          child: EditorStartView(
            deviceSize: caps != null && caps.is2D && caps.width <= 128 && caps.height <= 128
                ? (caps.width, caps.height)
                : null,
            onStart: _start,
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) => PopScope(
        canPop: !m.isDirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: GestureDetector(
              onTap: _rename,
              child: Text(_title ?? 'Untitled',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            actions: [
              IconButton(
                  tooltip: 'Undo', onPressed: m.canUndo ? m.undo : null, icon: const Icon(Icons.undo)),
              IconButton(
                  tooltip: 'Redo', onPressed: m.canRedo ? m.redo : null, icon: const Icon(Icons.redo)),
              IconButton(
                tooltip: 'Save',
                onPressed: _save,
                icon: Icon(m.isDirty || _id == null ? Icons.save_outlined : Icons.check_circle_outline),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  switch (v) {
                    case 'matrix':
                      _saveToMatrix();
                    case 'rename':
                      _rename();
                    case 'clear':
                      m.clearFrame();
                    case 'new':
                      _newDrawing();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'matrix',
                    enabled: !_saving,
                    child: const ListTile(
                        leading: Icon(Icons.download_for_offline_outlined),
                        title: Text('Save to matrix')),
                  ),
                  const PopupMenuItem(
                      value: 'rename',
                      child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename'))),
                  const PopupMenuItem(
                      value: 'clear',
                      child: ListTile(
                          leading: Icon(Icons.layers_clear_outlined), title: Text('Clear frame'))),
                  const PopupMenuItem(
                      value: 'new',
                      child: ListTile(leading: Icon(Icons.note_add_outlined), title: Text('New drawing'))),
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(children: [
              _CanvasHeader(
                model: m,
                led: _led,
                saving: _saving,
                onLed: () => setState(() => _led = !_led),
                mirror: ListenableBuilder(
                  listenable: Listenable.merge([_scope.playback, _scope.devices]),
                  builder: (context, _) => _MirrorPill(
                    on: _mirroring,
                    streaming: _scope.playback.isStreaming,
                    onTap: _toggleMirror,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: EditorCanvas(
                    model: m,
                    preview: _preview,
                    led: _led,
                    onTouch: _stopPreview,
                  ),
                ),
              ),
              EditorToolBar(model: m),
              ColorStrip(model: m, onOpenPicker: _openPicker),
              FrameTimeline(
                model: m,
                playing: _playing,
                onPlay: _togglePlay,
                onFps: _pickFps,
                onSelect: (i) {
                  _stopPreview();
                  m.selectFrame(i);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CanvasHeader extends StatelessWidget {
  const _CanvasHeader({
    required this.model,
    required this.led,
    required this.saving,
    required this.onLed,
    required this.mirror,
  });

  final EditorModel model;
  final bool led, saving;
  final VoidCallback onLed;
  final Widget mirror;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
        child: Row(children: [
          Flexible(child: mirror),
          if (saving)
            const Padding(
              padding: EdgeInsets.only(left: 10),
              child: SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          const Spacer(),
          Text('${model.width}×${model.height}',
              style: const TextStyle(fontSize: 12, color: GlyphColors.textMuted)),
          IconButton(
            tooltip: 'Mirror left/right',
            isSelected: model.mirrorX,
            visualDensity: VisualDensity.compact,
            onPressed: () => model.mirrorX = !model.mirrorX,
            icon: const Icon(Icons.flip),
            selectedIcon: const Icon(Icons.flip, color: GlyphColors.accent),
          ),
          IconButton(
            tooltip: 'Mirror top/bottom',
            isSelected: model.mirrorY,
            visualDensity: VisualDensity.compact,
            onPressed: () => model.mirrorY = !model.mirrorY,
            icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
            selectedIcon: const RotatedBox(
                quarterTurns: 1, child: Icon(Icons.flip, color: GlyphColors.accent)),
          ),
          IconButton(
            tooltip: led ? 'Square pixels' : 'LED dots',
            visualDensity: VisualDensity.compact,
            onPressed: onLed,
            icon: Icon(led ? Icons.grid_on : Icons.blur_on),
          ),
        ]),
      );
}

class _MirrorPill extends StatelessWidget {
  const _MirrorPill({required this.on, required this.streaming, required this.onTap});

  final bool on, streaming;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = on && streaming;
    final color = live ? GlyphColors.danger : (on ? GlyphColors.warning : GlyphColors.textMuted);
    return Tooltip(
      message: on ? 'Stop mirroring' : 'Show this drawing on the matrix as you draw',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: on ? color.withValues(alpha: 0.15) : null,
            border: Border.all(color: on ? color : GlyphColors.outline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.cast_connected : Icons.cast, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                live ? 'LIVE' : (on ? 'Connecting…' : 'Live mirror'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? color : GlyphColors.text),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
