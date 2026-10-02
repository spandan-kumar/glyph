import 'package:flutter/material.dart';

import '../../../ui/theme.dart';
import '../../../wled/schedule.dart';
import '../device_manager.dart';
import 'common.dart';

const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// WLED timers and the boot preset. They run on the matrix's own clock.
class SchedulesTab extends StatelessWidget {
  const SchedulesTab({super.key, required this.manager});

  final DeviceManager manager;

  @override
  Widget build(BuildContext context) {
    final s = manager.schedule;
    return RefreshIndicator(
      onRefresh: manager.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const InfoBanner(
            icon: Icons.schedule_rounded,
            text: 'Schedules run on the matrix itself, even when your phone is off or away.',
          ),
          if (s == null)
            manager.scheduleError != null
                ? InfoBanner(
                    text: 'Couldn\'t read the schedule: ${manager.scheduleError}',
                    icon: Icons.error_outline,
                    color: GlyphColors.danger,
                  )
                : const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
          else ...[
            if (!s.ntpEnabled)
              const InfoBanner(
                icon: Icons.access_time,
                color: GlyphColors.warning,
                text:
                    'Internet time (NTP) is off on this matrix, so its clock may be wrong. '
                    'Turn it on in WLED → Settings → Time & Macros.',
              ),
            if (!s.isEditable)
              const InfoBanner(
                icon: Icons.system_update_alt,
                color: GlyphColors.warning,
                text: 'Editing schedules needs WLED 16 or newer. They are shown read-only.',
              ),
            _BootPreset(manager: manager, schedule: s),
            SectionLabel(
              'Timers (${s.timers.length}/${WledSchedule.maxTimers})',
              trailing: s.isEditable && s.timers.length < WledSchedule.maxTimers
                  ? TextButton.icon(
                      onPressed: manager.playable.isEmpty ? null : () => _edit(context, s, null),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    )
                  : null,
            ),
            if (s.timers.isEmpty)
              EmptyNote(
                icon: Icons.alarm_add_outlined,
                text: manager.presets.isEmpty
                    ? 'Save a preset first, then schedule it here.'
                    : 'No schedules. Add one to switch presets at set times, '
                          'e.g. a calm preset at sunset and off at midnight.',
              ),
            for (final (i, t) in s.timers.indexed)
              Tile(
                leading: Icon(
                  _icon(t.trigger),
                  color: t.enabled ? GlyphColors.accent : GlyphColors.textMuted,
                ),
                title: describeTime(t),
                subtitle: '${describeDays(t)} → ${manager.presetName(t.presetId)}',
                onTap: s.isEditable ? () => _edit(context, s, i) : null,
                trailing: Switch(
                  value: t.enabled,
                  onChanged: s.isEditable
                      ? (v) => guarded(context, () {
                          final list = [...s.timers]..[i] = t.copyWith(enabled: v);
                          return manager.saveTimers(list);
                        })
                      : null,
                ),
              ),
            if (s.timers.any((t) => t.isSunBased) && !s.hasLocation)
              const InfoBanner(
                icon: Icons.wb_twilight,
                color: GlyphColors.warning,
                text:
                    'Sunrise/sunset timers need the matrix\'s location: set latitude and '
                    'longitude in WLED → Settings → Time & Macros.',
              ),
          ],
        ],
      ),
    );
  }

  static IconData _icon(TimerTrigger t) => switch (t) {
    TimerTrigger.sunrise => Icons.wb_sunny_outlined,
    TimerTrigger.sunset => Icons.wb_twilight,
    TimerTrigger.everyHour => Icons.update,
    TimerTrigger.time => Icons.alarm,
  };

  Future<void> _edit(BuildContext context, WledSchedule s, int? index) async {
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TimerEditor(
        manager: manager,
        initial: index == null ? WledTimer(presetId: manager.playable.first.id) : s.timers[index],
        canDelete: index != null,
        hasLocation: s.hasLocation,
      ),
    );
    if (result == null || !context.mounted) return;
    final list = [...s.timers];
    if (result.delete) {
      list.removeAt(index!);
    } else if (index == null) {
      list.add(result.timer!);
    } else {
      list[index] = result.timer!;
    }
    await guarded(
      context,
      () => manager.saveTimers(list),
      done: result.delete ? 'Schedule removed' : 'Schedule saved to the matrix',
    );
  }
}

String describeTime(WledTimer t) {
  String two(int v) => v.toString().padLeft(2, '0');
  String offset(String what) => t.minute == 0
      ? 'At $what'
      : '${t.minute.abs()} min ${t.minute < 0 ? 'before' : 'after'} $what';
  return switch (t.trigger) {
    TimerTrigger.sunrise => offset('sunrise'),
    TimerTrigger.sunset => offset('sunset'),
    TimerTrigger.everyHour => 'Every hour at :${two(t.minute)}',
    TimerTrigger.time => '${two(t.hour)}:${two(t.minute)}',
  };
}

String describeDays(WledTimer t) {
  final days = switch (t.weekdays) {
    WledTimer.allDays => 'Every day',
    WledTimer.weekdaysOnly => 'Weekdays',
    WledTimer.weekend => 'Weekends',
    _ => [
      for (var d = 1; d <= 7; d++)
        if (t.runsOn(d)) _dayNames[d - 1],
    ].join(' '),
  };
  if (t.allYear) return days;
  final from = '${t.startDay} ${_months[(t.startMonth - 1).clamp(0, 11)]}';
  final to = '${t.endDay} ${_months[(t.endMonth - 1).clamp(0, 11)]}';
  return '$days, $from–$to';
}

class _BootPreset extends StatelessWidget {
  const _BootPreset({required this.manager, required this.schedule});

  final DeviceManager manager;
  final WledSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final id = schedule.bootPreset;
    return Tile(
      leading: const Icon(Icons.power_rounded, color: GlyphColors.primary),
      title: 'At power-on',
      subtitle: id == 0 ? 'Restore defaults (no preset)' : manager.presetName(id),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final choice = await showModalBottomSheet<int>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            builder: (ctx, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                const Text(
                  'Play at power-on',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Tile(title: 'No preset', highlight: id == 0, onTap: () => Navigator.pop(ctx, 0)),
                for (final p in manager.presets)
                  Tile(
                    leading: PresetThumb(manager: manager, preset: p, size: 36),
                    title: p.name,
                    subtitle: manager.describe(p),
                    highlight: p.id == id,
                    onTap: () => Navigator.pop(ctx, p.id),
                  ),
              ],
            ),
          ),
        );
        if (choice == null || choice == id || !context.mounted) return;
        await guarded(context, () => manager.setBootPreset(choice), done: 'Power-on preset saved');
      },
    );
  }
}

class _EditResult {
  const _EditResult.save(WledTimer this.timer) : delete = false;
  const _EditResult.delete() : timer = null, delete = true;

  final WledTimer? timer;
  final bool delete;
}

class TimerEditor extends StatefulWidget {
  const TimerEditor({
    super.key,
    required this.manager,
    required this.initial,
    this.canDelete = false,
    this.hasLocation = true,
  });

  final DeviceManager manager;
  final WledTimer initial;
  final bool canDelete;
  final bool hasLocation;

  @override
  State<TimerEditor> createState() => _TimerEditorState();
}

class _TimerEditorState extends State<TimerEditor> {
  late WledTimer _t = widget.initial;

  void _set(WledTimer t) => setState(() => _t = t);

  void _setTrigger(TimerTrigger tr) {
    final was = _t.trigger;
    if (tr == was) return;
    _set(switch (tr) {
      TimerTrigger.sunrise => _t.copyWith(hour: WledTimer.sunriseHour, minute: 0),
      TimerTrigger.sunset => _t.copyWith(hour: WledTimer.sunsetHour, minute: 0),
      TimerTrigger.everyHour => _t.copyWith(
        hour: WledTimer.everyHourValue,
        minute: _t.minute.clamp(0, 59),
      ),
      TimerTrigger.time => _t.copyWith(hour: 8, minute: 0),
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    final err = _t.validate();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            widget.canDelete ? 'Edit schedule' : 'New schedule',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TimerTrigger>(
            initialValue: _t.trigger,
            decoration: const InputDecoration(labelText: 'When'),
            items: const [
              DropdownMenuItem(value: TimerTrigger.time, child: Text('At a time')),
              DropdownMenuItem(value: TimerTrigger.sunrise, child: Text('Sunrise')),
              DropdownMenuItem(value: TimerTrigger.sunset, child: Text('Sunset')),
              DropdownMenuItem(value: TimerTrigger.everyHour, child: Text('Every hour')),
            ],
            onChanged: (v) => v == null ? null : _setTrigger(v),
          ),
          const SizedBox(height: 12),
          ..._timeControls(),
          if (_t.isSunBased && !widget.hasLocation)
            const InfoBanner(
              icon: Icons.location_off_outlined,
              color: GlyphColors.warning,
              text: 'Set the location in WLED → Settings → Time & Macros, or this won\'t run.',
            ),
          const SectionLabel('Days'),
          Wrap(
            spacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  showCheckmark: false,
                  label: Text(_dayLetters[d - 1]),
                  tooltip: _dayNames[d - 1],
                  selected: _t.runsOn(d),
                  onSelected: (on) => _set(
                    _t.copyWith(
                      weekdays: on ? _t.weekdays | (1 << (d - 1)) : _t.weekdays & ~(1 << (d - 1)),
                    ),
                  ),
                ),
            ],
          ),
          const SectionLabel('Preset'),
          DropdownButtonFormField<int>(
            initialValue: m.preset(_t.presetId) != null ? _t.presetId : null,
            isExpanded: true,
            hint: const Text('Pick a preset'),
            items: [
              for (final p in m.presets)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => v == null ? null : _set(_t.copyWith(presetId: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('All year'),
            value: _t.allYear,
            onChanged: (v) => _set(
              v
                  ? _t.copyWith(startMonth: 1, startDay: 1, endMonth: 12, endDay: 31)
                  : _t.copyWith(
                      startMonth: DateTime.now().month,
                      startDay: 1,
                      endMonth: 12,
                      endDay: 31,
                    ),
            ),
          ),
          if (!_t.allYear) ...[
            _DateRow(
              label: 'From',
              month: _t.startMonth,
              day: _t.startDay,
              onChanged: (mo, d) => _set(_t.copyWith(startMonth: mo, startDay: d)),
            ),
            _DateRow(
              label: 'Until',
              month: _t.endMonth,
              day: _t.endDay,
              onChanged: (mo, d) => _set(_t.copyWith(endMonth: mo, endDay: d)),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            value: _t.enabled,
            onChanged: (v) => _set(_t.copyWith(enabled: v)),
          ),
          if (err != null)
            Text(err, style: const TextStyle(color: GlyphColors.warning, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (widget.canDelete)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: GlyphColors.danger),
                  onPressed: () => Navigator.pop(context, const _EditResult.delete()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: err == null
                      ? () => Navigator.pop(context, _EditResult.save(_t))
                      : null,
                  child: const Text('Save to matrix', textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _timeControls() {
    switch (_t.trigger) {
      case TimerTrigger.time:
        return [
          OutlinedButton.icon(
            icon: const Icon(Icons.access_time),
            label: Text(describeTime(_t), style: const TextStyle(fontSize: 20)),
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: _t.hour, minute: _t.minute),
              );
              if (picked != null) _set(_t.copyWith(hour: picked.hour, minute: picked.minute));
            },
          ),
        ];
      case TimerTrigger.everyHour:
        return [
          Row(
            children: [
              Text('At minute :${_t.minute.toString().padLeft(2, '0')}'),
              Expanded(
                child: Slider(
                  value: _t.minute.clamp(0, 59).toDouble(),
                  max: 59,
                  divisions: 59,
                  onChanged: (v) => _set(_t.copyWith(minute: v.round())),
                ),
              ),
            ],
          ),
        ];
      case TimerTrigger.sunrise:
      case TimerTrigger.sunset:
        return [
          Text(describeTime(_t)),
          Slider(
            value: _t.minute.clamp(-WledTimer.maxSunOffset, WledTimer.maxSunOffset).toDouble(),
            min: -WledTimer.maxSunOffset.toDouble(),
            max: WledTimer.maxSunOffset.toDouble(),
            divisions: 48,
            label: '${_t.minute} min',
            onChanged: (v) => _set(_t.copyWith(minute: v.round())),
          ),
        ];
    }
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.month,
    required this.day,
    required this.onChanged,
  });

  final String label;
  final int month, day;
  final void Function(int month, int day) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(width: 56, child: Text(label)),
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: day.clamp(1, 31),
            items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d'))],
            onChanged: (v) => v == null ? null : onChanged(month, v),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: month.clamp(1, 12),
            items: [
              for (var mo = 1; mo <= 12; mo++)
                DropdownMenuItem(value: mo, child: Text(_months[mo - 1])),
            ],
            onChanged: (v) => v == null ? null : onChanged(v, day),
          ),
        ),
      ],
    ),
  );
}
