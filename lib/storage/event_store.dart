import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_event.dart';
import '../services/auth_service.dart';
import '../services/secure_http.dart';

const _storageKey = 'calendar-events-v1';

String _makeId() {
  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(36).toRadixString(36),
  ).join();
  return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
}

/// Account-scoped cache with an atomic, durable queue of individual changes.
class EventStore extends ChangeNotifier {
  EventStore({
    Future<List<Map<String, dynamic>>> Function(
      String,
      List<Map<String, dynamic>>,
    )?
    syncRemote,
  }) : _syncRemote = syncRemote ?? AuthService.instance.syncEvents;

  final Future<List<Map<String, dynamic>>> Function(
    String,
    List<Map<String, dynamic>>,
  )
  _syncRemote;
  final syncSucceeded = ValueNotifier<bool?>(null);
  EventMap _events = {};
  Map<String, Map<String, dynamic>> _pending = {};
  String? _user;
  bool _loaded = false;
  Future<void> _queue = Future.value();
  Future<bool>? _syncing;
  int _accountGeneration = 0;

  EventMap get events => _events;
  bool get loaded => _loaded;
  int get accountGeneration => _accountGeneration;
  String get _cacheKey => _user == null
      ? 'calendar.account-events.guest'
      : 'calendar.account-events.user.${base64Url.encode(utf8.encode(_user!))}';

  void _checkAccount(int generation) {
    if (generation != _accountGeneration) {
      throw AuthException('계정이 변경되었습니다. 다시 시도해 주세요.');
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  EventMap _decodeEvents(Map<String, dynamic> values) {
    final events = <String, List<CalendarEvent>>{};
    final ids = <String>{};
    for (final value in values.values) {
      if (value is! List) continue;
      for (final raw in value) {
        if (ids.length >= 10000) break;
        try {
          final event = CalendarEvent.fromJson(
            Map<String, dynamic>.from(raw as Map),
          );
          if (ids.add(event.id)) _put(events, event);
        } catch (_) {
          // Older clients could cache malformed remote data. Keep valid events
          // usable; the original cache is retained until a later successful write.
        }
      }
    }
    _sortEvents(events);
    return events;
  }

  Map<String, dynamic> _decodeCache(String raw) {
    if (utf8.encode(raw).length > 32 * 1024 * 1024) {
      throw const FormatException('일정 캐시가 너무 큽니다.');
    }
    return Map<String, dynamic>.from(
      decodeBoundedJson(raw, maxDepth: 32) as Map,
    );
  }

  Map<String, Map<String, dynamic>> _decodePending(dynamic raw) {
    final pending = <String, Map<String, dynamic>>{};
    if (raw is! Map) return pending;
    final localIds = _events.values
        .expand((items) => items)
        .map((event) => event.id)
        .toSet();
    for (final entry in raw.entries) {
      if (pending.length >= 10000) break;
      try {
        final change = Map<String, dynamic>.from(entry.value as Map);
        final id = entry.key;
        final timestamp = change['modifiedAt'];
        if (id is! String ||
            id.trim().isEmpty ||
            id.length > 256 ||
            id.contains('\u0000') ||
            change['id'] != id ||
            change['deleted'] is! bool ||
            timestamp is! String ||
            DateTime.tryParse(timestamp) == null) {
          continue;
        }
        if (change['deleted'] != true) {
          final event = CalendarEvent.fromJson(
            Map<String, dynamic>.from(change['event'] as Map),
          );
          if (event.id != id || !localIds.contains(id)) {
            continue;
          }
        }
        pending[id] = change;
      } catch (_) {
        // An invalid queue entry must not prevent every valid edit syncing.
      }
    }
    return pending;
  }

  Future<void> load() => selectAccount(null);

  Future<void> selectAccount(String? user) {
    final generation = ++_accountGeneration;
    return _serial(() async {
      if (generation != _accountGeneration) return;
      final prefs = await SharedPreferences.getInstance();
      if (generation != _accountGeneration) return;
      _user = user;
      _events = {};
      _pending = {};
      syncSucceeded.value = null;
      // Namespaced account keys cannot collide with the unauthenticated guest.
      final raw =
          prefs.getString(_cacheKey) ??
          (user != null && user != 'guest'
              ? prefs.getString('calendar.account-events.$user')
              : null);
      if (raw != null) {
        try {
          final cache = _decodeCache(raw);
          _events = _decodeEvents(
            Map<String, dynamic>.from(cache['events'] as Map),
          );
          _pending = _decodePending(cache['pending']);
        } catch (_) {
          // Retain unreadable bytes for recovery and allow a cloud refresh.
          syncSucceeded.value = false;
        }
      } else if (prefs.getString('calendar.events.legacy-owner') == null) {
        // Claim pre-sync device events only once, never another account's cache.
        final legacy = prefs.getString(_storageKey);
        if (legacy != null) {
          try {
            _events = _decodeEvents(_decodeCache(legacy));
          } catch (_) {
            /* Leave the original legacy data intact for recovery. */
          }
        }
        if (user != null) {
          final guest = prefs.getString('calendar.account-events.guest');
          if (guest != null) {
            try {
              final cache = _decodeCache(guest);
              _events = _decodeEvents(
                Map<String, dynamic>.from(cache['events'] as Map),
              );
            } catch (_) {
              // A damaged guest cache cannot block another account loading.
            }
          }
          for (final event in _events.values.expand((list) => list)) {
            _pending[event.id] = _change(event);
          }
          await _persist();
          await prefs.setString('calendar.events.legacy-owner', user);
        }
      }
      if (user != null &&
          prefs.getString('calendar.events.legacy-owner') == null) {
        await prefs.setString('calendar.events.legacy-owner', user);
      }
      _loaded = true;
      notifyListeners();
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _cacheKey,
      jsonEncode({
        'events': _events.map(
          (key, value) => MapEntry(key, value.map((e) => e.toJson()).toList()),
        ),
        'pending': _pending,
      }),
    );
    if (!saved) throw StateError('일정을 기기에 저장하지 못했습니다.');
  }

  Map<String, dynamic> _cloudEvent(CalendarEvent event) => event.toJson()
    ..remove('systemEventId')
    ..remove('systemCalendarId')
    ..remove('seriesId');

  Map<String, dynamic> _change(CalendarEvent event) => {
    'id': event.id,
    'modifiedAt': event.updatedAt ?? DateTime.now().toUtc().toIso8601String(),
    'deleted': false,
    'event': _cloudEvent(event),
  };

  void _put(EventMap target, CalendarEvent event) {
    final list = target.putIfAbsent(event.date, () => []);
    list.add(event);
  }

  void _sortEvents(EventMap events) {
    for (final list in events.values) {
      list.sort((a, b) => (a.time ?? '').compareTo(b.time ?? ''));
    }
  }

  String _timestamp(String id) {
    var now = DateTime.now().toUtc();
    final previous = _pending[id]?['modifiedAt'] as String?;
    if (previous != null) {
      final last = DateTime.parse(previous);
      if (!now.isAfter(last)) now = last.add(const Duration(microseconds: 1));
    }
    return now.toIso8601String();
  }

  Future<CalendarEvent> saveEvent(CalendarEvent draft) async {
    final generation = _accountGeneration;
    final event = await _serial(() async {
      _checkAccount(generation);
      final id = draft.id.isNotEmpty ? draft.id : _makeId();
      final now = _timestamp(id);
      final event = draft.copyWith(
        id: id,
        uid: draft.uid ?? id,
        createdAt: draft.createdAt ?? now,
        updatedAt: now,
      );
      final next = <String, List<CalendarEvent>>{};
      for (final old in _events.values.expand((list) => list)) {
        if (old.id != id) _put(next, old);
      }
      _put(next, event);
      _sortEvents(next);
      _events = next;
      if (_user != null) _pending[id] = _change(event);
      await _persist();
      notifyListeners();
      return event;
    });
    unawaited(sync());
    return event;
  }

  /// Apply native edits only to existing events; don't resurrect remote deletions.
  Future<void> replaceAll(
    EventMap events, {
    int? expectedAccountGeneration,
  }) async {
    final generation = expectedAccountGeneration ?? _accountGeneration;
    await _serial(() async {
      _checkAccount(generation);
      final incoming = {
        for (final e in events.values.expand((list) => list)) e.id: e,
      };
      final next = <String, List<CalendarEvent>>{};
      for (final current in _events.values.expand((list) => list)) {
        final native = incoming[current.id];
        var event = current;
        // SystemEventsSync preserves updatedAt. Ignore snapshots superseded by cloud edits.
        if (native != null &&
            native.updatedAt == current.updatedAt &&
            jsonEncode(native.toJson()) != jsonEncode(current.toJson())) {
          event = native.copyWith(updatedAt: _timestamp(current.id));
          if (_user != null) _pending[event.id] = _change(event);
        }
        _put(next, event);
      }
      _sortEvents(next);
      _events = next;
      await _persist();
      notifyListeners();
    });
    unawaited(sync());
  }

  Future<void> deleteEvent(String dateKey, String id) async {
    final generation = _accountGeneration;
    await _serial(() async {
      _checkAccount(generation);
      final next = <String, List<CalendarEvent>>{};
      for (final event in _events.values.expand((list) => list)) {
        if (event.id != id) _put(next, event);
      }
      _sortEvents(next);
      _events = next;
      if (_user != null) {
        _pending[id] = {
          'id': id,
          'modifiedAt': _timestamp(id),
          'deleted': true,
        };
      }
      await _persist();
      notifyListeners();
    });
    unawaited(sync());
  }

  Map<String, dynamic> exportBackup() => {
    'events': _events.values
        .expand((items) => items)
        .map((event) => event.toJson())
        .toList(),
  };

  Future<void> restoreBackup(
    List<dynamic> rawEvents, {
    int? expectedAccountGeneration,
  }) {
    final generation = expectedAccountGeneration ?? _accountGeneration;
    return _serial(() async {
      _checkAccount(generation);
      if (rawEvents.length > 10000) {
        throw const FormatException('백업 일정은 10,000개까지 복원할 수 있습니다.');
      }
      final restored = <String, List<CalendarEvent>>{};
      final pending = <String, Map<String, dynamic>>{};
      final ids = <String>{};
      for (final raw in rawEvents) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('일정 데이터 형식이 올바르지 않습니다.');
        }
        // Portable files cannot claim ownership of existing device calendars.
        final fields = {...raw}
          ..remove('systemEventId')
          ..remove('systemCalendarId')
          ..remove('seriesId');
        final parsed = CalendarEvent.fromJson(fields);
        // A restore is a new local edit. Backup timestamps must not poison the
        // upload queue with future timestamps or lose to an old cloud copy.
        final now = DateTime.now().toUtc().toIso8601String();
        final event = parsed.copyWith(
          updatedAt: now,
          createdAt: parsed.createdAt ?? now,
        );
        if (!ids.add(event.id)) {
          throw const FormatException('백업 일정 ID가 중복되었습니다.');
        }
        _put(restored, event);
        if (_user != null) pending[event.id] = _change(event);
      }
      final oldEvents = _events;
      final oldPending = _pending;
      _sortEvents(restored);
      _events = restored;
      _pending = pending;
      try {
        await _persist();
      } catch (_) {
        _events = oldEvents;
        _pending = oldPending;
        rethrow;
      }
      notifyListeners();
    });
  }

  Future<bool> sync() {
    if (_syncing != null) return _syncing!;
    final generation = _accountGeneration;
    final operation = _serial(() async {
      if (generation != _accountGeneration) return false;
      final user = _user;
      if (user == null) return true;
      try {
        do {
          final batch = _pending.values.take(200).toList();
          final remote = await _syncRemote(user, batch);
          if (generation != _accountGeneration) return false;
          if (remote.length > 10000) {
            throw const FormatException('일정 응답이 너무 큽니다.');
          }
          final local = {
            for (final e in _events.values.expand((list) => list)) e.id: e,
          };
          final remaining = {..._pending};
          for (final change in batch) {
            remaining.remove(change['id']);
          }
          final next = <String, List<CalendarEvent>>{};
          final ids = <String>{};
          for (final change in remote) {
            final id = change['id'] as String;
            if (!ids.add(id)) {
              throw const FormatException('일정 응답 ID가 중복되었습니다.');
            }
            if (remaining.containsKey(id) || change['deleted'] == true) {
              continue;
            }
            final fields = Map<String, dynamic>.from(change['event'] as Map)
              ..remove('systemEventId')
              ..remove('systemCalendarId')
              ..remove('seriesId');
            if (fields['id'] != id) {
              throw const FormatException('일정 응답 ID가 올바르지 않습니다.');
            }
            final old = local[id];
            if (old?.systemEventId != null) {
              fields['systemEventId'] = old!.systemEventId;
            }
            if (old?.systemCalendarId != null) {
              fields['systemCalendarId'] = old!.systemCalendarId;
            }
            _put(next, CalendarEvent.fromJson(fields));
          }
          for (final change in remaining.values) {
            if (change['deleted'] != true) _put(next, local[change['id']]!);
          }
          final oldEvents = _events;
          final oldPending = _pending;
          _sortEvents(next);
          _events = next;
          _pending = remaining;
          try {
            await _persist();
          } catch (_) {
            _events = oldEvents;
            _pending = oldPending;
            rethrow;
          }
          notifyListeners();
        } while (_pending.isNotEmpty);
        syncSucceeded.value = true;
        return true;
      } catch (_) {
        if (generation == _accountGeneration) syncSucceeded.value = false;
        return false;
      }
    });
    _syncing = operation;
    operation.whenComplete(() {
      _syncing = null;
    });
    return operation;
  }

  @override
  void dispose() {
    syncSucceeded.dispose();
    super.dispose();
  }
}
