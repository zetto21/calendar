import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'account_preferences.dart';

import '../models/calendar_event.dart';
import '../services/auth_service.dart';

class ImportedEvents extends ChangeNotifier {
  static const _sourcesKey = 'calendar.import.sources.v1';
  static const _visibilityKey = 'calendar.import.visibility.v1';
  static const _excludedEventsKey = 'calendar.import.excluded-events.v1';
  EventMap _events = const {};
  int _accountGeneration = 0;
  final Map<String, List<ImportCalendar>> _sources = {};
  final Map<String, bool> _visibility = {};
  final Set<String> _excludedEvents = {};
  EventMap get events => {
    for (final entry in _events.entries)
      entry.key: entry.value
          .where(
            (event) =>
                (_visibility[event.systemCalendarId] ?? true) &&
                !_excludedEvents.contains('id:${event.id}'),
          )
          .toList(),
  };
  Map<String, List<ImportCalendar>> get sources => _sources;

  Future<void> load() async {
    _accountGeneration++;
    _sources.clear();
    _visibility.clear();
    _excludedEvents.clear();
    _events = const {};
    final raw = await AccountPreferences.instance.get(_sourcesKey) as String?;
    if (raw == null) return;
    try {
      final saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      for (final entry in saved.entries) {
        _sources[entry.key] = (entry.value as List)
            .map(
              (value) => ImportCalendar.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList();
      }
      final visibility = await AccountPreferences.instance.get(_visibilityKey);
      if (visibility != null) {
        _visibility.addAll(
          Map<String, dynamic>.from(jsonDecode(visibility as String) as Map)
              .map((key, value) => MapEntry(key, value as bool)),
        );
      }
      final excluded = await AccountPreferences.instance.get(
        _excludedEventsKey,
      );
      if (excluded != null) {
        _excludedEvents.addAll(
          (jsonDecode(excluded as String) as List).map(
            (value) => value as String,
          ),
        );
      }
    } catch (_) {
      _sources.clear();
    }
  }

  String eventKey(String provider, String calendarId, String eventId) =>
      '$provider|$calendarId|$eventId';

  Future<void> saveEventSelection(
    String provider,
    Iterable<String> fetchedKeys,
    Iterable<String> selectedKeys,
  ) async {
    final fetched = fetchedKeys.toSet();
    _excludedEvents.removeAll(fetched);
    _excludedEvents.addAll(fetched.difference(selectedKeys.toSet()));
    await AccountPreferences.instance.set(
      _excludedEventsKey,
      jsonEncode(_excludedEvents.toList()),
    );
  }

  Future<void> hideImportedEvent(CalendarEvent event) async {
    _excludedEvents.add('id:${event.id}');
    await AccountPreferences.instance.set(
      _excludedEventsKey,
      jsonEncode(_excludedEvents.toList()),
    );
    notifyListeners();
  }

  bool isVisible(String provider, String calendarId) =>
      _visibility['$provider|$calendarId'] ?? true;

  Future<void> setVisible(
    String provider,
    String calendarId,
    bool visible,
  ) async {
    _visibility['$provider|$calendarId'] = visible;
    await AccountPreferences.instance.set(
      _visibilityKey,
      jsonEncode(_visibility),
    );
    notifyListeners();
  }

  void replace(EventMap events) {
    _events = events;
    notifyListeners();
  }

  void replaceProvider(String provider, EventMap events) {
    final next = <String, List<CalendarEvent>>{};
    for (final entry in _events.entries) {
      final retained = entry.value
          .where((event) => !event.id.startsWith('import:$provider:'))
          .toList();
      if (retained.isNotEmpty) next[entry.key] = retained;
    }
    for (final entry in events.entries) {
      (next[entry.key] ??= []).addAll(entry.value);
    }
    _events = next;
    notifyListeners();
  }

  /// Stores a device calendar connection even though its events are read
  /// directly through EventKit instead of the remote import endpoint.
  Future<void> setDeviceSources(
    String provider,
    List<ImportCalendar> calendars,
  ) async {
    _sources[provider] = calendars;
    await _persistSources();
    notifyListeners();
  }

  /// Removes a calendar connection and all read-only events it contributed.
  Future<void> disconnect(String provider, String calendarId) async {
    final calendars = _sources[provider];
    if (calendars == null) return;
    final remaining = calendars.where((item) => item.id != calendarId).toList();
    if (remaining.isEmpty) {
      _sources.remove(provider);
    } else {
      _sources[provider] = remaining;
    }
    _visibility.remove('$provider|$calendarId');
    _events = {
      for (final entry in _events.entries)
        entry.key: entry.value
            .where((event) => event.systemCalendarId != '$provider|$calendarId')
            .toList(),
    }..removeWhere((_, items) => items.isEmpty);
    await _persistSources();
    await AccountPreferences.instance.set(
      _visibilityKey,
      jsonEncode(_visibility),
    );
    notifyListeners();
  }

  Future<void> _persistSources() => AccountPreferences.instance.set(
    _sourcesKey,
    jsonEncode({
      for (final entry in _sources.entries)
        entry.key: [
          for (final calendar in entry.value)
            {
              'id': calendar.id,
              'title': calendar.title,
              'color': calendar.color,
            },
        ],
    }),
  );

  Future<void> refresh(
    String provider,
    List<ImportCalendar> calendars,
    DateTime from,
    DateTime to,
  ) async {
    final generation = _accountGeneration;
    final next = <String, List<CalendarEvent>>{};
    for (final calendar in calendars) {
      final items = await AuthService.instance.importEvents(
        provider,
        calendar.id,
        from,
        to,
      );
      for (final item in items) {
        if (_excludedEvents.contains(
          eventKey(provider, calendar.id, item.id),
        )) {
          continue;
        }
        final event = CalendarEvent(
          id: 'import:$provider:${calendar.id}:${item.id}',
          date: item.date,
          title: item.title,
          time: item.time,
          duration: item.duration,
          color: item.color,
          systemCalendarId: '$provider|${calendar.id}',
          description: '$provider · 읽기 전용',
        );
        (next[event.date] ??= []).add(event);
      }
    }
    if (generation != _accountGeneration) return;
    replaceProvider(provider, next);
    _sources[provider] = calendars;
    await _persistSources();
  }
}
