import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../logic/event_details.dart';
import '../logic/recurrence.dart';
import '../models/calendar_event.dart';

class LiveCalendarEvent {
  const LiveCalendarEvent(this.event, this.start, this.end);
  final CalendarEvent event;
  final DateTime start, end;
  String get id => '${event.id}@${event.date}';
  Map<String, dynamic> get payload => {
    'eventID': id,
    'title': event.title,
    'color': event.color,
    'start': start.millisecondsSinceEpoch / 1000,
    'end': end.millisecondsSinceEpoch / 1000,
  };
}

List<LiveCalendarEvent> currentLiveEvents(
  EventMap events,
  tz.Location zone,
  DateTime now,
) {
  final today = zonedParts(now, zone).date;
  final previous = zonedParts(now.subtract(const Duration(days: 7)), zone).date;
  final expanded = expandEvents(events, previous, today, zone);
  final current = <LiveCalendarEvent>[];
  for (final event in expanded.values.expand((items) => items)) {
    if (event.isAllDay || event.title.trim().isEmpty || event.duration <= 0) {
      continue;
    }
    try {
      final start = event.startsAt != null
          ? DateTime.parse(event.startsAt!)
          : wallTimeToDate(event.date, event.time!, zone);
      final end = event.endsAt != null
          ? DateTime.parse(event.endsAt!)
          : start.add(Duration(minutes: event.duration));
      if (!now.isBefore(start) && now.isBefore(end)) {
        current.add(LiveCalendarEvent(event, start, end));
      }
    } on FormatException {
      continue;
    }
  }
  current.sort((a, b) => a.end.compareTo(b.end));
  return current;
}

/// Returns ongoing events and events beginning within [lookAhead].
List<LiveCalendarEvent> liveActivityCandidates(
  EventMap events,
  tz.Location zone,
  DateTime now, {
  Duration lookAhead = const Duration(minutes: 10),
}) {
  final today = zonedParts(now, zone).date;
  final previous = zonedParts(now.subtract(const Duration(days: 7)), zone).date;
  final expanded = expandEvents(events, previous, today, zone);
  final candidates = <LiveCalendarEvent>[];
  for (final event in expanded.values.expand((items) => items)) {
    if (event.isAllDay || event.title.trim().isEmpty || event.duration <= 0) {
      continue;
    }
    try {
      final start = event.startsAt != null
          ? DateTime.parse(event.startsAt!)
          : wallTimeToDate(event.date, event.time!, zone);
      final end = event.endsAt != null
          ? DateTime.parse(event.endsAt!)
          : start.add(Duration(minutes: event.duration));
      if (!now.isBefore(start.subtract(lookAhead)) && now.isBefore(end)) {
        candidates.add(LiveCalendarEvent(event, start, end));
      }
    } on FormatException {
      continue;
    }
  }
  candidates.sort((a, b) {
    final aStarted = !now.isBefore(a.start);
    final bStarted = !now.isBefore(b.start);
    if (aStarted != bStarted) return aStarted ? -1 : 1;
    return a.start.compareTo(b.start);
  });
  return candidates;
}

List<LiveCalendarEvent> automaticLiveEvents(
  EventMap events,
  tz.Location zone,
  DateTime now,
) {
  final today = zonedParts(now, zone).date;
  return liveActivityCandidates(
        events,
        zone,
        now,
        lookAhead: const Duration(hours: 24),
      )
      .where(
        (event) => zonedParts(event.start, zone).date.compareTo(today) <= 0,
      )
      .toList(growable: false);
}

class LiveActivity {
  static const _channel = MethodChannel('calendar_app/live_activity');
  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  static bool get isSupportedPlatform => isIOS || isAndroid || isMacOS;

  static Future<void> openNotificationSettings() async {
    if (isAndroid) await _channel.invokeMethod<void>('openSettings');
  }

  static Future<
    ({
      bool supported,
      bool enabled,
      bool scheduledStartSupported,
      List<String> eventIDs,
    })
  >
  status() async {
    if (!isSupportedPlatform) {
      return (
        supported: false,
        enabled: false,
        scheduledStartSupported: false,
        eventIDs: const <String>[],
      );
    }
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>('status');
      return (
        supported: value?['supported'] == true,
        enabled: value?['enabled'] == true,
        scheduledStartSupported: value?['scheduledStartSupported'] == true,
        eventIDs: (value?['eventIDs'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
      );
    } on MissingPluginException {
      return (
        supported: false,
        enabled: false,
        scheduledStartSupported: false,
        eventIDs: const <String>[],
      );
    }
  }

  static Future<void> start(LiveCalendarEvent event) =>
      _channel.invokeMethod('start', event.payload);
  static Future<void> syncAutomatic(List<LiveCalendarEvent> events) =>
      _channel.invokeMethod('syncAutomatic', {
        'events': events.map((event) => event.payload).toList(),
      });
  static Future<void> schedule(LiveCalendarEvent event) =>
      _channel.invokeMethod('schedule', event.payload);
  static Future<void> update(LiveCalendarEvent event) =>
      _channel.invokeMethod('update', event.payload);
  static Future<void> end() async {
    if (isSupportedPlatform) {
      try {
        await _channel.invokeMethod<void>('end');
      } on MissingPluginException {
        /* Older installed build. */
      }
    }
  }
}
