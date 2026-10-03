import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/creations.dart';
import '../../engine/clip.dart';
import '../../engine/frame.dart';
import '../../engine/generator.dart';
import '../../engine/gif_baker.dart';
import '../../engine/palette.dart';
import '../../engine/registry.dart';
import '../../ui/actions.dart';
import '../../ui/scope.dart';
import '../../ui/design/parts.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/studio_kit.dart';
import '../../ui/make/tool_session.dart';
import '../../ui/widgets/led_matrix_view.dart';
import 'native_text.dart';
import 'text_generators.dart';
import 'text_settings.dart';

/// The text tools: Write (scrolling text), Clock and Timer (countdown). Each
/// opens straight into its own mode with only that mode's controls; a saved
/// creation reopens in the mode it was made with.
class TextStudioScreen extends StatefulWidget {
  const TextStudioScreen({super.key, this.initial, this.mode = 'text'});

  final Creation? initial;

  /// 'text' | 'clock' | 'countdown'. Ignored when [initial] has its own
  /// mode in its meta.
  final String mode;

  @override
  State<TextStudioScreen> createState() => _TextStudioScreenState();
}

const _presets = <(String, Map<String, dynamic>)>[
  ('Happy Birthday', {'colorMode': 'rainbow', 'background': 'fireworks', 'effect': 'outline', 'direction': 'left'}),
  ('Open', {'colorMode': 'solid', 'color': 0x4BE3A0, 'font': 'bold', 'direction': 'static', 'background': ''}),
  ('On Air', {'colorMode': 'solid', 'color': 0xFF2244, 'font': 'bold', 'direction': 'static', 'background': ''}),
  ('Welcome', {'colorMode': 'animated', 'palette': 'sunset', 'direction': 'left', 'background': ''}),
  ('♥ Love ♥', {'colorMode': 'animated', 'palette': 'heart', 'direction': 'left', 'background': 'twinkle'}),
  ('Game On', {'colorMode': 'gradient', 'palette': 'neon', 'font': 'bold', 'direction': 'left', 'background': 'rain'}),
  ('Merry Christmas', {'colorMode': 'rainbow', 'palette': 'christmas', 'direction': 'left', 'background': 'snow', 'effect': 'outline'}),
];

const _swatches = [0x3DDCFF, 0xFF2244, 0xFFB547, 0x4BE3A0, 0x8B7CFF, 0xFFFFFF, 0xFF6AD5, 0xFF7A00];

const _previewSizes = [(16, 16), (32, 8), (8, 8), (32, 32)];

class _TextStudioScreenState extends State<TextStudioScreen>
    with SingleTickerProviderStateMixin, ToolSession<TextStudioScreen> {
  late final String _mode;
  late TextSettings _s;
  late final TextEditingController _textCtl;
  late final TextEditingController _doneCtl;
  late final Ticker _ticker;
  final _tick = ValueNotifier(0);
  (int, int) _pickedSize = _previewSizes.first;
  Frame _frame = Frame(16, 16);
  EffectInstance? _instance;
  Generator? _pushed;
  double _t = 0;
  Duration _last = Duration.zero;
  Timer? _pushDebounce;
  bool _native = true;
  bool _busy = false;
  String? _result;
  String? _creationId;

  @override
  void initState() {
    super.initState();
    final meta = widget.initial?.meta;
    _mode = (meta?['mode'] as String?) ?? widget.mode;
    _s = meta != null ? TextSettings.fromJson(meta) : TextSettings();
    if (meta == null) {
      switch (_mode) {
        case 'clock':
          _s
            ..font = 'bold'
            ..colorMode = 'animated'
            ..palette = 'ocean';
        case 'countdown':
          _s
            ..font = 'bold'
            ..colorMode = 'animated'
            ..palette = 'sunset';
      }
    }
    _creationId = widget.initial?.id;
    _textCtl = TextEditingController(text: _s.text);
    _doneCtl = TextEditingController(text: _s.doneText);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuild(push: false);
  }

  @override
  void dispose() {
    _pushDebounce?.cancel();
    _ticker.dispose();
    _tick.dispose();
    _textCtl.dispose();
    _doneCtl.dispose();
    super.dispose();
  }

  (int, int) get _size {
    final caps = AppScope.of(context).devices.caps;
    if (caps != null && caps.is2D) return (caps.width, caps.height);
    return _pickedSize;
  }

  Generator _makeGenerator() => switch (_mode) {
        'clock' => ClockGenerator(_s),
        'countdown' => CountdownGenerator(_s),
        _ => ScrollingText(_s),
      };

  void _rebuild({bool push = true}) {
    final (w, h) = _size;
    if (_frame.width != w || _frame.height != h) _frame = Frame(w, h);
    final g = _makeGenerator();
    _instance = g.create(w, h, 1);
    _t = 0;
    if (!push) return;
    final playback = AppScope.of(context).playback;
    if (_pushed != null && playback.generator == _pushed) {
      _pushDebounce?.cancel();
      _pushDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted || playback.generator != _pushed) return;
        _pushed = _makeGenerator();
        playback.playGenerator(_pushed!);
        toolOwns(_pushed!);
      });
    }
  }

  void _update(void Function() change) {
    setState(() {
      change();
      _result = null;
    });
    _rebuild();
  }

  void _onTick(Duration elapsed) {
    if ((elapsed - _last).inMilliseconds < 33) return;
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _t += dt;
    final pal = paletteById(_s.palette);
    _instance?.render(_frame, _t, dt, Params({}), pal);
    _tick.value++;
  }

  String get _title => switch (_mode) {
        'clock' => 'Clock',
        'countdown' => _s.doneText.trim().isEmpty ? 'Timer' : 'Timer: ${_s.doneText.trim()}',
        _ => _s.text.trim().isEmpty ? 'Text' : _s.text.trim(),
      };

  Future<void> _play() async {
    final playback = AppScope.of(context).playback;
    _pushed = _makeGenerator();
    playback.playGenerator(_pushed!);
    toolPlays(_pushed!);
    await GlyphActions.ensureStreaming(context);
    if (!mounted) return;
    if (!AppScope.of(context).devices.isConnected) {
      _toast('Playing here on your phone. Connect a device to see it big.');
    }
  }

  /// Renders the current design into a clip at [w]×[h].
  FrameClip _bake(int w, int h) {
    final g = _makeGenerator();
    var seconds = 4.0;
    if (_mode == 'text') {
      final loop = (g.create(w, h, 1) as TextInstance).loopSeconds;
      if (loop != null) seconds = loop.clamp(2.0, 12.0);
    }
    final fps = min(20, max(8, (240 / seconds).floor()));
    final frames = renderFrames(
      generator: g,
      params: Params({}),
      palette: paletteById(_s.palette),
      width: w,
      height: h,
      seconds: seconds,
      fps: fps,
      warmup: _s.background.isEmpty ? 0 : 1.5,
    );
    return FrameClip.uniform(frames, fps: fps);
  }

  Future<void> _saveCreation() async {
    final (w, h) = _size;
    final c = await AppScope.of(context).creations.save(
          id: _creationId,
          title: _title,
          kind: 'text',
          clip: _bake(w, h),
          meta: {..._s.toJson(), 'mode': _mode},
        );
    _creationId = c.id;
    _toast('Saved to Made by you');
  }

  Future<void> _saveToMatrix() async {
    final scope = AppScope.of(context);
    final devices = scope.devices;
    final caps = devices.caps, client = devices.client;
    if (caps == null || client == null) {
      _toast('Connect a device to send this to it.');
      return;
    }
    if (_mode == 'text' && _s.text.trim().isEmpty) {
      _toast('Type a message first.');
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    String? msg;
    try {
      if (_mode == 'clock' || (_native && caps.is2D)) {
        await GlyphActions.stopStreaming(context);
        await saveNativeText(client,
            s: _s,
            mode: _mode,
            presetName: _title,
            rows: caps.height,
            isEsp8266: caps.isEsp8266);
        await devices.refresh();
        msg = 'Sent to your device. Unplug your phone — it keeps playing.';
        if (_mode == 'clock' && _clockUnsynced(devices.info?.raw)) {
          msg += ' Your device doesn\'t know the time yet: turn on internet time in its Time settings.';
        }
      } else {
        final clip = _bake(caps.width, caps.height);
        if (!mounted) return;
        msg = await sendClipFromTool(clip, _title);
      }
    } catch (e) {
      msg = 'Couldn\'t send it: $e';
    }
    noteSent(msg);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = msg;
    });
  }

  static bool _clockUnsynced(Map<String, dynamic>? info) {
    final t = info?['time'];
    final y = t is String ? int.tryParse(t.split('-').first) : null;
    return y != null && y < 2020;
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _s.target != null && _s.target!.isAfter(now) ? _s.target! : now.add(const Duration(days: 1));
    final d = await showDatePicker(
        context: context, initialDate: initial, firstDate: now, lastDate: DateTime(now.year + 5));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return;
    _update(() {
      _s.target = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      _s.useDuration = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final devices = AppScope.of(context).devices;
    return ListenableBuilder(
      listenable: devices,
      builder: (context, _) {
        final (w, h) = _size;
        if (_frame.width != w || _frame.height != h) _rebuild(push: false);
        final caps = devices.caps;
        return StudioScaffold(
          title: switch (_mode) {
            'clock' => 'Clock',
            'countdown' => 'Timer',
            _ => 'Write',
          },
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 360, maxHeight: w >= h * 2 ? 140 : 240),
                  child: LedMatrixView(
                      frame: _frame, repaint: _tick, glow: true, bezel: true, borderRadius: Lb.rControl),
                ),
              ),
              const SizedBox(height: 12),
              if (caps != null && caps.is2D)
                Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const StatusDot(on: true),
                    const SizedBox(width: 8),
                    MonoLabel('${devices.info?.name ?? 'Device'} · ${caps.width}×${caps.height}'),
                  ]),
                )
              else
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  children: [
                    for (final sz in _previewSizes)
                      ChoiceChip(
                        label: Text('${sz.$1}×${sz.$2}'),
                        selected: _pickedSize == sz,
                        onSelected: (_) => _update(() => _pickedSize = sz),
                      ),
                  ],
                ),
              const SizedBox(height: 18),
              ..._modeControls(w, h),
              _styleSection(),
              if (_mode == 'text') _motionSection(),
              _backgroundSection(),
              _actions(caps?.is2D ?? false),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _modeControls(int w, int h) => switch (_mode) {
        'clock' => [
            StudioGroup(
              label: 'Clock',
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Column(children: [
                _switch('24-hour', _s.hour24, (v) => _s.hour24 = v),
                _switch('Seconds', _s.seconds, (v) => _s.seconds = v),
                _switch('Blinking colon', _s.blink, (v) => _s.blink = v),
                _switch('Date when there\'s room', _s.date, (v) => _s.date = v),
                _switch('Analog face', _s.analog, (v) => _s.analog = v,
                    subtitle: analogFits(w, h) ? null : 'Needs a square device, 16×16 or bigger'),
              ]),
            ),
          ],
        'countdown' => [
            StudioGroup(
              label: 'Count down to',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (label, secs) in const [('1 min', 60), ('5 min', 300), ('10 min', 600), ('25 min', 1500), ('1 hour', 3600)])
                    ChoiceChip(
                      label: Text(label),
                      selected: _s.useDuration && _s.durationSec == secs,
                      onSelected: (_) => _update(() {
                        _s.useDuration = true;
                        _s.durationSec = secs;
                      }),
                    ),
                  ChoiceChip(
                    avatar: const Icon(Icons.event, size: 16),
                    label: Text(!_s.useDuration && _s.target != null ? _fmtDate(_s.target!) : 'Date & time'),
                    selected: !_s.useDuration,
                    onSelected: (_) => _pickDate(),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _doneCtl,
                  decoration: const InputDecoration(
                      hintText: 'Message at zero', prefixIcon: Icon(Icons.celebration_outlined)),
                  onChanged: (v) => _update(() => _s.doneText = v),
                ),
              ]),
            ),
          ],
        _ => [
            TextField(
              controller: _textCtl,
              maxLength: 120,
              style: LbType.title,
              decoration: const InputDecoration(hintText: 'Type your message', counterText: ''),
              onChanged: (v) => _update(() => _s.text = v),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (label, style) in _presets)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(label),
                        onPressed: () => _update(() {
                          final next = TextSettings.fromJson({..._s.toJson(), ...style, 'text': label});
                          _s = next;
                          _textCtl.text = label;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
      };

  Widget _switch(String label, bool value, void Function(bool) set, {String? subtitle}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label, style: LbType.body),
        subtitle: subtitle == null ? null : Text(subtitle, style: LbType.small),
        value: value,
        onChanged: (v) => _update(() => set(v)),
      );

  Widget _chips<T>(List<(T, String)> options, T selected, void Function(T) onPick) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (v, label) in options)
            ChoiceChip(label: Text(label), selected: v == selected, onSelected: (_) => _update(() => onPick(v))),
        ],
      );

  Widget _styleSection() => StudioGroup(
        label: 'Style',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _chips([('tiny', 'Tiny'), ('classic', 'Classic'), ('bold', 'Bold')], _s.font, (v) => _s.font = v),
          _switch('Large on tall devices', _s.large, (v) => _s.large = v),
          const SizedBox(height: 4),
          _chips([('solid', 'Solid'), ('gradient', 'Gradient'), ('rainbow', 'Rainbow'), ('animated', 'Animated')],
              _s.colorMode, (v) => _s.colorMode = v),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _s.colorMode == 'solid'
                  ? [
                      for (final c in _swatches)
                        _Dot(
                          selected: _s.color == c,
                          decoration: BoxDecoration(color: Color(0xFF000000 | c)),
                          onTap: () => _update(() => _s.color = c),
                        ),
                    ]
                  : [
                      for (final p in palettes)
                        _Dot(
                          selected: _s.palette == p.id,
                          decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [for (final c in p.swatch) Color(0xFF000000 | c)])),
                          onTap: () => _update(() => _s.palette = p.id),
                        ),
                    ],
            ),
          ),
          const SizedBox(height: 12),
          _chips([('none', 'Plain'), ('outline', 'Outline'), ('shadow', 'Shadow')], _s.effect, (v) => _s.effect = v),
        ]),
      );

  Widget _motionSection() => StudioGroup(
        label: 'Motion',
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: _chips([('left', '← Left'), ('right', 'Right →'), ('up', '↑ Up'), ('static', 'Still')],
                _s.direction, (v) => _s.direction = v),
          ),
          const SizedBox(width: 12),
          StudioKnob(
            label: 'Speed',
            value: _s.speed,
            size: 56,
            onChanged: (v) => _update(() => _s.speed = v),
          ),
        ]),
      );

  Widget _backgroundSection() => StudioGroup(
        label: 'Background',
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final (id, name) in [('', 'None'), for (final g in generators) (g.id, g.name)])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(name),
                    selected: _s.background == id,
                    onSelected: (_) => _update(() => _s.background = id),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _actions(bool is2D) {
    final connected = AppScope.of(context).devices.isConnected;
    final countdown = _mode == 'countdown';
    final note = switch (_mode) {
      'clock' => 'A clock sent to your device runs on the device itself, so it keeps time without your phone. '
          'It uses the device\'s own font; 12/24-hour follows its time settings.',
      'countdown' => 'Timers run from your phone, so use Play on device.',
      _ => _native
          ? 'Sent as words: live time like #HH:#MM works, '
              'but it uses the device\'s own font and colours.'
          : 'Sent as an animation: your exact look and background, but the words are fixed.',
    };
    final ok = _result != null && const ['Sent', 'Kept', 'Saved'].any(_result!.startsWith);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      FilledButton.icon(
        onPressed: _play,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Play on device'),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saveCreation,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Save'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: connected && !countdown && !_busy && (is2D || (_mode == 'text' && !_native))
                ? _saveToMatrix
                : null,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.push_pin_outlined, size: 18),
            label: FittedBox(child: Text(_busy ? 'Sending…' : 'Send to device')),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      if (_mode == 'text') ...[
        const MonoLabel('Send as'),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          style: studioSegmentStyle,
          segments: const [
            ButtonSegment(value: true, label: Text('Device font')),
            ButtonSegment(value: false, label: Text('Exact look')),
          ],
          selected: {_native},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _native = v.first),
        ),
        const SizedBox(height: 8),
      ],
      Text(note, style: LbType.small),
      if (!connected)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Connect a device to send it there.', style: LbType.small.copyWith(color: Lb.text3)),
        ),
      if (_result != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_result!, style: LbType.small.copyWith(color: ok ? Lb.ok : Lb.phosphor)),
        ),
    ]);
  }

  static String _fmtDate(DateTime d) =>
      '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Dot extends StatelessWidget {
  const _Dot({required this.selected, required this.decoration, required this.onTap});

  final bool selected;
  final BoxDecoration decoration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Lb.fast,
            width: 34,
            height: 34,
            decoration: decoration.copyWith(
              borderRadius: const BorderRadius.all(Radius.circular(Lb.rTile)),
              border: Border.all(color: selected ? Lb.text : Lb.line, width: selected ? 2.5 : 1),
            ),
          ),
        ),
      );
}
