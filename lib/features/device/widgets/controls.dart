import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/devices.dart';
import '../../../ui/design/knob.dart';
import '../../../ui/design/parts.dart';
import '../../../ui/design/tokens.dart';
import '../../../ui/design/type.dart';
import 'common.dart';

/// Power, brightness and night light, laid out like the front of a device.
class HardwareControls extends StatelessWidget {
  const HardwareControls({super.key, required this.store});

  final DeviceStore store;

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(context);
    final on = store.isOn ?? false;
    final bri = store.brightness;
    return LbPanel(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Labelled(
              label: on ? 'On' : 'Off',
              child: ChunkyButton(
                key: const ValueKey('power'),
                semantics: 'Power',
                lit: on,
                litColor: Lb.ok,
                icon: Icons.power_settings_new_sharp,
                onTap: store.isOn == null
                    ? null
                    : () => guarded(context, () => store.setPower(!on)),
              ),
            ),
          ),
          Expanded(
            child: Opacity(
              opacity: bri == null ? 0.4 : 1,
              child: IgnorePointer(
                ignoring: bri == null,
                child: Knob(
                  value: (bri ?? 128).clamp(1, 255).toDouble(),
                  min: 1,
                  max: 255,
                  size: 76,
                  accent: accent,
                  label: 'Brightness',
                  onChanged: (v) => store.setBrightness(v.round()),
                ),
              ),
            ),
          ),
          Expanded(
            child: _Labelled(
              label: 'Night light',
              child: ChunkyButton(
                key: const ValueKey('nightlight'),
                semantics: 'Night light',
                lit: store.nightlightOn,
                litColor: Lb.phosphor,
                icon: Icons.bedtime_sharp,
                onTap: store.isConnected
                    ? () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => NightlightSheet(store: store),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      const SizedBox(height: 6),
      MonoLabel(label),
    ],
  );
}

/// A raised, square hardware key with an LED that lights when [lit].
class ChunkyButton extends StatelessWidget {
  const ChunkyButton({
    super.key,
    required this.icon,
    required this.lit,
    required this.onTap,
    this.litColor = Lb.ok,
    this.semantics,
    this.size = 76,
  });

  final IconData icon;
  final bool lit;
  final VoidCallback? onTap;
  final Color litColor;
  final String? semantics;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: lit,
    label: semantics,
    child: GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      child: AnimatedContainer(
        duration: Lb.fast,
        curve: Lb.ease,
        width: size,
        height: size,
        decoration: BoxDecoration(
          // Flat key; a lit one takes a faint wash of its LED colour.
          color: lit ? Color.lerp(Lb.raised, litColor, 0.08) : Lb.raised,
          borderRadius: BorderRadius.circular(Lb.rControl),
          border: Border.all(color: lit ? litColor.withValues(alpha: 0.5) : Lb.line),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 28, color: onTap == null ? Lb.text3 : (lit ? Lb.text : Lb.text2)),
            Positioned(top: 10, right: 10, child: StatusDot(on: lit, color: litColor)),
          ],
        ),
      ),
    ),
  );
}

/// WLED's night light: dims to a target over a duration, then (at target 0)
/// switches off. Modes per json.cpp "nl": 0 instant, 1 fade, 3 sunrise.
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
    // Fading needs the light on; the sunrise effect caps at 60 min (led.cpp
    // handleNightlight).
    final maxMin = sun ? 60.0 : 120.0;
    final minutes = _minutes.clamp(5.0, maxMin);
    final canStart = sun || !lightOff;
    final m = minutes.round();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetTitle(
              'Night light',
              subtitle: 'Your device fades out by itself, even if your phone is off.',
            ),
            SegmentedButton<int>(
              style: squareSegments,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('Fade out')),
                ButtonSegment(value: 0, label: Text('Then off')),
                ButtonSegment(value: 3, label: Text('Sunrise')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                SizedBox(width: 64, child: Text('$m min', style: LbType.bodyStrong)),
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
                        ? 'A slow sunrise over $m min.'
                        : 'A slow sunset over $m min.'
                  : lightOff
                  ? 'Switch your device on first.'
                  : _mode == 0
                  ? 'Switches off after $m min.'
                  : 'Dims to dark over $m min.',
              style: LbType.small,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (on) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _set(false, m),
                      child: const Text('Stop'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: canStart ? () => _set(true, m) : null,
                    child: Text(on ? 'Start again' : 'Start'),
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
