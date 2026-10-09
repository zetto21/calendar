import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'account_preferences.dart';

import '../models/calendar_event.dart';
import '../services/auth_service.dart';
import '../services/kbo_schedule.dart';

class ImportedEvents extends ChangeNotifier {
  ImportedEvents({
    Future<List<KboGame>> Function(DateTime, DateTime)? fetchKboSchedule,
  }) : _fetchKboSchedule = fetchKboSchedule ?? KboScheduleService.fetchSchedule;

  final Future<List<KboGame>> Function(DateTime, DateTime) _fetchKboSchedule;
  int _kboRefreshVersion = 0;
  static const _sourcesKey = 'calendar.import.sources.v1';
  static const _visibilityKey = 'calendar.import.visibility.v1';
  static const _excludedEventsKey = 'calendar.import.excluded-events.v1';
  EventMap _events = const {};
  int _accountGeneration = 0;
  int? _loadedPreferencesGeneration;
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

  Future<void> load({bool preserveEvents = false}) async {
    final generation = ++_accountGeneration;
    final preferencesGeneration = AccountPreferences.instance.accountGeneration;
    final retainEvents =
        preserveEvents && _loadedPreferencesGeneration == preferencesGeneration;
    if (!retainEvents) {
      _sources.clear();
      _visibility.clear();
      _excludedEvents.clear();
      _events = const {};
    }
    final sources = <String, List<ImportCalendar>>{};
    final visible = <String, bool>{};
    final excludedEvents = <String>{};
    final raw = await AccountPreferences.instance.get(_sourcesKey) as String?;
    if (!_isCurrent(generation, preferencesGeneration)) return;
    if (raw == null) {
      _sources.clear();
      _visibility.clear();
      _excludedEvents.clear();
      _events = const {};
      _loadedPreferencesGeneration = preferencesGeneration;
      return;
    }
    try {
      final saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      var migratedDeviceSources = false;
      for (final entry in saved.entries) {
        // 톡캘린더 연동은 제거되어, 저장된 목록도 불러오지 않는다.
        if (entry.key == 'kakao') continue;
        // Apple·네이버 기기 캘린더 연동은 '기기에서 가져오기' 하나로 통합되었다.
        final key = _migrateDeviceProviderKey(entry.key);
        if (key != entry.key) migratedDeviceSources = true;
        final calendars = (entry.value as List)
            .map(
              (value) => ImportCalendar.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList();
        final existing = sources[key];
        if (existing == null) {
          sources[key] = calendars;
        } else {
          final seenIds = existing.map((calendar) => calendar.id).toSet();
          existing.addAll(
            calendars.where((calendar) => seenIds.add(calendar.id)),
          );
        }
      }
      final visibility = await AccountPreferences.instance.get(_visibilityKey);
      if (!_isCurrent(generation, preferencesGeneration)) return;
      if (visibility != null) {
        visible.addAll(
          Map<String, dynamic>.from(jsonDecode(visibility as String) as Map)
              .map(
                (key, value) =>
                    MapEntry(_migrateDeviceVisibilityKey(key), value as bool),
              ),
        );
      }
      final excluded = await AccountPreferences.instance.get(
        _excludedEventsKey,
      );
      if (!_isCurrent(generation, preferencesGeneration)) return;
      if (excluded != null) {
        excludedEvents.addAll(
          (jsonDecode(excluded as String) as List).map(
            (value) => value as String,
          ),
        );
      }
      // Commit settings together, keeping connected calendars visible while
      // resume synchronization fetches their latest events in the background.
      _sources
        ..clear()
        ..addAll(sources);
      _visibility
        ..clear()
        ..addAll(visible);
      _excludedEvents
        ..clear()
        ..addAll(excludedEvents);
      _loadedPreferencesGeneration = preferencesGeneration;
      if (retainEvents) {
        final connected = {
          for (final source in sources.entries)
            for (final calendar in source.value) '${source.key}|${calendar.id}',
        };
        _events = {
          for (final entry in _events.entries)
            entry.key: entry.value
                .where((event) => connected.contains(event.systemCalendarId))
                .toList(),
        }..removeWhere((_, events) => events.isEmpty);
      }
      if (migratedDeviceSources) {
        await _persistSources();
        if (!_isCurrent(generation, preferencesGeneration)) return;
        await AccountPreferences.instance.set(
          _visibilityKey,
          jsonEncode(_visibility),
        );
      }
    } catch (_) {
      if (_isCurrent(generation, preferencesGeneration)) {
        _sources.clear();
        _visibility.clear();
        _excludedEvents.clear();
        _events = const {};
      }
    }
  }

  bool _isCurrent(int generation, int preferencesGeneration) =>
      generation == _accountGeneration &&
      preferencesGeneration == AccountPreferences.instance.accountGeneration;

  /// Apple/네이버 기기 캘린더는 과거에 별도 provider로 저장되었지만, 이제는
  /// 하나의 '기기에서 가져오기'(`device`) 연동으로 합쳐졌다.
  static String _migrateDeviceProviderKey(String provider) =>
      provider == 'apple' || provider == 'naver' ? 'device' : provider;

  static String _migrateDeviceVisibilityKey(String key) {
    final separator = key.indexOf('|');
    if (separator == -1) return key;
    final provider = key.substring(0, separator);
    if (provider != 'apple' && provider != 'naver') return key;
    return 'device${key.substring(separator)}';
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
    // Reflect the tap before local persistence and remote synchronization.
    notifyListeners();
    await AccountPreferences.instance.set(
      _visibilityKey,
      jsonEncode(_visibility),
    );
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
    final generation = _accountGeneration;
    final preferencesGeneration = AccountPreferences.instance.accountGeneration;
    final calendars = _sources[provider];
    if (calendars == null) return;
    if (provider == 'kbo') _kboRefreshVersion++;
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
    if (!_isCurrent(generation, preferencesGeneration)) return;
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
              'category': calendar.category,
              'nameUnavailable': calendar.nameUnavailable,
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
    final preferencesGeneration = AccountPreferences.instance.accountGeneration;
    if (provider == 'kbo') {
      await _refreshKbo(generation, preferencesGeneration, calendars, from, to);
      return;
    }
    if (provider == 'kakao' &&
        calendars.any((calendar) => calendar.id == 'all')) {
      calendars = await AuthService.instance.importCalendars(provider);
      if (!_isCurrent(generation, preferencesGeneration)) return;
      if (calendars.any((calendar) => calendar.id == 'all')) {
        throw AuthException('톡캘린더 목록을 가져오려면 서버 업데이트가 필요합니다.');
      }
    }
    if (provider == 'kakao') {
      // 톡캘린더는 모든 캘린더를 같은 노란색으로 통일한다.
      calendars = [
        for (final calendar in calendars)
          ImportCalendar(
            id: calendar.id,
            title: calendar.title,
            color: _kakaoYellow,
            category: calendar.category,
            nameUnavailable: calendar.nameUnavailable,
          ),
      ];
    }
    final next = <String, List<CalendarEvent>>{};
    for (final calendar in calendars) {
      final items = await AuthService.instance.importEvents(
        provider,
        calendar.id,
        from,
        to,
      );
      if (!_isCurrent(generation, preferencesGeneration)) return;
      for (final item in items) {
        // Talk calendars are connected as a whole. Older per-event import
        // selections must not suppress their future synchronizations.
        if (provider != 'kakao' &&
            _excludedEvents.contains(
              eventKey(provider, calendar.id, item.id),
            )) {
          continue;
        }
        // Imported identifiers include provider/calendar prefixes and can be
        // longer than writable cloud event IDs; validate their display fields.
        CalendarEvent.fromJson({
          'id': 'imported-validation',
          'date': item.date,
          'title': item.title,
          'time': item.time,
          'duration': item.duration,
          'color': item.color,
        });
        final event = CalendarEvent(
          id: 'import:$provider:${calendar.id}:${item.id}',
          date: item.date,
          title: item.title,
          time: item.time,
          duration: item.duration,
          color: provider == 'kakao' ? calendar.color : item.color,
          systemCalendarId: '$provider|${calendar.id}',
          description: '$provider · 읽기 전용',
        );
        (next[event.date] ??= []).add(event);
      }
    }
    if (!_isCurrent(generation, preferencesGeneration)) return;
    _sources[provider] = calendars;
    await _persistSources();
    if (!_isCurrent(generation, preferencesGeneration)) return;
    replaceProvider(provider, next);
  }

  /// Fetches the whole KBO league schedule once and keeps a game exactly
  /// once even when both its teams are subscribed, instead of fetching (and
  /// duplicating) it once per subscribed team.
  Future<void> _refreshKbo(
    int generation,
    int preferencesGeneration,
    List<ImportCalendar> calendars,
    DateTime from,
    DateTime to,
  ) async {
    final version = ++_kboRefreshVersion;
    bool current() =>
        version == _kboRefreshVersion &&
        _isCurrent(generation, preferencesGeneration);
    final games = await _fetchKboSchedule(from, to);
    // Date navigation and subscription changes can overlap network requests.
    // Only the newest response may replace the currently displayed schedule.
    if (!current()) return;
    final colorByCode = {for (final c in calendars) c.id: c.color};
    final next = <String, List<CalendarEvent>>{};
    for (final game in games) {
      final homeSubscribed = colorByCode.containsKey(game.homeCode);
      final awaySubscribed = colorByCode.containsKey(game.awayCode);
      if (!homeSubscribed && !awaySubscribed) continue;
      final primaryCode = homeSubscribed ? game.homeCode : game.awayCode;
      if (_excludedEvents.contains(eventKey('kbo', primaryCode, game.gameId))) {
        continue;
      }
      final event = CalendarEvent(
        id: 'import:kbo:$primaryCode:${game.gameId}',
        date: game.date,
        title: game.cancelled
            ? '${game.awayName} vs ${game.homeName} (취소)'
            : game.finished && game.awayScore != null && game.homeScore != null
            ? '${game.awayName} ${game.awayScore} vs ${game.homeScore} ${game.homeName}'
            : '${game.awayName} vs ${game.homeName}',
        time: game.time,
        location: game.stadium?.trim().isNotEmpty == true
            ? game.stadium!.trim()
            : null,
        duration: _kboGameDurationMinutes,
        color: colorByCode[primaryCode] ?? '#707078',
        systemCalendarId: 'kbo|$primaryCode',
        description: [
          if (game.homeScore != null && game.awayScore != null)
            '${game.awayName} ${game.awayScore} : ${game.homeScore} ${game.homeName}',
        ].join(' · '),
      );
      (next[event.date] ??= []).add(event);
    }
    if (!current()) return;
    final previousCalendars = _sources['kbo'] ?? const <ImportCalendar>[];
    final sourcesChanged =
        previousCalendars.length != calendars.length ||
        !listEquals(
          previousCalendars.map(_calendarSignature).toList(),
          calendars.map(_calendarSignature).toList(),
        );
    final previousEvents = {
      for (final event in _events.values.expand((items) => items))
        if (event.id.startsWith('import:kbo:'))
          event.id: jsonEncode(event.toJson()),
    };
    final nextEvents = {
      for (final event in next.values.expand((items) => items))
        event.id: jsonEncode(event.toJson()),
    };
    final eventsChanged = !mapEquals(previousEvents, nextEvents);
    _sources['kbo'] = calendars;
    if (sourcesChanged) await _persistSources();
    if (!current()) return;
    if (eventsChanged) {
      replaceProvider('kbo', next);
    } else if (sourcesChanged) {
      notifyListeners();
    }
  }

  static String _calendarSignature(ImportCalendar calendar) => jsonEncode([
    calendar.id,
    calendar.title,
    calendar.color,
    calendar.category,
    calendar.nameUnavailable,
  ]);
}

const _kakaoYellow = '#F5D76E';
const _kboGameDurationMinutes = 210;
