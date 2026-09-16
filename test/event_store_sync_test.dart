import 'dart:async';
import 'dart:convert';

import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/storage/event_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CalendarEvent draft(
  String title, {
  String id = '',
  String date = '2026-09-16',
}) => CalendarEvent(
  id: id,
  date: date,
  title: title,
  duration: 60,
  color: '#3B82F6',
  time: '13:00',
  recurrence: const EventRecurrence(frequency: RepeatFrequency.weekly),
);

class Server {
  final accounts = <String, Map<String, Map<String, dynamic>>>{};
  bool offline = false;
  Future<List<Map<String, dynamic>>> sync(
    String user,
    List<Map<String, dynamic>> changes,
  ) async {
    if (offline) throw Exception('offline');
    final items = accounts.putIfAbsent(user, () => {});
    for (final change in changes) {
      final id = change['id'] as String;
      final old = items[id];
      if (old == null ||
          (old['deleted'] != true &&
              (change['deleted'] == true ||
                  DateTime.parse(change['modifiedAt'] as String)
                      .isAfter(DateTime.parse(old['modifiedAt'] as String))))) {
        items[id] = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(change)) as Map,
        );
      }
    }
    return items.values
        .map(
          (item) =>
              Map<String, dynamic>.from(jsonDecode(jsonEncode(item)) as Map),
        )
        .toList();
  }

  EventStore device() => EventStore(syncRemote: sync);
}

Future<Map<String, Object>> disk() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final key in prefs.getKeys()) key: prefs.get(key)!};
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('second device receives events, edits, dates and deletion', () async {
    final server = Server();
    final first = server.device();
    await first.selectAccount('a');
    final saved = await first.saveEvent(
      draft('회의').copyWith(systemEventId: 'device-one'),
    );
    expect(await first.sync(), true);
    expect(
      server.accounts['a']![saved.id]!['event'],
      isNot(contains('systemEventId')),
    );
    final firstDisk = await disk();
    SharedPreferences.setMockInitialValues({});
    final second = server.device();
    await second.selectAccount('a');
    await second.sync();
    final restored = second.events.values.single.single;
    expect(restored.title, '회의');
    expect(restored.recurrence!.frequency, RepeatFrequency.weekly);
    expect(restored.systemEventId, isNull);
    await second.saveEvent(restored.copyWith(title: '변경', date: '2026-09-17'));
    await second.sync();
    SharedPreferences.setMockInitialValues(firstDisk);
    await first.sync();
    expect(first.events.keys, ['2026-09-17']);
    expect(first.events.values.single.single.title, '변경');
    expect(first.events.values.single.single.systemEventId, 'device-one');
    await second.deleteEvent('2026-09-17', saved.id);
    await second.sync();
    await first.sync();
    expect(first.events, isEmpty);
  });

  test(
    'offline changes and deletes survive restart without losing other events',
    () async {
      final server = Server();
      final first = server.device();
      await first.selectAccount('a');
      final original = await first.saveEvent(draft('원본'));
      await first.sync();
      server.offline = true;
      await first.deleteEvent(original.date, original.id);
      await first.saveEvent(draft('오프라인 추가'));
      expect(await first.sync(), false);
      final savedDisk = await disk();
      server.offline = false;
      SharedPreferences.setMockInitialValues({});
      final other = server.device();
      await other.selectAccount('a');
      await other.saveEvent(draft('다른 기기 추가'));
      await other.sync();
      SharedPreferences.setMockInitialValues(savedDisk);
      final restarted = server.device();
      await restarted.selectAccount('a');
      expect(await restarted.sync(), true);
      expect(
        restarted.events.values.expand((e) => e).map((e) => e.title).toSet(),
        {'오프라인 추가', '다른 기기 추가'},
      );
      // A stale device's edit cannot resurrect a deleted ID.
      await other.saveEvent(original.copyWith(title: '오래된 수정'));
      await other.sync();
      expect(
        other.events.values.expand((e) => e).any((e) => e.id == original.id),
        false,
      );
    },
  );

  test(
    'accounts are isolated and pending changes stay with their owner',
    () async {
      final server = Server()..offline = true;
      final store = server.device();
      await store.selectAccount('a');
      await store.saveEvent(draft('A 비공개'));
      await store.sync();
      await store.selectAccount('b');
      expect(store.events, isEmpty);
      server.offline = false;
      await store.sync();
      expect(server.accounts['b'], isEmpty);
      await store.selectAccount(null);
      expect(store.events, isEmpty);
      await store.selectAccount('a');
      await store.sync();
      expect(store.events.values.single.single.title, 'A 비공개');
    },
  );

  test(
    'legacy data migrates once and native identifiers stay on the device',
    () async {
      SharedPreferences.setMockInitialValues({
        'calendar-events-v1': jsonEncode({
          '2026-09-16': [
            draft(
              '기존 일정',
              id: 'legacy',
            ).copyWith(systemEventId: 'native').toJson(),
          ],
        }),
      });
      final server = Server();
      final store = server.device();
      await store.load();
      await store.selectAccount('a');
      await store.sync();
      expect(store.events.values.single.single.systemEventId, 'native');
      await store.selectAccount('b');
      await store.sync();
      expect(store.events, isEmpty);
      expect(server.accounts['b'], isEmpty);
    },
  );

  test('edits made during a request are uploaded after that request', () async {
    final server = Server();
    final started = Completer<void>();
    final release = Completer<void>();
    var firstRequest = true;
    final store = EventStore(
      syncRemote: (user, changes) async {
        if (firstRequest) {
          firstRequest = false;
          started.complete();
          await release.future;
        }
        return server.sync(user, changes);
      },
    );
    await store.selectAccount('a');
    final initial = store.sync();
    await started.future;
    final saving = store.saveEvent(draft('요청 중 추가'));
    release.complete();
    await initial;
    await saving;
    await store.sync();
    expect(server.accounts['a']!.values.single['event']['title'], '요청 중 추가');
  });

  test('stale native snapshot cannot overwrite a newer cloud edit', () async {
    final server = Server();
    final store = server.device();
    await store.selectAccount('a');
    final original = await store.saveEvent(draft('원본'));
    await store.sync();
    final staleNative = {
      original.date: [original.copyWith(title: '오래된 네이티브')],
    };
    await store.saveEvent(original.copyWith(title: '새 수정'));
    await store.sync();
    await store.replaceAll(staleNative);
    await store.sync();
    expect(store.events.values.single.single.title, '새 수정');
  });
  test(
    'large offline queue uploads in batches without dropping unsent events',
    () async {
      final server = Server()..offline = true;
      final sizes = <int>[];
      final store = EventStore(
        syncRemote: (user, changes) async {
          if (!server.offline) sizes.add(changes.length);
          return server.sync(user, changes);
        },
      );
      await store.selectAccount('a');
      for (var i = 0; i < 205; i++) {
        await store.saveEvent(draft('일정 $i'));
      }
      await store.sync();
      server.offline = false;
      expect(await store.sync(), true);
      expect(sizes, [200, 5]);
      expect(store.events.values.expand((events) => events).length, 205);
      expect(server.accounts['a']!.length, 205);
    },
  );

  test(
    'lost acknowledgement retries the same event without duplication',
    () async {
      final server = Server();
      var loseResponse = true;
      final store = EventStore(
        syncRemote: (user, changes) async {
          final result = await server.sync(user, changes);
          if (loseResponse) throw Exception('response lost');
          return result;
        },
      );
      await store.selectAccount('a');
      await store.saveEvent(draft('재전송'));
      expect(await store.sync(), false);
      loseResponse = false;
      expect(await store.sync(), true);
      expect(server.accounts['a']!.length, 1);
      expect(store.events.values.single.length, 1);
    },
  );
}
