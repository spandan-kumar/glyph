import 'package:flutter/material.dart';

import '../../../app/devices.dart';
import '../../../app/playback.dart';
import '../../../ui/theme.dart';
import '../device_manager.dart';
import 'common.dart';

/// Power, master brightness, night light and what's playing, synced from
/// /json/state.
class QuickControls extends StatelessWidget {
  const QuickControls({
    super.key,
    required this.store,
    required this.manager,
    required this.playback,
  });

  final DeviceStore store;
  final DeviceManager manager;
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final on = store.isOn ?? false;
    final info = store.info;
    final status = playback.isStreaming
        ? 'Live from Glyph'
        : !on
        ? 'Off'
        : store.playlistRunning
        ? store.playlistId != null
              ? 'Playlist · ${manager.presetName(store.playlistId!)}'
              : 'Playlist running'
        : store.presetId != null
        ? manager.presetName(store.presetId!)
        : info?.isLive == true
        ? 'Live (${info!.liveSource})'
        : 'No preset active';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      decoration: BoxDecoration(
        color: GlyphColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GlyphColors.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _DeviceSwitcher(store: store)),
              Switch(
                value: on,
                onChanged: store.isOn == null
                    ? null
                    : (v) => guarded(context, () => store.setPower(v)),
              ),
            ],
          ),
          Row(
            children: [
              Icon(
                on ? Icons.play_circle_outline : Icons.power_settings_new,
                size: 16,
                color: GlyphColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: GlyphColors.textMuted, fontSize: 13),
                ),
              ),
              if (store.playlistRunning)
                IconButton(
                  tooltip: 'Next in playlist',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: () => guarded(context, () async {
                    await store.client?.nextInPlaylist();
                    await Future<void>.delayed(const Duration(milliseconds: 400));
                    await store.refreshState();
                  }),
                ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.brightness_6_outlined, size: 20, color: GlyphColors.textMuted),
              Expanded(
                child: Slider(
                  value: (store.brightness ?? 128).clamp(1, 255).toDouble(),
                  min: 1,
                  max: 255,
                  onChanged: store.brightness == null
                      ? null
                      : (v) => store.setBrightness(v.round()),
                ),
              ),
              IconButton(
                tooltip: 'Night light',
                isSelected: store.nightlightOn,
                selectedIcon: const Icon(Icons.bedtime, color: GlyphColors.warning),
                icon: const Icon(Icons.bedtime_outlined),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => NightlightSheet(store: store),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceSwitcher extends StatelessWidget {
  const _DeviceSwitcher({required this.store});

  final DeviceStore store;

  @override
  Widget build(BuildContext context) {
    final name = store.info?.name ?? store.selected?.name ?? 'Matrix';
    final title = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    );
    if (store.saved.length < 2) return title;
    return PopupMenuButton<String>(
      tooltip: 'Switch matrix',
      onSelected: (host) => store.select(store.saved.firstWhere((d) => d.host == host)),
      itemBuilder: (_) => [
        for (final d in store.saved)
          CheckedPopupMenuItem(
            value: d.host,
            checked: d.host == store.selected?.host,
            child: Text(d.name),
          ),
      ],
      child: Row(
        children: [
          Flexible(child: title),
          const Icon(Icons.expand_more, color: GlyphColors.textMuted),
        ],
      ),
    );
  }
}

/// WLED's night light: dims to a target over a duration, then (at target 0)
/// switches off. Modes per json.cpp "nl": 0 instant, 1 fade, 2 colour fade,
/// 3 sunrise.
class NightlightSheet extends StatefulWidget {
  const NightlightSheet({super.key, required this.store});

  final DeviceStore store;

  @override
  State<NightlightSheet> createState() => _NightlightSheetState();
}

class _NightlightSheetState extends State<NightlightSheet> {
  double _minutes = 30;
  int _mode = 1;

  @override
  Widget build(BuildContext context) {
    final on = widget.store.nightlightOn;
    final lightOff = widget.store.isOn == false;
    final sun = _mode == 3;
    // Fading needs the light on; the Sunrise effect caps at 60 min (led.cpp
    // handleNightlight).
    final maxMin = sun ? 60.0 : 120.0;
    final minutes = _minutes.clamp(5.0, maxMin);
    final canStart = sun || !lightOff;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Night light', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const Text(
              'The matrix fades out by itself, even if your phone is off.',
              style: TextStyle(color: GlyphColors.textMuted),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Fade')),
                ButtonSegment(value: 0, label: Text('Wait')),
                ButtonSegment(value: 3, label: Text('Sunrise')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(width: 70, child: Text('${minutes.round()} min')),
                Expanded(
                  child: Slider(
                    value: minutes,
                    min: 5,
                    max: maxMin,
                    divisions: ((maxMin - 5) / 5).round(),
                    onChanged: (v) => setState(() => _minutes = v),
                  ),
                ),
              ],
            ),
            Text(
              sun
                  ? lightOff
                        ? 'A sunrise over ${minutes.round()} min.'
                        : 'A sunset over ${minutes.round()} min.'
                  : lightOff
                  ? 'Turn the matrix on first.'
                  : _mode == 0
                  ? 'Switches off after ${minutes.round()} min.'
                  : 'Dims to off over ${minutes.round()} min.',
              style: const TextStyle(fontSize: 12, color: GlyphColors.textMuted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (on)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _set(false, minutes.round()),
                      child: const Text('Cancel night light'),
                    ),
                  ),
                if (on) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: canStart ? () => _set(true, minutes.round()) : null,
                    child: Text(on ? 'Restart' : 'Start'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _set(bool on, int minutes) async {
    final ok = await guarded(
      context,
      () => widget.store.setNightlight(
        on,
        minutes: minutes,
        mode: _mode,
        targetBri: _mode == 3 ? null : 0,
      ),
    );
    if (ok && mounted) Navigator.pop(context);
  }
}
