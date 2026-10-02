import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/creations.dart';
import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../../ui/actions.dart';
import '../../ui/scope.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/led_matrix_view.dart';
import 'crop_editor.dart';
import 'decode.dart';
import 'processing.dart';
import 'sharing.dart';

/// Runs [callback] off the UI isolate. Swappable so tests can run inline.
typedef ImportRunner = Future<R> Function<Q, R>(ComputeCallback<Q, R> callback, Q message);

/// Create → Import: pick a GIF/image (or a `.glyph` file), crop and tune it
/// for the matrix, then play, save or upload it.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, this.initialSource, this.initialName});

  /// Opens the editor on an already-decoded source (tests, other features).
  @visibleForTesting
  final DecodedSource? initialSource;
  final String? initialName;

  @visibleForTesting
  static ImportRunner runner = compute;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

const _sizes = [(8, 8), (16, 16), (32, 8), (32, 16), (32, 32), (64, 32), (64, 64)];
const _colorSteps = [0, 128, 64, 32, 16, 8, 4, 2];
const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];

class _ImportScreenState extends State<ImportScreen> with SingleTickerProviderStateMixin {
  DecodedSource? _src;
  String _name = 'Import';
  String? _fileName;
  bool _loading = false;
  String? _error;
  ImportSettings _s = ImportSettings.ledDefaults;
  (int, int) _manualSize = (16, 16);

  // Background render + GIF estimate for the current settings.
  int _gen = 0;
  ImportOutput? _out;
  int _outGen = -1;
  (int, int)? _outSize;
  bool _jobRunning = false;
  Timer? _debounce;

  String? _savedId;
  bool _uploading = false;

  // Preview playback.
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _clockMs = 0;
  bool _playing = true;
  final _preview = ValueNotifier<Frame>(Frame(16, 16));
  Object? _shownKey;
  List<(int, int)>? _picks;
  int _picksGen = -1;

  ui.Image? _cropImage;
  Object? _cropKey;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    final src = widget.initialSource;
    if (src != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(src, widget.initialName ?? 'Import');
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _debounce?.cancel();
    _preview.dispose();
    _cropImage?.dispose();
    super.dispose();
  }

  (int, int) get _target {
    final caps = AppScope.of(context).devices.caps;
    return caps != null && caps.width > 0 && caps.height > 0
        ? (caps.width, caps.height)
        : _manualSize;
  }

  bool get _fresh => _out != null && _outGen == _gen && _outSize == _target;

  // ---------------------------------------------------------------------------
  // Loading

  Future<void> _pick({required bool anyFile}) async {
    final PlatformFile? f;
    try {
      f = await FilePicker.pickFile(
        type: anyFile ? FileType.any : FileType.image,
        // Transcodes HEIC to JPEG; GIFs come through as GIFs.
        darwinOptions: const DarwinOptions(
            assetRepresentationMode: DarwinAssetRepresentationMode.compatible),
      );
    } catch (e) {
      setState(() => _error = 'Couldn\'t open the file picker: $e');
      return;
    }
    if (f == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final len = f.lengthSync() ?? await f.length();
      if (len != null && len > ImportLimits.maxFileBytes) {
        throw const ImportException('That file is too big (max 40 MB).');
      }
      final bytes = await f.readAsBytes();
      final ext = f.extension?.toLowerCase();
      if (ext == glyphFileExtension || ext == 'json' || (bytes.isNotEmpty && bytes[0] == 0x7B)) {
        await _importGlyph(bytes);
        return;
      }
      final src = await ImportScreen.runner(decodeSourceMessage, bytes);
      if (!mounted) return;
      _fileName = f.name;
      _load(src, _stripExt(f.name));
    } catch (e) {
      if (mounted) setState(() => _error = e is ImportException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importGlyph(Uint8List bytes) async {
    final store = AppScope.of(context).creations;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final c = await importGlyphFile(store, bytes);
      messenger.showSnackBar(SnackBar(
          content: Text('Added “${c.title}” to My Creations'),
          behavior: SnackBarBehavior.floating));
      if (nav.canPop()) nav.pop();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static String _stripExt(String n) {
    final i = n.lastIndexOf('.');
    final base = i > 0 ? n.substring(0, i) : n;
    return base.isEmpty ? 'Import' : base;
  }

  void _load(DecodedSource src, String name) {
    final f = src.frames.first;
    setState(() {
      _src = src;
      _name = name;
      _error = null;
      _savedId = null;
      _out = null;
      _clockMs = 0;
      _playing = true;
      _s = ImportSettings.ledDefaults.copyWith(
          pixelArt: src.looksPixelArt, bgColor: (f[0] << 16) | (f[1] << 8) | f[2]);
      _gen++;
    });
    _scheduleJob(immediate: true);
    _refreshCropImage();
    _updatePreview();
    if (!_ticker.isActive) _ticker.start();
  }

  // ---------------------------------------------------------------------------
  // Settings + background work

  void _set(ImportSettings s) {
    final orientChanged = s.quarterTurns != _s.quarterTurns ||
        s.flipH != _s.flipH ||
        s.flipV != _s.flipV ||
        s.trimStart != _s.trimStart;
    setState(() {
      _s = s;
      _gen++;
    });
    if (orientChanged) _refreshCropImage();
    _scheduleJob();
    _updatePreview();
  }

  void _setSize((int, int) size) {
    setState(() {
      _manualSize = size;
      _gen++;
    });
    _scheduleJob();
    _updatePreview();
  }

  void _scheduleJob({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: immediate ? 0 : 250), _runJob);
  }

  Future<void> _runJob() async {
    final src = _src;
    if (src == null || !mounted) return;
    if (_jobRunning) return; // Re-run when the current one finishes.
    _jobRunning = true;
    final gen = _gen, size = _target;
    try {
      final out = await ImportScreen.runner(
          runImportJob, ImportJob(src, _s, size.$1, size.$2));
      if (!mounted || !identical(src, _src)) return;
      setState(() {
        _out = out;
        _outGen = gen;
        _outSize = size;
      });
      _updatePreview();
    } catch (e) {
      if (mounted) setState(() => _error = 'Processing failed: $e');
    } finally {
      _jobRunning = false;
    }
    if (mounted && (gen != _gen || size != _target) && !(_debounce?.isActive ?? false)) {
      _scheduleJob(immediate: true);
    }
  }

  /// The clip for the current settings, rendering it now if needed.
  Future<FrameClip?> _finalClip() async {
    if (_fresh) return _out!.clip;
    final src = _src;
    if (src == null) return null;
    final gen = _gen, size = _target;
    final out = await ImportScreen.runner(runImportJob, ImportJob(src, _s, size.$1, size.$2));
    if (mounted && gen == _gen) {
      setState(() {
        _out = out;
        _outGen = gen;
        _outSize = size;
      });
    }
    return out.clip;
  }

  // ---------------------------------------------------------------------------
  // Preview

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1000;
    _lastTick = elapsed;
    if (_playing) _clockMs += dt;
    _updatePreview();
  }

  void _updatePreview() {
    final src = _src;
    if (src == null || !mounted) return;
    final (tw, th) = _target;
    if (_fresh) {
      final clip = _out!.clip;
      final i = _indexAt(clip.delaysMs);
      final key = (_out, i);
      if (key != _shownKey) {
        _shownKey = key;
        _preview.value = clip.frames[i];
      }
      return;
    }
    // Until the background render lands, draw frames on the fly (without
    // palette reduction, which needs every frame).
    if (_picksGen != _gen) {
      _picks = selectFrames(src.delaysMs, _s);
      _picksGen = _gen;
    }
    final picks = _picks!;
    final i = _indexAt([for (final p in picks) p.$2]);
    final key = (_gen, tw, th, i);
    if (key == _shownKey) return;
    _shownKey = key;
    _preview.value = renderFrame(src.frames[picks[i].$1], src.width, src.height, _s, tw, th);
  }

  int _indexAt(List<int> delays) {
    if (delays.length == 1) return 0;
    final total = delays.fold<int>(0, (a, b) => a + b);
    var t = _clockMs % total;
    for (var i = 0; i < delays.length; i++) {
      t -= delays[i];
      if (t < 0) return i;
    }
    return delays.length - 1;
  }

  Future<void> _refreshCropImage() async {
    final src = _src;
    if (src == null) return;
    final s = _s;
    final frame = s.trimStart.clamp(0, src.frameCount - 1);
    final key = (src, s.quarterTurns, s.flipH, s.flipV, frame);
    _cropKey = key;
    final rgb = orient(src.frames[frame], src.width, src.height, s.quarterTurns,
        flipH: s.flipH, flipV: s.flipV);
    final (w, h) = orientedSize(src.width, src.height, s.quarterTurns);
    final rgba = Uint8List(w * h * 4);
    for (var i = 0, j = 0; i < rgb.length; i += 3, j += 4) {
      rgba[j] = rgb[i];
      rgba[j + 1] = rgb[i + 1];
      rgba[j + 2] = rgb[i + 2];
      rgba[j + 3] = 255;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
    final image = await done.future;
    if (!mounted || _cropKey != key) {
      image.dispose();
      return;
    }
    setState(() {
      _cropImage?.dispose();
      _cropImage = image;
    });
  }

  // ---------------------------------------------------------------------------
  // Actions

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  Map<String, dynamic> _meta() {
    final src = _src!;
    return {
      'source': {
        'name': ?_fileName,
        'format': src.format,
        'width': src.sourceWidth,
        'height': src.sourceHeight,
        'frames': src.sourceFrameCount,
      },
      'settings': _s.toJson(),
    };
  }

  Future<void> _play() async {
    final clip = await _finalClip();
    if (clip == null || !mounted) return;
    await GlyphActions.playClip(context, clip, _name);
    if (!mounted) return;
    _toast(AppScope.of(context).devices.isConnected
        ? 'Playing on the matrix'
        : 'Playing in the app. Connect a matrix to stream it.');
  }

  Future<void> _save() async {
    final title = await _askTitle();
    if (title == null || !mounted) return;
    final clip = await _finalClip();
    if (clip == null || !mounted) return;
    final c = await AppScope.of(context)
        .creations
        .save(id: _savedId, title: title, kind: 'import', clip: clip, meta: _meta());
    if (!mounted) return;
    setState(() {
      _savedId = c.id;
      _name = title;
    });
    _toast('Saved to My Creations');
  }

  Future<String?> _askTitle() => showDialog<String>(
      context: context, builder: (_) => _TitleDialog(initial: _name));

  Future<void> _upload() async {
    final caps = AppScope.of(context).devices.caps;
    if (caps == null) return _toast('Connect a matrix in the Matrix tab first.');
    if (!caps.canPlayGifs) {
      return _toast('This controller can\'t play GIFs. Use Play to stream it instead.');
    }
    setState(() => _uploading = true);
    try {
      final clip = await _finalClip();
      if (clip != null && mounted) await GlyphActions.saveClipToDevice(context, clip, _name);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _share({required bool gif}) async {
    final clip = await _finalClip();
    if (clip == null || !mounted) return;
    final c = Creation(
        id: _savedId ?? 'share',
        title: _name,
        kind: 'import',
        clip: clip,
        updatedAt: DateTime.now(),
        meta: _meta());
    await (gif ? shareCreationAsGif(context, c) : shareCreationFile(context, c));
  }

  // ---------------------------------------------------------------------------
  // UI

  @override
  Widget build(BuildContext context) {
    final devices = AppScope.of(context).devices;
    return ListenableBuilder(
      listenable: devices,
      builder: (context, _) {
        // A device (dis)connecting changes the target; refresh lazily.
        if (_src != null && _out != null && _outSize != _target && !_jobRunning) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !(_debounce?.isActive ?? false)) _scheduleJob(immediate: true);
          });
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Import'),
            actions: [
              if (_src != null) ...[
                IconButton(
                  tooltip: 'Open another',
                  icon: const Icon(Icons.folder_open_outlined),
                  onPressed: _loading ? null : () => _pick(anyFile: false),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Share',
                  icon: const Icon(Icons.ios_share),
                  onSelected: (v) => _share(gif: v == 'gif'),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'gif', child: Text('Share as GIF')),
                    PopupMenuItem(value: 'glyph', child: Text('Share Glyph file')),
                  ],
                ),
              ],
            ],
          ),
          body: _src == null ? _empty() : _editor(),
          bottomNavigationBar: _src == null ? null : _actionBar(),
        );
      },
    );
  }

  Widget _empty() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                  gradient: GlyphColors.brandGradient, borderRadius: BorderRadius.circular(26)),
              child: const Icon(Icons.gif_box_outlined, size: 44, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text('Bring in a GIF or image',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'GIF, PNG, JPEG, WebP or BMP. Animations keep their timing. '
              'Glyph files shared by friends open here too.',
              textAlign: TextAlign.center,
              style: TextStyle(color: GlyphColors.textMuted),
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Decoding…', style: TextStyle(color: GlyphColors.textMuted)),
              ])
            else ...[
              SizedBox(
                width: 260,
                child: FilledButton.icon(
                  onPressed: () => _pick(anyFile: false),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose image'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 260,
                child: OutlinedButton.icon(
                  onPressed: () => _pick(anyFile: true),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open a file'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center, style: const TextStyle(color: GlyphColors.warning)),
            ],
          ]),
        ),
      );

  Widget _editor() {
    final src = _src!;
    final (tw, th) = _target;
    final s = _s;
    final (ow, oh) = orientedSize(src.width, src.height, s.quarterTurns);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: Center(
            child: ValueListenableBuilder<Frame>(
              valueListenable: _preview,
              builder: (_, f, _) => LedMatrixView(frame: f, glow: true, borderRadius: 18),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _infoRow(src, tw, th),
        _sizeLine(),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: const TextStyle(color: GlyphColors.warning, fontSize: 12)),
          ),
        const SizedBox(height: 12),
        _Section(
          title: 'Frame',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 200,
              child: CropEditor(
                image: _cropImage,
                width: ow,
                height: oh,
                settings: s,
                targetWidth: tw,
                targetHeight: th,
                onChanged: _set,
                onTap: s.background == BackgroundMode.colour ? _pickColour : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.fit == FitMode.fill
                  ? 'Drag to move, pinch to zoom.'
                  : s.fit == FitMode.fit
                      ? 'The whole image, with black bars.'
                      : 'The whole image, squashed to fit.',
              style: const TextStyle(fontSize: 12, color: GlyphColors.textMuted),
            ),
            const SizedBox(height: 10),
            SegmentedButton<FitMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: FitMode.fill, label: Text('Fill')),
                ButtonSegment(value: FitMode.fit, label: Text('Fit')),
                ButtonSegment(value: FitMode.stretch, label: Text('Stretch')),
              ],
              selected: {s.fit},
              onSelectionChanged: (v) => _set(s.copyWith(fit: v.first)),
            ),
            const SizedBox(height: 6),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Rotate',
                  icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                  onPressed: () => _set(s.copyWith(quarterTurns: s.quarterTurns + 1)),
                ),
                IconButton(
                  tooltip: 'Flip horizontally',
                  isSelected: s.flipH,
                  icon: const Icon(Icons.flip),
                  onPressed: () => _set(s.copyWith(flipH: !s.flipH)),
                ),
                IconButton(
                  tooltip: 'Flip vertically',
                  isSelected: s.flipV,
                  icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
                  onPressed: () => _set(s.copyWith(flipV: !s.flipV)),
                ),
                FilterChip(
                  label: const Text('Pixel art'),
                  selected: s.pixelArt,
                  onSelected: (v) => _set(s.copyWith(pixelArt: v)),
                ),
              ],
            ),
          ]),
        ),
        _Section(
          title: 'Tone',
          child: Column(children: [
            _slider('Brightness', s.brightness, -0.5, 0.5, (v) => _set(s.copyWith(brightness: v)),
                label: '${(s.brightness * 200).round()}'),
            _slider('Contrast', s.contrast, 0.5, 2, (v) => _set(s.copyWith(contrast: v))),
            _slider('Saturation', s.saturation, 0, 2, (v) => _set(s.copyWith(saturation: v))),
            _slider('Gamma', s.gamma, 0.5, 2.5, (v) => _set(s.copyWith(gamma: v))),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => _set(s.withToneOf(const ImportSettings())),
                child: const Text('Original'),
              ),
              TextButton(
                onPressed: () => _set(s.withToneOf(ImportSettings.ledDefaults)),
                child: const Text('LED tuned'),
              ),
            ]),
          ]),
        ),
        _Section(
          title: 'Background',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Turn background off'),
              subtitle: const Text('Dark or one colour becomes unlit LEDs'),
              value: s.background != BackgroundMode.off,
              onChanged: (v) =>
                  _set(s.copyWith(background: v ? BackgroundMode.dark : BackgroundMode.off)),
            ),
            if (s.background != BackgroundMode.off) ...[
              SegmentedButton<BackgroundMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: BackgroundMode.dark, label: Text('Near-black')),
                  ButtonSegment(value: BackgroundMode.colour, label: Text('A colour')),
                ],
                selected: {s.background},
                onSelectionChanged: (v) => _set(s.copyWith(background: v.first)),
              ),
              if (s.background == BackgroundMode.colour)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | s.bgColor),
                        shape: BoxShape.circle,
                        border: Border.all(color: GlyphColors.outline, width: 2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Tap the image above to pick the colour',
                          style: TextStyle(fontSize: 12, color: GlyphColors.textMuted)),
                    ),
                  ]),
                ),
              _slider('Tolerance', s.bgTolerance, 0, 0.5, (v) => _set(s.copyWith(bgTolerance: v)),
                  label: '${(s.bgTolerance * 100).round()}%'),
            ],
          ]),
        ),
        _Section(
          title: 'Colours',
          child: Column(children: [
            _slider(
              'Colours',
              _colorSteps.indexOf(s.colors).clamp(0, _colorSteps.length - 1).toDouble(),
              0,
              _colorSteps.length - 1.0,
              (v) => _set(s.copyWith(colors: _colorSteps[v.round()])),
              divisions: _colorSteps.length - 1,
              label: s.colors == 0 ? 'All' : '${s.colors}',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dither'),
              subtitle: const Text('Smoother gradients with fewer colours'),
              value: s.dither,
              onChanged: s.colors == 0 ? null : (v) => _set(s.copyWith(dither: v)),
            ),
          ]),
        ),
        if (src.isAnimated) _timing(src),
      ],
    );
  }

  Widget _infoRow(DecodedSource src, int tw, int th) {
    final picks = _fresh ? _out!.clip.delaysMs : [for (final p in selectFrames(src.delaysMs, _s)) p.$2];
    final secs = picks.fold<int>(0, (a, b) => a + b) / 1000;
    final connected = AppScope.of(context).devices.caps != null;
    return Row(children: [
      if (src.isAnimated)
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play',
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          onPressed: () => setState(() => _playing = !_playing),
        ),
      Expanded(
        child: Text(
          src.isAnimated
              ? '${picks.length} frames · ${secs.toStringAsFixed(1)} s'
              : 'Still image',
          style: const TextStyle(color: GlyphColors.textMuted),
        ),
      ),
      if (connected)
        Text('$tw×$th', style: const TextStyle(fontWeight: FontWeight.w600))
      else
        PopupMenuButton<(int, int)>(
          tooltip: 'Matrix size',
          initialValue: _manualSize,
          onSelected: _setSize,
          itemBuilder: (_) => [
            for (final z in _sizes) PopupMenuItem(value: z, child: Text('${z.$1}×${z.$2}')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$tw×$th', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Icon(Icons.arrow_drop_down, size: 20),
            ]),
          ),
        ),
    ]);
  }

  Widget _sizeLine() {
    final caps = AppScope.of(context).devices.caps;
    final src = _src!;
    final notes = <String>[
      if (src.wasSampled) 'long animation sampled to ${src.frameCount} frames',
    ];
    if (!_fresh) {
      return _line('Estimating GIF size…', GlyphColors.textMuted, notes);
    }
    final bytes = _out!.gifBytes;
    final kb = '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (caps == null) return _line('GIF ≈ $kb', GlyphColors.textMuted, notes);
    if (!caps.canPlayGifs) {
      return _line('GIF ≈ $kb · this controller can only stream', GlyphColors.textMuted, notes);
    }
    final free = '${(caps.freeFsBytes / 1024).round()} KB free';
    return caps.fitsFile(bytes)
        ? _line('GIF ≈ $kb · fits on the matrix ($free)', GlyphColors.success, notes)
        : _line('GIF ≈ $kb · too big ($free). Trim, skip frames or use fewer colours.',
            GlyphColors.warning, notes);
  }

  Widget _line(String text, Color color, List<String> notes) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text(
          [text, ...notes].join(' · '),
          style: TextStyle(fontSize: 12, color: color),
        ),
      );

  Widget _timing(DecodedSource src) {
    final s = _s;
    final n = src.frameCount;
    final end = (s.trimEnd ?? n - 1).clamp(s.trimStart, n - 1);
    final speedIdx = _speeds.indexWhere((x) => x >= s.speed).clamp(0, _speeds.length - 1);
    return _Section(
      title: 'Timing',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Frames ${s.trimStart + 1}–${end + 1} of $n',
            style: const TextStyle(color: GlyphColors.textMuted, fontSize: 13)),
        RangeSlider(
          values: RangeValues(s.trimStart.toDouble(), end.toDouble()),
          max: n - 1.0,
          divisions: n - 1,
          onChanged: (r) => _set(s.copyWith(
            trimStart: r.start.round(),
            trimEnd: () => r.end.round() >= n - 1 ? null : r.end.round(),
          )),
        ),
        _slider('Speed', speedIdx.toDouble(), 0, _speeds.length - 1.0,
            (v) => _set(s.copyWith(speed: _speeds[v.round()])),
            divisions: _speeds.length - 1, label: '${_speeds[speedIdx]}×'),
        _slider('Keep', s.frameStep.toDouble(), 1, 6, (v) => _set(s.copyWith(frameStep: v.round())),
            divisions: 5, label: s.frameStep == 1 ? 'All' : '1 in ${s.frameStep}'),
      ]),
    );
  }

  Widget _slider(String name, double value, double min, double max, ValueChanged<double> onChanged,
          {int? divisions, String? label}) =>
      Row(children: [
        SizedBox(
            width: 84,
            child: Text(name, style: const TextStyle(color: GlyphColors.textMuted, fontSize: 13))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(label ?? value.toStringAsFixed(2),
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
        ),
      ]);

  Widget _actionBar() {
    final caps = AppScope.of(context).devices.caps;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: GlyphColors.surface,
          border: Border(top: BorderSide(color: GlyphColors.outline)),
        ),
        child: Row(children: [
          IconButton.filledTonal(
            tooltip: 'Play on matrix',
            onPressed: _play,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(onPressed: _save, child: const Text('Save')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: caps != null && !_uploading ? _upload : null,
              child: _uploading
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('To matrix'),
            ),
          ),
        ]),
      ),
    );
  }

  void _pickColour(double x, double y) {
    final src = _src!;
    final (rx, ry) = orientedToRaw(x, y, src.width, src.height, _s);
    final px = rx.floor().clamp(0, src.width - 1), py = ry.floor().clamp(0, src.height - 1);
    final f = src.frames[_s.trimStart.clamp(0, src.frameCount - 1)];
    final i = (py * src.width + px) * 3;
    _set(_s.copyWith(bgColor: (f[i] << 16) | (f[i + 1] << 8) | f[i + 2]));
  }
}

class _TitleDialog extends StatefulWidget {
  const _TitleDialog({required this.initial});
  final String initial;

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _done() {
    final t = _ctrl.text.trim();
    Navigator.pop(context, t.isEmpty ? widget.initial : t);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Name it'),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'Title'),
          onSubmitted: (_) => _done(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _done, child: const Text('Save')),
        ],
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        // A Material (not a coloured box) so list tiles can paint ink.
        child: Material(
          color: GlyphColors.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _body(),
          ),
        ),
      );

  Widget _body() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: GlyphColors.textMuted)),
            const SizedBox(height: 8),
            child,
          ],
        );
}
