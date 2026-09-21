enum RepeatFrequency { daily, weekly, biweekly, monthly, yearly }

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

  factory EventRecurrence.fromJson(Map<String, dynamic> json) => EventRecurrence(
        frequency: repeatFrequencyFromString(json['frequency'] as String?) ?? RepeatFrequency.weekly,
        until: json['until'] as String?,
      );

  Map<String, dynamic> toJson() => {'frequency': frequency.name, if (until != null) 'until': until};
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

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'] as String,
        date: json['date'] as String,
        title: json['title'] as String,
        location: json['location'] as String?,
        systemEventId: json['systemEventId'] as String?,
        systemCalendarId: json['systemCalendarId'] as String?,
        recurrence: json['recurrence'] != null ? EventRecurrence.fromJson(json['recurrence'] as Map<String, dynamic>) : null,
        seriesId: json['seriesId'] as String?,
        url: json['url'] as String?,
        description: json['description'] as String?,
        timeZone: json['timeZone'] as String?,
        startsAt: json['startsAt'] as String?,
        endsAt: json['endsAt'] as String?,
        uid: json['uid'] as String?,
        createdAt: json['createdAt'] as String?,
        updatedAt: json['updatedAt'] as String?,
        time: json['time'] as String?,
        duration: (json['duration'] as num).toInt(),
        color: json['color'] as String,
      );

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
