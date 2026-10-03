import 'package:flutter/material.dart';

import '../../app/background.dart';
import '../../engine/palette.dart';
import '../../features/audio/visualizers.dart';
import '../actions.dart';
import '../scope.dart';
import '../theme.dart';
import 'led_matrix_view.dart';

void showNowPlayingSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _NowPlayingSheet(),
  );
}

class _NowPlayingSheet extends StatefulWidget {
  const _NowPlayingSheet();

  @override
  State<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<_NowPlayingSheet> {
  bool _saving = false;
  String? _saveResult;

  Future<void> _setBackground(bool on) async {
    final scope = AppScope.of(context);
    final playback = scope.playback, devices = scope.devices;
    if (!on) return BackgroundStreaming.stop();
    await BackgroundStreaming.start(
      title: 'Glyph is streaming to ${devices.info?.name ?? 'your matrix'}',
      microphone: playback.generator is AudioVisualizer,
      onStop: () {
        playback.pause();
        playback.stopStreaming();
        devices.client?.exitLive();
      },
    );
    BackgroundStreaming.watch(playback);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback;
    final devices = scope.devices;

    return ListenableBuilder(
      listenable: Listenable.merge([playback, devices]),
      builder: (context, _) {
        final g = playback.generator;
        if (g == null) return const SizedBox(height: 200);
        final caps = devices.caps;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: LedMatrixView(
                    frame: playback.frame,
                    repaint: playback.frameTick,
                    glow: true,
                    borderRadius: 24,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(playback.item?.title ?? g.name,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              Text('${g.name} · ${playback.palette.name}',
                  style: const TextStyle(color: GlyphColors.textMuted)),
              if (playback.item?.notice case final notice?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(notice,
                      style: const TextStyle(fontSize: 11, color: GlyphColors.textMuted)),
                ),
              const SizedBox(height: 20),
              _Section(
                title: 'Matrix',
                child: Column(children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Stream live'),
                    subtitle: Text(devices.isConnected
                        ? playback.isStreaming
                            ? '${playback.framesSent} frames sent'
                                '${playback.sendErrors > 0 ? ' · ${playback.sendErrors} dropped' : ''}'
                            : 'Send this animation to ${devices.info!.name}'
                        : 'Connect a matrix in the Matrix tab'),
                    value: playback.isStreaming,
                    onChanged: devices.isConnected
                        ? (on) => on
                            ? GlyphActions.ensureStreaming(context)
                            : GlyphActions.stopStreaming(context)
                        : null,
                  ),
                  if (BackgroundStreaming.supported && playback.isStreaming)
                    ValueListenableBuilder<bool>(
                      valueListenable: BackgroundStreaming.running,
                      builder: (context, running, _) => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Keep running in background'),
                        subtitle: const Text('Streams with the screen off'),
                        value: running,
                        onChanged: _setBackground,
                      ),
                    ),
                  Row(children: [
                    const Icon(Icons.brightness_6_outlined,
                        size: 20, color: GlyphColors.textMuted),
                    Expanded(
                      child: Slider(
                        value: (devices.brightness ?? 128).toDouble(),
                        max: 255,
                        onChanged: devices.isConnected
                            ? (v) => devices.setBrightness(v.round())
                            : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (caps?.canPlayGifs ?? false) && !_saving
                          ? () async {
                              setState(() {
                                _saving = true;
                                _saveResult = null;
                              });
                              final result = await GlyphActions.saveToDevice(context);
                              if (mounted) {
                                setState(() {
                                  _saving = false;
                                  _saveResult = result;
                                });
                              }
                            }
                          : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_for_offline_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save to matrix'),
                    ),
                  ),
                  if (_saveResult != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_saveResult!,
                          style: TextStyle(
                              fontSize: 12,
                              color: _saveResult!.startsWith('Saved')
                                  ? GlyphColors.success
                                  : GlyphColors.warning)),
                    ),
                  if (caps != null && !caps.canPlayGifs)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'This controller can\'t play GIFs (needs ESP32 + WLED 16). Live streaming works.',
                        style: TextStyle(fontSize: 12, color: GlyphColors.textMuted),
                      ),
                    ),
                ]),
              ),
              _Section(
                title: 'Colours',
                child: SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final p in palettes)
                        _PaletteSwatch(
                          palette: p,
                          selected: p.id == playback.palette.id,
                          onTap: () => playback.setPalette(p),
                        ),
                    ],
                  ),
                ),
              ),
              if (g.params.isNotEmpty)
                _Section(
                  title: 'Tweak',
                  child: Column(children: [
                    for (final spec in g.params)
                      Row(children: [
                        SizedBox(
                            width: 80,
                            child: Text(spec.label,
                                style: const TextStyle(color: GlyphColors.textMuted))),
                        Expanded(
                          child: Slider(
                            min: spec.min,
                            max: spec.max,
                            value: playback.params[spec.key].clamp(spec.min, spec.max),
                            onChanged: (v) => playback.setParam(spec.key, v),
                          ),
                        ),
                      ]),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: GlyphColors.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
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
            ),
          ),
        ),
      );
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch(
      {required this.palette, required this.selected, required this.onTap});

  final Palette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Tooltip(
          message: palette.name,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    for (final c in palette.swatch) Color(0xFF000000 | c),
                  ],
                ),
                border: Border.all(
                  color: selected ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          ),
        ),
      );
}
