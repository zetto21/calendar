import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_event.dart';
import '../services/auth_service.dart';

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

  EventMap get events => _events;
  bool get loaded => _loaded;
  String get _cacheKey => 'calendar.account-events.${_user ?? "guest"}';

  Future<T> _serial<T>(Future<T> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  EventMap _decodeEvents(Map<String, dynamic> values) => values.map(
    (key, value) => MapEntry(
      key,
      (value as List)
          .map(
            (e) => CalendarEvent.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    ),
  );

  Future<void> load() => selectAccount(null);

  Future<void> selectAccount(String? user) => _serial(() async {
    final prefs = await SharedPreferences.getInstance();
    _user = user;
    _events = {};
    _pending = {};
    syncSucceeded.value = null;
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      final cache = jsonDecode(raw) as Map<String, dynamic>;
      _events = _decodeEvents(
        Map<String, dynamic>.from(cache['events'] as Map),
      );
      _pending = (cache['pending'] as Map).map(
        (key, value) =>
            MapEntry(key as String, Map<String, dynamic>.from(value as Map)),
      );
    } else if (prefs.getString('calendar.events.legacy-owner') == null) {
      // Claim pre-sync device events only once, never another account's cache.
      final legacy = prefs.getString(_storageKey);
      if (legacy != null) {
        try {
          _events = _decodeEvents(jsonDecode(legacy) as Map<String, dynamic>);
        } catch (_) {
          /* Leave the original legacy data intact for recovery. */
        }
      }
      if (user != null) {
        final guest = prefs.getString('calendar.account-events.guest');
        if (guest != null) {
          final cache = jsonDecode(guest) as Map<String, dynamic>;
          _events = _decodeEvents(
            Map<String, dynamic>.from(cache['events'] as Map),
          );
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
    list.sort((a, b) => (a.time ?? '').compareTo(b.time ?? ''));
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
    final event = await _serial(() async {
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
  Future<void> replaceAll(EventMap events) async {
    await _serial(() async {
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
      _events = next;
      await _persist();
      notifyListeners();
    });
    unawaited(sync());
  }

  Future<void> deleteEvent(String dateKey, String id) async {
    await _serial(() async {
      final next = <String, List<CalendarEvent>>{};
      for (final event in _events.values.expand((list) => list)) {
        if (event.id != id) _put(next, event);
      }
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

  Future<bool> sync() {
    if (_syncing != null) return _syncing!;
    final operation = _serial(() async {
      final user = _user;
      if (user == null) return true;
      try {
        do {
          final batch = _pending.values.take(200).toList();
          final remote = await _syncRemote(user, batch);
          final local = {
            for (final e in _events.values.expand((list) => list)) e.id: e,
          };
          final remaining = {..._pending};
          for (final change in batch) {
            remaining.remove(change['id']);
          }
          final next = <String, List<CalendarEvent>>{};
          for (final change in remote) {
            final id = change['id'] as String;
            if (remaining.containsKey(id) || change['deleted'] == true) {
              continue;
            }
            final fields = Map<String, dynamic>.from(change['event'] as Map)
              ..remove('systemEventId')
              ..remove('systemCalendarId')
              ..remove('seriesId');
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
        syncSucceeded.value = false;
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
