import 'package:flutter/material.dart';

import '../../../ui/design/parts.dart';
import '../../../ui/design/toggle.dart';
import '../../../ui/design/tokens.dart';
import '../../../ui/design/type.dart';
import '../../../wled/schedule.dart';
import '../device_manager.dart';
import 'common.dart';

const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Weekdays", "Every day", "Mon, Wed, Fri".
String describeDays(WledTimer t) => switch (t.weekdays) {
  WledTimer.allDays => 'Every day',
  WledTimer.weekdaysOnly => 'Weekdays',
  WledTimer.weekend => 'Weekends',
  _ => [
    for (var d = 1; d <= 7; d++)
      if (t.runsOn(d)) _dayNames[d - 1],
  ].join(', '),
};

/// ", 2 Nov – 20 Feb" when the routine only runs part of the year.
String describeDates(WledTimer t) {
  if (t.allYear) return '';
  final from = '${t.startDay} ${_months[(t.startMonth - 1).clamp(0, 11)]}';
  final to = '${t.endDay} ${_months[(t.endMonth - 1).clamp(0, 11)]}';
  return ', $from – $to';
}

/// "at 7:00", "at sunset", "30 min before sunset", "every hour at :15".
String describeTime(WledTimer t) {
  String two(int v) => v.toString().padLeft(2, '0');
  String sun(String what) => t.minute == 0
      ? 'at $what'
      : '${t.minute.abs()} min ${t.minute < 0 ? 'before' : 'after'} $what';
  return switch (t.trigger) {
    TimerTrigger.sunrise => sun('sunrise'),
    TimerTrigger.sunset => sun('sunset'),
    TimerTrigger.everyHour => 'every hour at :${two(t.minute)}',
    TimerTrigger.time => 'at ${t.hour}:${two(t.minute)}',
  };
}

/// The routine as a sentence: "Weekdays at 7:00 → Sunrise",
/// "Every day at sunset → Fireplace", "Every hour at :15 → Clock".
String describeRoutine(WledTimer t, String target) {
  final days = describeDays(t);
  final time = describeTime(t);
  final when = t.trigger == TimerTrigger.everyHour
      ? (t.weekdays == WledTimer.allDays ? 'Every hour at :${time.split(':').last}' : '$days, $time')
      : '$days $time';
  return '$when${describeDates(t)} → $target';
}

/// Routines: saved items the device switches to on its own clock.
class RoutinesSection extends StatelessWidget {
  const RoutinesSection({super.key, required this.manager});

  final DeviceManager manager;

  @override
  Widget build(BuildContext context) {
    final s = manager.schedule;
    final accent = accentOf(context);
    if (s == null) {
      return EmptyNote(
        text: manager.scheduleError != null
            ? 'Couldn\'t read your device\'s routines.'
            : 'Reading routines…',
        action: manager.scheduleError != null
            ? OutlinedButton(onPressed: manager.load, child: const Text('Try again'))
            : null,
      );
    }
    final canAdd = s.isEditable && s.timers.length < WledSchedule.maxTimers && pickable(manager).isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Note(text: 'These run on your device, even when your phone is off.', lit: true, color: accent),
        if (!s.ntpEnabled)
          const Note(
            color: Lb.phosphor,
            lit: true,
            text: 'Your device doesn\'t know the time yet. Turn on internet time in Device '
                'settings → Time & Macros so routines start on time.',
          ),
        if (!s.isEditable)
          const Note(
            color: Lb.phosphor,
            lit: true,
            text: 'Changing routines needs a newer WLED (16 or later). You can still see them here.',
          ),
        if (s.timers.any((t) => t.isSunBased) && !s.hasLocation)
          const Note(
            color: Lb.phosphor,
            lit: true,
            text: 'Sunrise and sunset need your device to know where it is — set its location in '
                'WLED firmware settings → Time & Macros.',
          ),
        RowGroup(
          children: [
            Row1(
              leading: const Icon(Icons.power_sharp, color: Lb.text2, size: 20),
              title: 'When it powers on → ${_powerOn(manager)}',
              trailing: const Icon(Icons.chevron_right_sharp, color: Lb.text3),
              onTap: () => _pickBoot(context, s),
            ),
            for (final (i, t) in s.timers.indexed)
              Row1(
                leading: Icon(
                  _icon(t.trigger),
                  size: 20,
                  color: t.enabled ? accent : Lb.text3,
                ),
                title: describeRoutine(t, keptName(manager, t.presetId)),
                onTap: s.isEditable ? () => _edit(context, s, i) : null,
                trailing: LbToggle(
                  value: t.enabled,
                  onChanged: s.isEditable
                      ? (v) => guarded(context, () {
                          final list = [...s.timers]..[i] = t.copyWith(enabled: v);
                          return manager.saveTimers(list);
                        })
                      : null,
                ),
              ),
          ],
        ),
        if (s.timers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'For example: “Every day at sunset → something calm”.',
              style: LbType.small,
            ),
          ),
        if (canAdd)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              onPressed: () => _edit(context, s, null),
              icon: const Icon(Icons.add_sharp, size: 20),
              label: const Text('New routine'),
            ),
          ),
      ],
    );
  }

  /// "Glyph intro, then Sunrise", "its usual light", "Sunrise".
  static String _powerOn(DeviceManager m) {
    final look = m.powerOnLook;
    if (m.bootIntro.installed) return look == 0 ? 'Glyph intro' : 'Glyph intro, then ${keptName(m, look)}';
    return look == 0 ? 'its usual light' : keptName(m, look);
  }

  static IconData _icon(TimerTrigger t) => switch (t) {
    TimerTrigger.sunrise => Icons.wb_sunny_sharp,
    TimerTrigger.sunset => Icons.wb_twilight_sharp,
    TimerTrigger.everyHour => Icons.update_sharp,
    TimerTrigger.time => Icons.schedule_sharp,
  };

  Future<void> _pickBoot(BuildContext context, WledSchedule s) async {
    final id = manager.powerOnLook;
    final choice = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TargetPicker(
        manager: manager,
        title: 'When it powers on',
        selected: id,
        allowNone: true,
        noneLabel: manager.bootIntro.installed ? 'Just the Glyph logo' : 'Its usual light',
      ),
    );
    if (choice == null || choice == id || !context.mounted) return;
    await guarded(context, () => manager.setBootPreset(choice), done: 'Saved to your device');
  }

  Future<void> _edit(BuildContext context, WledSchedule s, int? index) async {
    final kept = keptItems(manager);
    final first = kept.isNotEmpty ? kept.first.id : pickable(manager).first.id;
    final result = await showModalBottomSheet<RoutineEdit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RoutineEditor(
        manager: manager,
        initial: index == null ? WledTimer(presetId: first) : s.timers[index],
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
      done: result.delete ? 'Routine removed' : 'Routine saved to your device',
    );
  }
}

/// Picks what a routine (or power-on) plays.
class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.manager,
    required this.title,
    required this.selected,
    this.allowNone = false,
    this.noneLabel = 'Its usual light',
  });

  final DeviceManager manager;
  final String title;
  final int selected;
  final bool allowNone;
  final String noneLabel;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    builder: (ctx, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 24),
      children: [
        SheetTitle(title),
        RowGroup(
          children: [
            if (allowNone)
              Row1(
                title: noneLabel,
                trailing: selected == 0 ? const Icon(Icons.check_sharp) : null,
                onTap: () => Navigator.pop(ctx, 0),
              ),
            for (final p in pickable(manager))
              Row1(
                key: ValueKey(p.id),
                leading: SizedBox.square(
                  dimension: 36,
                  child: LedBezel(child: PresetThumb(manager: manager, preset: p)),
                ),
                title: keptName(manager, p.id),
                subtitle: p.isPlaylist ? 'Show' : null,
                trailing: p.id == selected ? const Icon(Icons.check_sharp) : null,
                onTap: () => Navigator.pop(ctx, p.id),
              ),
          ],
        ),
      ],
    ),
  );
}

class RoutineEdit {
  const RoutineEdit.save(WledTimer this.timer) : delete = false;
  const RoutineEdit.delete() : timer = null, delete = true;

  final WledTimer? timer;
  final bool delete;
}

/// Edits one routine: when, which days, what plays.
class RoutineEditor extends StatefulWidget {
  const RoutineEditor({
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
  State<RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<RoutineEditor> {
  late WledTimer _t = widget.initial;

  void _set(WledTimer t) => setState(() => _t = t);

  void _setTrigger(TimerTrigger tr) {
    if (tr == _t.trigger) return;
    _set(switch (tr) {
      TimerTrigger.sunrise => _t.copyWith(hour: WledTimer.sunriseHour, minute: 0),
      TimerTrigger.sunset => _t.copyWith(hour: WledTimer.sunsetHour, minute: 0),
      TimerTrigger.everyHour => _t.copyWith(hour: WledTimer.everyHourValue, minute: _t.minute.clamp(0, 59)),
      TimerTrigger.time => _t.copyWith(hour: 8, minute: 0),
    });
  }

  String? get _problem {
    if (widget.manager.preset(_t.presetId) == null) return 'Pick what to play.';
    if (_t.weekdays & WledTimer.allDays == 0) return 'Pick at least one day.';
    return _t.validate() == null ? null : 'Something about this time doesn\'t work.';
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    final err = _problem;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 24),
        children: [
          SheetTitle(
            widget.canDelete ? 'Edit routine' : 'New routine',
            subtitle: describeRoutine(_t, keptName(m, _t.presetId)),
          ),
          const MonoLabel('When'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (tr, label) in const [
                (TimerTrigger.time, 'At a time'),
                (TimerTrigger.sunrise, 'Sunrise'),
                (TimerTrigger.sunset, 'Sunset'),
                (TimerTrigger.everyHour, 'Every hour'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _t.trigger == tr,
                  onSelected: (_) => _setTrigger(tr),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ..._timeControls(),
          if (_t.isSunBased && !widget.hasLocation)
            const Note(
              color: Lb.phosphor,
              lit: true,
              text: 'Your device needs its location for this (WLED firmware settings → Time & Macros).',
            ),
          const SizedBox(height: 16),
          const MonoLabel('Days'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  showCheckmark: false,
                  label: Text(_dayLetters[d - 1]),
                  tooltip: _dayNames[d - 1],
                  selected: _t.runsOn(d),
                  onSelected: (on) => _set(
                    _t.copyWith(weekdays: on ? _t.weekdays | (1 << (d - 1)) : _t.weekdays & ~(1 << (d - 1))),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const MonoLabel('Play'),
          const SizedBox(height: 8),
          RowGroup(
            children: [
              Row1(
                title: m.preset(_t.presetId) == null ? 'Pick what to play' : keptName(m, _t.presetId),
                trailing: const Icon(Icons.chevron_right_sharp, color: Lb.text3),
                onTap: () async {
                  final id = await showModalBottomSheet<int>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => _TargetPicker(manager: m, title: 'Play', selected: _t.presetId),
                  );
                  if (id != null) _set(_t.copyWith(presetId: id));
                },
              ),
              Row1(
                title: 'All year',
                trailing: LbToggle(
                  value: _t.allYear,
                  onChanged: (v) => _set(
                    v
                        ? _t.copyWith(startMonth: 1, startDay: 1, endMonth: 12, endDay: 31)
                        : _t.copyWith(startMonth: DateTime.now().month, startDay: 1, endMonth: 12, endDay: 31),
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
              Row1(
                title: 'On',
                trailing: LbToggle(value: _t.enabled, onChanged: (v) => _set(_t.copyWith(enabled: v))),
              ),
            ],
          ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(err, style: LbType.small.copyWith(color: Lb.phosphor)),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.canDelete) ...[
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Lb.danger),
                  onPressed: () => Navigator.pop(context, const RoutineEdit.delete()),
                  child: const Text('Delete'),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: err == null ? () => Navigator.pop(context, RoutineEdit.save(_t)) : null,
                  child: const Text('Save to device'),
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
            icon: const Icon(Icons.schedule_sharp),
            label: Text('${_t.hour}:${_t.minute.toString().padLeft(2, '0')}', style: LbType.title),
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
          Text('At minute :${_t.minute.toString().padLeft(2, '0')}', style: LbType.body),
          Slider(
            value: _t.minute.clamp(0, 59).toDouble(),
            max: 59,
            divisions: 59,
            onChanged: (v) => _set(_t.copyWith(minute: v.round())),
          ),
        ];
      case TimerTrigger.sunrise:
      case TimerTrigger.sunset:
        return [
          Text(_capitalised(describeTime(_t)), style: LbType.body),
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
  const _DateRow({required this.label, required this.month, required this.day, required this.onChanged});

  final String label;
  final int month, day;
  final void Function(int month, int day) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
    child: Row(
      children: [
        SizedBox(width: 52, child: Text(label, style: LbType.body)),
        Expanded(
          child: DropdownButtonFormField<int>(
            borderRadius: BorderRadius.circular(Lb.rControl),
            initialValue: day.clamp(1, 31),
            items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d'))],
            onChanged: (v) => v == null ? null : onChanged(month, v),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int>(
            borderRadius: BorderRadius.circular(Lb.rControl),
            initialValue: month.clamp(1, 12),
            items: [
              for (var mo = 1; mo <= 12; mo++) DropdownMenuItem(value: mo, child: Text(_months[mo - 1])),
            ],
            onChanged: (v) => v == null ? null : onChanged(v, day),
          ),
        ),
      ],
    ),
  );
}

String _capitalised(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
