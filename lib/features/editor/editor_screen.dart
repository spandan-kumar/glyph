import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/creations.dart';
import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../../ui/actions.dart';
import '../../ui/design/parts.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/studio_kit.dart';
import '../../ui/make/tool_session.dart';
import '../../ui/scope.dart';
import 'color_picker.dart';
import 'editor_canvas.dart';
import 'editor_model.dart';
import 'editor_panels.dart';
import 'live_mirror.dart';
import 'start_view.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.initial, this.blank = false});

  /// A saved creation of kind 'drawing' to keep editing.
  final Creation? initial;

  /// Skip the size/template picker and open a blank canvas at the matrix's
  /// size, so the first stroke lands on the matrix right away. Sizes and
  /// examples stay one tap away under "New drawing".
  final bool blank;

  @override
  State<EditorScreen> createState() => EditorScreenState();
}

class EditorScreenState extends State<EditorScreen> with ToolSession<EditorScreen> {
  EditorModel? _model;
  String? _id, _title;
  bool _led = true;
  bool _mirror = false;

  /// The person turned the live mirror off; don't switch it back on by
  /// itself.
  bool _mirrorOptOut = false;
  bool _saving = false;
  LiveMirrorGenerator? _live;
  late AppScope _scope;
  bool _listening = false;

  /// Index of the frame being previewed, or null while editing.
  final _preview = ValueNotifier<int?>(null);
  Timer? _player;

  @visibleForTesting
  EditorModel? get model => _model;

  /// Whether the drawing is currently being mirrored to the matrix.
  @visibleForTesting
  bool get mirroring => _mirroring;

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
    if (widget.blank && widget.initial == null && _model == null && !_listening) {
      final caps = _scope.devices.caps;
      final fits = caps != null && caps.is2D && caps.width <= 128 && caps.height <= 128;
      _model = EditorModel(width: fits ? caps.width : 16, height: fits ? caps.height : 16);
    }
    if (!_listening) {
      _listening = true;
      _scope.devices.addListener(_onDevices);
      _scheduleAutoMirror();
    }
  }

  @override
  void dispose() {
    if (_listening) _scope.devices.removeListener(_onDevices);
    _player?.cancel();
    _keepSentDrawing();
    _preview.dispose();
    _model?.dispose();
    super.dispose();
  }

  /// Leaving stops an unsent drawing (see [ToolSession]). A sent one stays
  /// on the phone as what the matrix now plays, but the live generator reads
  /// this screen's state, so it becomes a plain clip of the drawing.
  void _keepSentDrawing() {
    final pb = _scope.playback, live = _live, m = _model;
    if (!sentFromTool || live == null || m == null || pb.generator != live) return;
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
    _scheduleAutoMirror();
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

  // Live mirror (AHA #6 "Draw live") -----------------------------------------

  static final _blank = Frame(16, 16);

  Frame _liveFrame() {
    final m = _model;
    if (m == null) return _blank;
    final p = _preview.value;
    return p == null ? m.frame : m.frames[p.clamp(0, m.frameCount - 1)];
  }

  bool get _mirroring => _mirror && _live != null && _scope.playback.generator == _live;

  void _onDevices() => _scheduleAutoMirror();

  /// With a matrix connected, the drawing shows on it from the first stroke.
  void _scheduleAutoMirror() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _model == null || _mirrorOptOut || _mirroring) return;
      if (_scope.devices.isConnected) _startMirror();
    });
  }

  Future<void> _startMirror() async {
    if (!_scope.devices.isConnected) return _connect();
    final live = _live ??= LiveMirrorGenerator(
      source: _liveFrame,
      revision: () => (_model?.pixels.value ?? 0) * 31 + (_preview.value ?? -1),
      title: _title ?? 'Drawing',
    );
    _scope.playback.playGenerator(live);
    toolPlays(live);
    setState(() => _mirror = true);
    await GlyphActions.ensureStreaming(context);
  }

  Future<void> _stopMirror() async {
    setState(() {
      _mirror = false;
      _mirrorOptOut = true;
    });
    await GlyphActions.stopStreaming(context);
    _scope.playback.pause();
  }

  /// Not connected: go to the Device tab (saving first if needed).
  Future<void> _connect() async {
    if ((_model?.isDirty ?? false) && !await _confirmLeave(pop: false)) return;
    if (mounted) goToMatrix(context);
  }

  // Saving --------------------------------------------------------------------

  Future<String?> _askTitle({String? initial}) async {
    final t = await showDialog<String>(
      context: context,
      builder: (_) => _TitleDialog(initial: initial),
    );
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
      studioToast(context, 'Saved to Made by you');
    }
    return true;
  }

  Future<void> _rename() async {
    final t = await _askTitle(initial: _title ?? '');
    if (t == null || !mounted) return;
    setState(() => _title = t);
    if (_id != null) await _save();
  }

  Future<void> _keepOnMatrix() async {
    final caps = _scope.devices.caps;
    if (caps == null) {
      studioToast(context, 'Connect a device to send this to it.',
          action: SnackBarAction(label: 'Connect', onPressed: _connect));
      return;
    }
    final title = _title ?? await _askTitle();
    if (title == null || !mounted) return;
    setState(() {
      _title = title;
      _saving = true;
    });
    final wasMirroring = _mirroring;
    await sendClipFromTool(_model!.toClip(), title);
    if (!mounted) return;
    // Uploading ends the stream and the matrix now plays the kept drawing.
    if (wasMirroring && !_scope.playback.isStreaming) {
      _mirror = false;
      _mirrorOptOut = true;
      _scope.playback.pause();
    }
    setState(() => _saving = false);
  }

  Future<void> _newDrawing() async {
    if (_model?.isDirty ?? false) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Start a new drawing?', style: LbType.title),
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

  /// Offers to save unsaved changes. Returns whether it's fine to leave;
  /// pops the screen when [pop].
  Future<bool> _confirmLeave({bool pop = true}) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Save your drawing?', style: LbType.title),
        content: const Text('You have unsaved changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (!mounted || choice == null) return false;
    if (choice == 'save' && !await _save()) return false;
    _model?.markSaved();
    if (pop && mounted) Navigator.of(context).pop();
    return true;
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
              const MonoLabel('Speed'),
              const SizedBox(height: 6),
              Text('${m.fps} frames a second', style: LbType.title),
              const SizedBox(height: 8),
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

  // Build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final m = _model;
    if (m == null) {
      final caps = _scope.devices.caps;
      return StudioScaffold(
        title: 'Draw',
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
        child: StudioScaffold(
          titleSpacing: 0,
          titleWidget: GestureDetector(
            onTap: _rename,
            child: Text(_title ?? 'Untitled', overflow: TextOverflow.ellipsis, style: LbType.heading),
          ),
          actions: [
            IconButton(
                style: studioIconStyle,
                tooltip: 'Undo', onPressed: m.canUndo ? m.undo : null, icon: const Icon(Icons.undo)),
            IconButton(
                style: studioIconStyle,
                tooltip: 'Redo', onPressed: m.canRedo ? m.redo : null, icon: const Icon(Icons.redo)),
            IconButton(
              style: studioIconStyle,
              tooltip: 'Save',
              onPressed: _save,
              icon: Icon(m.isDirty || _id == null ? Icons.save_outlined : Icons.check_circle_outline),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              shape: studioMenuShape,
              style: studioIconStyle,
              onSelected: (v) {
                switch (v) {
                  case 'matrix':
                    _keepOnMatrix();
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
                      leading: Icon(Icons.push_pin_outlined), title: Text('Send to device')),
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
          body: SafeArea(
            top: false,
            child: Column(children: [
              _CanvasHeader(
                model: m,
                led: _led,
                saving: _saving,
                onLed: () => setState(() => _led = !_led),
                live: ListenableBuilder(
                  listenable: Listenable.merge([_scope.playback, _scope.devices]),
                  builder: (context, _) => _LiveIndicator(
                    connected: _scope.devices.isConnected,
                    mirroring: _mirroring,
                    streaming: _scope.playback.isStreaming,
                    onStart: () {
                      _mirrorOptOut = false;
                      _startMirror();
                    },
                    onStop: _stopMirror,
                    onConnect: _connect,
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
    required this.live,
  });

  final EditorModel model;
  final bool led, saving;
  final VoidCallback onLed;
  final Widget live;

  @override
  Widget build(BuildContext context) {
    final accent = readAccent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      child: Row(children: [
        Expanded(child: Align(alignment: Alignment.centerLeft, child: live)),
        if (saving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        Text('${model.width}×${model.height}', style: LbType.mono),
        IconButton(
          tooltip: 'Mirror left/right',
          style: studioIconStyle,
          isSelected: model.mirrorX,
          visualDensity: VisualDensity.compact,
          onPressed: () => model.mirrorX = !model.mirrorX,
          icon: const Icon(Icons.flip, color: Lb.text3),
          selectedIcon: Icon(Icons.flip, color: accent),
        ),
        IconButton(
          tooltip: 'Mirror top/bottom',
          style: studioIconStyle,
          isSelected: model.mirrorY,
          visualDensity: VisualDensity.compact,
          onPressed: () => model.mirrorY = !model.mirrorY,
          icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip, color: Lb.text3)),
          selectedIcon: RotatedBox(quarterTurns: 1, child: Icon(Icons.flip, color: accent)),
        ),
        IconButton(
          tooltip: led ? 'Square pixels' : 'LED dots',
          style: studioIconStyle,
          visualDensity: VisualDensity.compact,
          onPressed: onLed,
          icon: Icon(led ? Icons.grid_on : Icons.blur_on, color: Lb.text2),
        ),
      ]),
    );
  }
}

/// "On your device" while the drawing streams live; otherwise a quiet way
/// to turn it on, or to go and connect one.
class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({
    required this.connected,
    required this.mirroring,
    required this.streaming,
    required this.onStart,
    required this.onStop,
    required this.onConnect,
  });

  final bool connected, mirroring, streaming;
  final VoidCallback onStart, onStop, onConnect;

  @override
  Widget build(BuildContext context) {
    final (String tip, VoidCallback tap, Widget child) = !connected
        ? (
            'Connect a device',
            onConnect,
            const _Quiet(dot: false, label: 'No device connected'),
          )
        : mirroring
            ? (
                'Stop showing on your device',
                onStop,
                streaming
                    ? const LivePulse(label: 'On your device')
                    : const _Quiet(dot: true, label: 'Connecting…'),
              )
            : (
                'Show this drawing on your device as you draw',
                onStart,
                const _Quiet(dot: false, label: 'Show on device'),
              );
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(Lb.rControl),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: child,
        ),
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.dot, required this.label});

  final bool dot;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        StatusDot(on: dot, color: readAccent(context)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label.toUpperCase(),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.label),
        ),
      ]);
}

/// Names a drawing. Owns its text field's controller, so the controller
/// outlives the dialog's closing animation.
class _TitleDialog extends StatefulWidget {
  const _TitleDialog({this.initial});

  final String? initial;

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final _c = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initial == null ? 'Name your drawing' : 'Rename', style: LbType.title),
        content: TextField(
          controller: _c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'My drawing'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
        ],
      );
}
