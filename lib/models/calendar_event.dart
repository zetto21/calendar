import 'dart:convert';

enum RepeatFrequency { daily, weekly, biweekly, monthly, yearly }

/// Strict calendar keys avoid DateTime's normalization of invalid dates/times.
bool isValidCalendarDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      parsed.year == int.parse(value.substring(0, 4)) &&
      parsed.month == int.parse(value.substring(5, 7)) &&
      parsed.day == int.parse(value.substring(8, 10));
}

bool isValidCalendarTime(String value) =>
    RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

String? _eventString(
  Map<String, dynamic> json,
  String key, {
  bool required = false,
  int maxLength = 16 * 1024,
}) {
  final value = json[key];
  if (value == null && !required) return null;
  if (value is! String ||
      value.length > maxLength ||
      value.contains('\u0000') ||
      (required && value.trim().isEmpty)) {
    throw const FormatException('일정 데이터 형식이 올바르지 않습니다.');
  }
  return value;
}

String? _eventTimestamp(Map<String, dynamic> json, String key) {
  final value = _eventString(json, key, maxLength: 64);
  if (value != null &&
      (!RegExp(
            r'^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:[zZ]|[+-](?:[01]\d|2[0-3]):?[0-5]\d)?$',
          ).hasMatch(value) ||
          !isValidCalendarDate(value.substring(0, 10)) ||
          DateTime.tryParse(value) == null)) {
    throw const FormatException('일정 날짜 형식이 올바르지 않습니다.');
  }
  return value;
}

RepeatFrequency? repeatFrequencyFromString(String? value) {
  for (final freq in RepeatFrequency.values) {
    if (freq.name == value) return freq;
  }
  return null;
}

class EventRecurrence {
  final RepeatFrequency frequency;
  final String? until; // "YYYY-MM-DD"

  const EventRecurrence({required this.frequency, this.until});

  factory EventRecurrence.fromJson(Map<String, dynamic> json) {
    final frequency = repeatFrequencyFromString(
      _eventString(json, 'frequency'),
    );
    final until = _eventString(json, 'until');
    if (frequency == null || (until != null && !isValidCalendarDate(until))) {
      throw const FormatException('반복 일정 형식이 올바르지 않습니다.');
    }
    return EventRecurrence(frequency: frequency, until: until);
  }

  Map<String, dynamic> toJson() => {
    'frequency': frequency.name,
    if (until != null) 'until': until,
  };
}

/// Mirrors calendar_app/lib/types.ts CalendarEvent/EventDraft.
class CalendarEvent {
  final String id;
  final String date; // "YYYY-MM-DD"
  final String title;
  final String? location;
  final String? systemEventId;
  final String? systemCalendarId;
  final EventRecurrence? recurrence;
  final String? seriesId; // display-only link back to the recurring series
  final String? url;
  final String? description;
  final String? timeZone;
  final String? startsAt;
  final String? endsAt;
  final String? uid;
  final String? createdAt;
  final String? updatedAt;
  final String? time; // "HH:MM", null = all-day
  final int duration; // minutes
  final String color;

  const CalendarEvent({
    required this.id,
    required this.date,
    required this.title,
    this.location,
    this.systemEventId,
    this.systemCalendarId,
    this.recurrence,
    this.seriesId,
    this.url,
    this.description,
    this.timeZone,
    this.startsAt,
    this.endsAt,
    this.uid,
    this.createdAt,
    this.updatedAt,
    this.time,
    required this.duration,
    required this.color,
  });

  bool get isAllDay => time == null;

  CalendarEvent copyWith({
    String? id,
    String? date,
    String? title,
    String? location,
    String? systemEventId,
    String? systemCalendarId,
    EventRecurrence? recurrence,
    bool clearRecurrence = false,
    String? seriesId,
    bool clearSeriesId = false,
    String? url,
    String? description,
    String? timeZone,
    String? startsAt,
    bool clearStartsAt = false,
    String? endsAt,
    bool clearEndsAt = false,
    String? uid,
    String? createdAt,
    String? updatedAt,
    String? time,
    bool clearTime = false,
    int? duration,
    String? color,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      date: date ?? this.date,
      title: title ?? this.title,
      location: location ?? this.location,
      systemEventId: systemEventId ?? this.systemEventId,
      systemCalendarId: systemCalendarId ?? this.systemCalendarId,
      recurrence: clearRecurrence ? null : (recurrence ?? this.recurrence),
      seriesId: clearSeriesId ? null : (seriesId ?? this.seriesId),
      url: url ?? this.url,
      description: description ?? this.description,
      timeZone: timeZone ?? this.timeZone,
      startsAt: clearStartsAt ? null : (startsAt ?? this.startsAt),
      endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
      uid: uid ?? this.uid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      time: clearTime ? null : (time ?? this.time),
      duration: duration ?? this.duration,
      color: color ?? this.color,
    );
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final date = _eventString(json, 'date', required: true)!;
    final time = _eventString(json, 'time');
    final duration = json['duration'];
    final color = _eventString(json, 'color', required: true)!;
    final recurrence = json['recurrence'];
    if (!isValidCalendarDate(date) ||
        (time != null && !isValidCalendarTime(time)) ||
        duration is! num ||
        !duration.isFinite ||
        duration != duration.toInt() ||
        duration < 0 ||
        duration > 366 * 24 * 60 ||
        !RegExp(r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(color) ||
        (recurrence != null && recurrence is! Map<String, dynamic>) ||
        utf8.encode(jsonEncode(json)).length > 16 * 1024) {
      throw const FormatException('일정 날짜, 시간 또는 데이터 형식이 올바르지 않습니다.');
    }
    return CalendarEvent(
      id: _eventString(json, 'id', required: true, maxLength: 256)!,
      date: date,
      title: _eventString(json, 'title', required: true)!,
      location: _eventString(json, 'location'),
      systemEventId: _eventString(json, 'systemEventId'),
      systemCalendarId: _eventString(json, 'systemCalendarId'),
      recurrence: recurrence == null
          ? null
          : EventRecurrence.fromJson(recurrence as Map<String, dynamic>),
      seriesId: _eventString(json, 'seriesId'),
      url: _eventString(json, 'url'),
      description: _eventString(json, 'description'),
      timeZone: _eventString(json, 'timeZone'),
      startsAt: _eventTimestamp(json, 'startsAt'),
      endsAt: _eventTimestamp(json, 'endsAt'),
      uid: _eventString(json, 'uid'),
      createdAt: _eventTimestamp(json, 'createdAt'),
      updatedAt: _eventTimestamp(json, 'updatedAt'),
      time: time,
      duration: duration.toInt(),
      color: color,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'title': title,
    if (location != null) 'location': location,
    if (systemEventId != null) 'systemEventId': systemEventId,
    if (systemCalendarId != null) 'systemCalendarId': systemCalendarId,
    if (recurrence != null) 'recurrence': recurrence!.toJson(),
    if (seriesId != null) 'seriesId': seriesId,
    if (url != null) 'url': url,
    if (description != null) 'description': description,
    if (timeZone != null) 'timeZone': timeZone,
    if (startsAt != null) 'startsAt': startsAt,
    if (endsAt != null) 'endsAt': endsAt,
    if (uid != null) 'uid': uid,
    if (createdAt != null) 'createdAt': createdAt,
    if (updatedAt != null) 'updatedAt': updatedAt,
    if (time != null) 'time': time,
    'duration': duration,
    'color': color,
  };
}

/// date key ("YYYY-MM-DD") -> events on that date.
typedef EventMap = Map<String, List<CalendarEvent>>;

enum ViewMode { day, week, month, list }

/// Holidays, solar terms, anniversaries and imported events are read-only.
bool isMovableEvent(CalendarEvent event) =>
    !event.id.startsWith('holiday:') &&
    !event.id.startsWith('solarTerm:') &&
    !event.id.startsWith('anniversary:') &&
    !event.id.startsWith('import:');
