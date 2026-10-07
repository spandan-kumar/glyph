class WeatherPlace {
  const WeatherPlace(
    this.name,
    this.latitude,
    this.longitude, {
    this.timezone = 'auto',
  });
  final String name, timezone;
  final double latitude, longitude;
  String get key => '$latitude,$longitude,$timezone';
  bool get valid =>
      name.trim().isNotEmpty &&
      name.length <= 100 &&
      latitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.isFinite &&
      longitude.abs() <= 180 &&
      (timezone == 'auto' ||
          RegExp(r'^[A-Za-z0-9_+/-]{1,80}$').hasMatch(timezone));
  Map<String, Object> toJson() => {
    'name': name,
    'lat': latitude,
    'lon': longitude,
    'zone': timezone,
  };
  factory WeatherPlace.fromJson(Map m) {
    final p = WeatherPlace(
      m['name'] as String,
      (m['lat'] as num).toDouble(),
      (m['lon'] as num).toDouble(),
      timezone: m['zone'] as String? ?? 'auto',
    );
    if (!p.valid) throw const FormatException('Invalid place');
    return p;
  }
}

enum GlanceKind { weather, counter }

enum CounterMode { until, since }

/// Dates are civil calendar dates, never elapsed 24-hour periods across DST.
class GlanceCard {
  const GlanceCard({
    required this.id,
    required this.title,
    required this.kind,
    this.place,
    this.fahrenheit = false,
    this.date,
    this.mode = CounterMode.until,
  });
  final String id, title;
  final GlanceKind kind;
  final WeatherPlace? place;
  final bool fahrenheit;
  final DateTime? date;
  final CounterMode mode;

  bool get valid =>
      id.isNotEmpty &&
      id.length <= 80 &&
      title.trim().isNotEmpty &&
      title.length <= 64 &&
      (kind == GlanceKind.weather
          ? place?.valid == true
          : date != null && date!.year >= 1900 && date!.year <= 2200);

  int days(DateTime now) {
    final local = now.toLocal();
    final today = DateTime.utc(local.year, local.month, local.day);
    final target = DateTime.utc(date!.year, date!.month, date!.day);
    return (mode == CounterMode.until
            ? target.difference(today)
            : today.difference(target))
        .inDays;
  }

  String counterLabel(DateTime now) {
    final n = days(now);
    if (n == 0) return 'Today';
    final unit = n.abs() == 1 ? 'day' : 'days';
    if (mode == CounterMode.until) {
      return n > 0 ? '$n $unit to go' : '${-n} $unit ago';
    }
    return n > 0 ? '$n $unit since' : 'In ${-n} $unit';
  }

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    if (place != null) 'place': place!.toJson(),
    'fahrenheit': fahrenheit,
    if (date != null)
      'date':
          '${date!.year.toString().padLeft(4, '0')}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}',
    'mode': mode.name,
  };
  factory GlanceCard.fromJson(Map m) {
    DateTime? date;
    if (m['date'] case final String raw) {
      final parts = raw.split('-').map(int.parse).toList();
      if (parts.length != 3) throw const FormatException('Invalid date');
      date = DateTime.utc(parts[0], parts[1], parts[2]);
      if (date.year != parts[0] ||
          date.month != parts[1] ||
          date.day != parts[2]) {
        throw const FormatException('Invalid date');
      }
    }
    final c = GlanceCard(
      id: m['id'] as String,
      title: m['title'] as String,
      kind: GlanceKind.values.byName(m['kind'] as String),
      place: m['place'] is Map
          ? WeatherPlace.fromJson(m['place'] as Map)
          : null,
      fahrenheit: m['fahrenheit'] == true,
      date: date,
      mode: CounterMode.values.byName(m['mode'] as String? ?? 'until'),
    );
    if (!c.valid) throw const FormatException('Invalid card');
    return c;
  }
}

enum ShowEntryKind { library, creation, card }

class PhoneShowEntry {
  const PhoneShowEntry(this.kind, this.id, {this.seconds = 10});
  final ShowEntryKind kind;
  final String id;
  final int seconds;
  PhoneShowEntry withSeconds(int value) =>
      PhoneShowEntry(kind, id, seconds: value.clamp(3, 120));
  Map<String, Object> toJson() => {
    'kind': kind.name,
    'id': id,
    'seconds': seconds,
  };
  factory PhoneShowEntry.fromJson(Map m) {
    final e = PhoneShowEntry(
      ShowEntryKind.values.byName(m['kind'] as String),
      m['id'] as String,
      seconds: (m['seconds'] as num).toInt(),
    );
    if (m['seconds'] != e.seconds ||
        e.id.isEmpty ||
        e.id.length > 80 ||
        e.seconds < 3 ||
        e.seconds > 120) {
      throw const FormatException('Invalid rotation entry');
    }
    return e;
  }
}

/// A rotation of cards and looks that plays live from the phone. (Named
/// "Rotation" in the UI so it is not confused with device-side Shows; the
/// class and its stored `shows` key keep their original names.)
class PhoneShow {
  PhoneShow({
    required this.id,
    required this.title,
    required List<PhoneShowEntry> entries,
  }) : entries = List.unmodifiable(entries);
  final String id, title;
  final List<PhoneShowEntry> entries;
  bool get valid =>
      id.isNotEmpty &&
      id.length <= 80 &&
      title.trim().isNotEmpty &&
      title.length <= 64 &&
      entries.isNotEmpty &&
      entries.length <= 24 &&
      entries.every(
        (e) =>
            e.id.isNotEmpty &&
            e.id.length <= 80 &&
            e.seconds >= 3 &&
            e.seconds <= 120,
      );
  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
  factory PhoneShow.fromJson(Map m) {
    final s = PhoneShow(
      id: m['id'] as String,
      title: m['title'] as String,
      entries: [
        for (final e in m['entries'] as List) PhoneShowEntry.fromJson(e as Map),
      ],
    );
    if (!s.valid) throw const FormatException('Invalid rotation');
    return s;
  }
}
