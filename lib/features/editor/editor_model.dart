import 'package:flutter/foundation.dart';

import '../../engine/clip.dart';
import '../../engine/frame.dart';
import 'pixel_ops.dart';

enum EditorTool { pencil, eraser, fill, picker, line, rect, move }

/// LED-friendly presets: saturated hues read well on diffused LEDs, pastel
/// and dark tones mostly don't.
const presetColors = <int>[
  0xFF0000, 0xFF4000, 0xFF9000, 0xFFD000, 0xFFFF00, 0x80FF00, 0x00FF00, 0x00FF80,
  0x00FFFF, 0x0090FF, 0x0020FF, 0x6000FF, 0xB000FF, 0xFF00FF, 0xFF0080, 0xFF6080,
  0xFFFFFF, 0xFFC880, 0x808080, 0x303030,
];

class _Snapshot {
  _Snapshot(List<Frame> frames, List<int> delays, this.index)
      : frames = [for (final f in frames) f.copy()],
        delays = List.of(delays);

  final List<Frame> frames;
  final List<int> delays;
  final int index;

  int get bytes => frames.fold(0, (n, f) => n + f.rgb.length);
}

/// Document + tool state for the pixel editor. Widgets drive it through
/// [strokeStart]/[strokeMove]/[strokeEnd] in cell coordinates; every stroke
/// or frame operation is one undo step.
class EditorModel extends ChangeNotifier {
  EditorModel({required this.width, required this.height, List<Frame>? frames, int fps = 8})
      : _frames = frames == null || frames.isEmpty
            ? [Frame(width, height)]
            : [for (final f in frames) f.copy()],
        _delays = List.filled(frames == null || frames.isEmpty ? 1 : frames.length,
            (1000 / fps.clamp(minFps, maxFps)).round(), growable: true) {
    _keepSavePoint();
  }

  /// Restores a saved drawing, preserving its timing. The legacy [fps] meta
  /// is accepted for older callers; the clip's delays are authoritative.
  factory EditorModel.fromClip(FrameClip clip, {int? fps}) {
    final model = EditorModel(width: clip.width, height: clip.height, frames: clip.frames);
    model._delays = [for (final ms in clip.delaysMs) ms.clamp(20, 10000)];
    model._keepSavePoint();
    return model;
  }

  static const minFps = 1, maxFps = 30, maxHistory = 60, maxRecent = 10;

  static const maxHistoryBytes = 64 * 1024 * 1024;

  final int width;
  final int height;

  List<Frame> _frames;
  int _index = 0;
  List<int> _delays;
  EditorTool _tool = EditorTool.pencil;
  EditorTool _beforePicker = EditorTool.pencil;
  int _color = 0xFF0040;
  bool _mirrorX = false, _mirrorY = false, _onion = false;
  final List<int> _recent = [];
  bool _dirty = false;

  // What was last saved (or loaded), so undoing back to it isn't "unsaved".
  List<Frame> _saved = const [];
  List<int> _savedDelays = const [];

  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];

  /// Bumps on every pixel change (including mid-stroke), so painters and the
  /// live mirror can react without the rest of the UI rebuilding.
  final pixels = ValueNotifier<int>(0);

  _Snapshot? _pending;
  Frame? _base;
  (int, int)? _start, _last;
  bool _usedColor = false;

  List<Frame> get frames => List.unmodifiable(_frames);
  int get frameCount => _frames.length;
  List<int> get delaysMs => List.unmodifiable(_delays);
  int get index => _index;
  Frame get frame => _frames[_index];
  Frame? get previous => _index > 0 ? _frames[_index - 1] : null;
  int get fps => (1000 / (_delays.fold(0, (a, b) => a + b) / _delays.length))
      .round().clamp(minFps, maxFps);

  EditorTool get tool => _tool;
  int get color => _color;
  bool get mirrorX => _mirrorX;
  bool get mirrorY => _mirrorY;
  bool get onion => _onion;
  List<int> get recent => List.unmodifiable(_recent);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isDirty => _dirty;
  bool get inStroke => _pending != null;

  @visibleForTesting
  int get historyBytes => [..._undo, ..._redo, ?_pending].fold(0, (n, s) => n + s.bytes);

  set tool(EditorTool t) {
    if (t == _tool) return;
    if (t == EditorTool.picker) _beforePicker = _tool;
    _tool = t;
    notifyListeners();
  }

  set color(int c) {
    _color = c & 0xFFFFFF;
    if (_tool == EditorTool.eraser || _tool == EditorTool.picker) _tool = EditorTool.pencil;
    notifyListeners();
  }

  set mirrorX(bool v) => _set(() => _mirrorX = v);
  set mirrorY(bool v) => _set(() => _mirrorY = v);
  set onion(bool v) => _set(() => _onion = v);

  set fps(int v) {
    final c = v.clamp(minFps, maxFps);
    final average = _delays.fold(0, (a, b) => a + b) / _delays.length;
    final factor = 1000 / c / average;
    final delays = [for (final ms in _delays) (ms * factor).round().clamp(20, 10000)];
    if (listEquals(delays, _delays)) return;
    _delays = delays;
    _dirty = !_atSavePoint();
    notifyListeners();
  }

  void _set(void Function() f) {
    f();
    notifyListeners();
  }

  /// Puts [c] at the front of the recent strip.
  void remember(int c) {
    _recent
      ..remove(c)
      ..insert(0, c);
    if (_recent.length > maxRecent) _recent.removeLast();
  }

  void markSaved() {
    _dirty = false;
    _keepSavePoint();
    notifyListeners();
  }

  void _keepSavePoint() {
    _saved = [for (final f in _frames) f.copy()];
    _savedDelays = List.of(_delays);
  }

  bool _atSavePoint() {
    if (!listEquals(_delays, _savedDelays) || _frames.length != _saved.length) return false;
    for (var i = 0; i < _frames.length; i++) {
      final a = _frames[i].rgb, b = _saved[i].rgb;
      for (var k = 0; k < a.length; k++) {
        if (a[k] != b[k]) return false;
      }
    }
    return true;
  }

  // Strokes ------------------------------------------------------------------

  void strokeStart(int x, int y) {
    if (_pending != null) strokeEnd();
    final inside = x >= 0 && y >= 0 && x < width && y < height;
    switch (_tool) {
      case EditorTool.picker:
        if (!inside) return;
        _color = frame.get(x, y);
        if (_color != 0) remember(_color);
        _tool = _beforePicker == EditorTool.picker ? EditorTool.pencil : _beforePicker;
        notifyListeners();
        return;
      case EditorTool.fill:
        if (!inside) return;
        _pending = _Snapshot(_frames, _delays, _index);
        _trimHistory();
        for (final (mx, my) in mirrored(x, y, width, height, mx: _mirrorX, my: _mirrorY)) {
          floodFill(frame, mx, my, _color);
        }
        _usedColor = true;
        _pixelsChanged();
        strokeEnd();
        return;
      default:
        _pending = _Snapshot(_frames, _delays, _index);
        _trimHistory();
        _base = frame.copy();
        _start = _last = (x, y);
        _usedColor = _tool != EditorTool.eraser && _tool != EditorTool.move;
        _apply(x, y);
    }
  }

  void strokeMove(int x, int y) {
    if (_pending == null || _last == (x, y)) return;
    _apply(x, y);
  }

  void strokeEnd() {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    _base = null;
    _start = _last = null;
    if (!sameFrame(p.frames[p.index], frame)) {
      _push(p);
      if (_usedColor && _color != 0) remember(_color);
    }
    notifyListeners();
  }

  /// Abandons the stroke in progress, e.g. when a second finger turns the
  /// gesture into a pinch.
  void strokeCancel() {
    final p = _pending;
    if (p == null) return;
    frame.rgb.setAll(0, p.frames[p.index].rgb);
    _pending = null;
    _base = null;
    _start = _last = null;
    _pixelsChanged();
    notifyListeners();
  }

  void _apply(int x, int y) {
    final f = frame;
    final (sx, sy) = _start!;
    switch (_tool) {
      case EditorTool.pencil:
      case EditorTool.eraser:
        final (lx, ly) = _last!;
        final c = _tool == EditorTool.eraser ? 0 : _color;
        for (final (px, py) in linePoints(lx, ly, x, y)) {
          _plot(f, px, py, c);
        }
      case EditorTool.line:
      case EditorTool.rect:
        f.rgb.setAll(0, _base!.rgb);
        final pts = _tool == EditorTool.line ? linePoints(sx, sy, x, y) : rectPoints(sx, sy, x, y);
        for (final (px, py) in pts) {
          _plot(f, px, py, _color);
        }
      case EditorTool.move:
        f.rgb.setAll(0, shifted(_base!, x - sx, y - sy).rgb);
      case EditorTool.fill:
      case EditorTool.picker:
        break;
    }
    _last = (x, y);
    _pixelsChanged();
  }

  void _plot(Frame f, int x, int y, int c) {
    for (final (mx, my) in mirrored(x, y, width, height, mx: _mirrorX, my: _mirrorY)) {
      f.set(mx, my, c);
    }
  }

  // Frames -------------------------------------------------------------------

  void selectFrame(int i) {
    if (i == _index || i < 0 || i >= _frames.length) return;
    strokeEnd();
    _index = i;
    _pixelsChanged();
    notifyListeners();
  }

  void addFrame() => _edit(() {
        _delays.insert(_index + 1, _delays[_index]);
        _frames.insert(_index + 1, Frame(width, height));
        _index++;
      });

  void duplicateFrame() => _edit(() {
        _delays.insert(_index + 1, _delays[_index]);
        _frames.insert(_index + 1, frame.copy());
        _index++;
      });

  /// Deletes the current frame; the last remaining frame is cleared instead.
  void deleteFrame() => _edit(() {
        if (_frames.length == 1) {
          _frames[0] = Frame(width, height);
          return;
        }
        _delays.removeAt(_index);
        _frames.removeAt(_index);
        if (_index >= _frames.length) _index = _frames.length - 1;
      });

  /// Moves the frame at [from] so it ends up at index [to].
  void moveFrame(int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= _frames.length || to >= _frames.length) {
      return;
    }
    _edit(() {
      final f = _frames.removeAt(from);
      _frames.insert(to, f);
      _delays.insert(to, _delays.removeAt(from));
      _index = to;
    });
  }

  void clearFrame() {
    if (frame.rgb.every((b) => b == 0)) return;
    _edit(() => _frames[_index] = Frame(width, height));
  }

  void _edit(void Function() f) {
    strokeEnd();
    final snap = _Snapshot(_frames, _delays, _index);
    f();
    _push(snap);
    _pixelsChanged();
    notifyListeners();
  }

  // History ------------------------------------------------------------------

  void _push(_Snapshot s) {
    _undo.add(s);
    if (_undo.length > maxHistory) _undo.removeAt(0);
    _redo.clear();
    _trimHistory();
    _dirty = true;
  }

  void _trimHistory() {
    while (_undo.length > 1 && historyBytes > maxHistoryBytes) {
      _undo.removeAt(0);
    }
    // Undo can move the whole history to redo; pending strokes count too.
    while (_redo.isNotEmpty && historyBytes > maxHistoryBytes &&
        (_redo.length > 1 || _undo.isNotEmpty || _pending != null)) {
      _redo.removeAt(0);
    }
  }

  void undo() => _travel(_undo, _redo);
  void redo() => _travel(_redo, _undo);

  void _travel(List<_Snapshot> from, List<_Snapshot> to) {
    strokeEnd();
    if (from.isEmpty) return;
    to.add(_Snapshot(_frames, _delays, _index));
    final s = from.removeLast();
    _frames = s.frames;
    _delays = s.delays;
    _trimHistory();
    _index = s.index.clamp(0, _frames.length - 1);
    _dirty = !_atSavePoint();
    _pixelsChanged();
    notifyListeners();
  }

  void _pixelsChanged() => pixels.value++;

  // Serialisation ------------------------------------------------------------

  FrameClip toClip() => FrameClip(width: width, height: height,
      frames: [for (final f in _frames) f.copy()], delaysMs: List.of(_delays));

  Map<String, dynamic> get meta => {'fps': fps, 'v': 2};

  @override
  void dispose() {
    pixels.dispose();
    super.dispose();
  }
}
