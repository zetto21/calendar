import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../logic/date_utils.dart' as dates;
import '../logic/event_details.dart';
import '../logic/recurrence.dart';
import '../models/calendar_event.dart';

/// Build a rolling week of reminders, independently of the visible month.
List<Map<String, Object>> buildWindowsReminders(
  EventMap events,
  tz.Location zone,
  DateTime now,
  String account,
) {
  final local = tz.TZDateTime.from(now, zone);
  final horizon = now.add(const Duration(days: 7));
  final expanded = expandEvents(
    events,
    dates.toDateKey(local),
    dates.toDateKey(tz.TZDateTime.from(horizon, zone)),
    zone,
  );
  final reminders = <String, Map<String, Object>>{};
  for (final event in expanded.values.expand((items) => items)) {
    if (event.time == null ||
        event.id.startsWith('holiday:') ||
        event.id.startsWith('solarTerm:') ||
        event.id.startsWith('anniversary:')) {
      continue;
    }
    try {
      final start = event.startsAt != null
          ? DateTime.parse(event.startsAt!)
          : wallTimeToDate(event.date, event.time!, zone);
      if (start.isAfter(horizon)) continue;
      final expires = start.add(
        Duration(minutes: event.duration.clamp(1, 1440)),
      );
      if (!expires.isAfter(now)) continue;
      final due = start.subtract(const Duration(minutes: 10));
      final title = event.title.length > 120
          ? event.title.substring(0, 120)
          : event.title;
      final location = event.location?.trim() ?? '';
      final body =
          '${event.date} ${event.time} 시작 · 10분 전'
          '${location.isEmpty ? '' : '\n${location.length > 120 ? location.substring(0, 120) : location}'}';
      final id = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                account,
                event.id,
                start.toUtc().toIso8601String(),
                title,
                body,
              ]),
            ),
          )
          .toString()
          .substring(0, 16);
      reminders[id] = {
        'id': id,
        'title': title,
        'body': body,
        'at': due.millisecondsSinceEpoch,
        'expires': expires.millisecondsSinceEpoch,
      };
    } on FormatException {
      // A malformed imported date must not prevent all other reminders.
    }
  }
  final sorted = reminders.values.toList()
    ..sort((a, b) => (a['at'] as int).compareTo(b['at'] as int));
  // Keep IDs of recently delivered reminders so Windows snooze survives refresh.
  return sorted.take(256).toList();
}

class WindowsEventReminders {
  static const channel = MethodChannel('calendar/windows_event_reminders');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static int _generation = 0;
  static Future<void> _queue = Future.value();
  static String? _lastPlan;

  static String _preferenceKey(String account) =>
      'calendar.windows-reminders.${sha256.convert(utf8.encode(account))}.enabled';

  static Future<bool> enabled(String account) async =>
      (await SharedPreferences.getInstance()).getBool(
        _preferenceKey(account),
      ) ??
      true;

  static Future<void> setEnabled(String account, bool value) async {
    if (!await (await SharedPreferences.getInstance()).setBool(
      _preferenceKey(account),
      value,
    )) {
      throw StateError('알림 설정을 저장하지 못했습니다.');
    }
  }

  static Future<void> update({
    required String account,
    required EventMap events,
    required tz.Location zone,
  }) async {
    if (!supported) return;
    final generation = ++_generation;
    final active = await enabled(account);
    if (generation != _generation) return;
    final plan = active
        ? buildWindowsReminders(events, zone, DateTime.now(), account)
        : const <Map<String, Object>>[];
    await _apply(generation, plan);
  }

  static Future<void> clear() async {
    if (!supported) return;
    await _apply(++_generation, const [], clear: true);
  }

  static Future<void> _apply(
    int generation,
    List<Map<String, Object>> plan, {
    bool clear = false,
  }) {
    final signature = jsonEncode(plan);
    final operation = _queue.then((_) async {
      if (generation != _generation || (!clear && signature == _lastPlan)) {
        return;
      }
      try {
        await channel.invokeMethod<void>(clear ? 'clear' : 'schedule', plan);
        _lastPlan = signature;
      } on PlatformException catch (error) {
        debugPrint('Windows reminder update failed: ${error.code}');
      } on MissingPluginException {
        // Tests and older Windows runners do not implement the channel.
      }
    });
    _queue = operation.catchError((Object error) {
      debugPrint('Windows reminder update failed: ${error.runtimeType}');
    });
    return _queue;
  }

  static Future<void> test() => channel.invokeMethod<void>('test');
}
