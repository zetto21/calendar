import 'package:flutter/services.dart';

import '../models/calendar_event.dart';

class DeviceCalendar {
  const DeviceCalendar({
    required this.id,
    required this.title,
    required this.source,
  });
  final String id;
  final String title;
  final String source;
}

/// Apple EventKit editor and synchronization platform channel.
class EventKit {
  EventKit._();
  static const _channel = MethodChannel('calendar_app/eventkit');

  /// Null event with saved=true means Calendar access was not granted.
  static Future<({bool saved, CalendarEvent? event})> presentEventEditor(
    DateTime date,
    String? time,
  ) async {
    final parts = time?.split(':');
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      parts == null ? 0 : int.parse(parts[0]),
      parts == null ? 0 : int.parse(parts[1]),
    );
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'presentEventEditor',
      {
        'date':
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'isAllDay': time == null,
        'startsAt': start.toUtc().toIso8601String(),
        'duration': 60,
      },
    );
    final raw = response?['event'];
    return (
      saved: response?['saved'] == true,
      event: raw is Map ? _fromNative(Map<String, dynamic>.from(raw)) : null,
    );
  }

  static Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> requestAccess() async {
    try {
      return await _channel.invokeMethod<bool>('requestAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Creates the event in the default EventKit calendar. Returns the new
  /// EKEvent identifier (to store as CalendarEvent.systemEventId), or null on failure.
  static Future<String?> createEvent(CalendarEvent event) async {
    try {
      return await _channel.invokeMethod<String>('createEvent', _toArgs(event));
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> updateEvent(CalendarEvent event) async {
    if (event.systemEventId == null) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'updateEvent',
        _toArgs(event),
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> deleteEvent(String systemEventId) async {
    try {
      final ok = await _channel.invokeMethod<bool>('deleteEvent', {
        'systemEventId': systemEventId,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Fetches EventKit events in [start, end) (inclusive start, exclusive end,
  /// ISO 8601 UTC strings) for two-way sync (lib/useSystemEvents.ios.ts).
  static Future<List<CalendarEvent>> fetchEvents(
    DateTime start,
    DateTime end, {
    List<String>? calendarIds,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('fetchEvents', {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        if (calendarIds != null) 'calendarIds': calendarIds,
      });
      if (raw == null) return [];
      return raw
          .map((item) => _fromNative(Map<String, dynamic>.from(item as Map)))
          .toList();
    } on PlatformException {
      return [];
    }
  }

  static Future<List<DeviceCalendar>> fetchCalendars() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('fetchCalendars');
      return (raw ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map(
            (item) => DeviceCalendar(
              id: item['id'] as String,
              title: item['title'] as String,
              source: item['source'] as String? ?? '',
            ),
          )
          .toList();
    } on PlatformException {
      return [];
    }
  }

  static Map<String, dynamic> _toArgs(CalendarEvent event) => {
    'systemEventId': event.systemEventId,
    'title': event.title,
    'location': event.location,
    'notes': event.description,
    'url': event.url,
    'isAllDay': event.isAllDay,
    'startsAt': event.startsAt,
    'endsAt': event.endsAt,
    'date': event.date,
    'time': event.time,
    'duration': event.duration,
    'recurrenceFrequency': event.recurrence?.frequency.name,
    'recurrenceUntil': event.recurrence?.until,
  };

  static CalendarEvent _fromNative(Map<String, dynamic> map) {
    final start = DateTime.parse(map['startsAt'] as String).toLocal();
    final date =
        map['date'] as String? ??
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final isAllDay = map['isAllDay'] as bool? ?? false;
    return CalendarEvent(
      id: map['systemEventId'] as String,
      date: date,
      title: map['title'] as String? ?? '',
      location: map['location'] as String?,
      systemEventId: map['systemEventId'] as String,
      systemCalendarId: map['systemCalendarId'] as String?,
      description: map['notes'] as String?,
      url: map['url'] as String?,
      startsAt: map['startsAt'] as String?,
      endsAt: map['endsAt'] as String?,
      updatedAt: map['updatedAt'] as String?,
      time: isAllDay
          ? null
          : map['time'] as String? ??
                '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
      duration: (map['durationMinutes'] as num?)?.toInt() ?? 60,
      color: map['color'] as String? ?? '#3B82F6',
    );
  }
}
