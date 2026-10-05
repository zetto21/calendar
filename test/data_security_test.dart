import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/services/backup_service.dart';
import 'package:calendar_app_flutter/storage/account_preferences.dart';
import 'package:calendar_app_flutter/storage/event_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> eventJson({String id = 'event-1', String title = '일정'}) =>
    {
      'id': id,
      'date': '2026-10-04',
      'title': title,
      'time': null,
      'duration': 60,
      'color': '#0A84FF',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('untrusted events reject invalid dates, times, numbers and types', () {
    for (final patch in <Map<String, dynamic>>[
      {'date': '2026-02-31'},
      {'date': '2026-13-01'},
      {'date': '2026-1-4'},
      {'time': '24:00'},
      {'time': '12:60'},
      {'time': 1230},
      {'duration': -1},
      {'duration': 1.5},
      {'duration': double.infinity},
      {'duration': 366 * 24 * 60 + 1},
      {'title': <String>[]},
      {'id': 'unsafe\u0000id'},
      {'startsAt': 'not-a-timestamp'},
      {'endsAt': '2026-02-31T12:00:00Z'},
      {'updatedAt': 'invalid'},
      {'color': '#broken'},
      {
        'recurrence': {'frequency': 'unexpected'},
      },
      {
        'recurrence': {'frequency': 'daily', 'until': '2026-02-30'},
      },
      {'description': 'a' * (16 * 1024)},
    ]) {
      expect(
        () => CalendarEvent.fromJson({...eventJson(), ...patch}),
        throwsFormatException,
      );
    }
    expect(CalendarEvent.fromJson(eventJson()).isAllDay, isTrue);
    expect(
      CalendarEvent.fromJson({...eventJson(), 'color': '#abc', 'duration': 0})
          .duration,
      0,
    );
  });

  test(
    'previous malformed cache cannot block valid events or app startup',
    () async {
      final raw = jsonEncode({
        'events': {
          'invalid-key': [
            eventJson(),
            {...eventJson(id: 'bad'), 'time': '24:00'},
          ],
        },
        'pending': {},
      });
      SharedPreferences.setMockInitialValues({
        'calendar.account-events.guest': raw,
      });
      final store = EventStore();
      await store.load();
      expect(store.loaded, isTrue);
      expect(store.events.keys, ['2026-10-04']);
      expect(store.events.values.single.single.id, 'event-1');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('calendar.account-events.guest'), raw);
      store.dispose();
    },
  );

  test(
    'restore removes device ownership and rejects duplicate IDs atomically',
    () async {
      final store = EventStore();
      await store.load();
      await store.restoreBackup([
        {
          ...eventJson(),
          'systemEventId': 'victim-device-event',
          'systemCalendarId': 'victim-calendar',
          'seriesId': 'foreign-series',
        },
      ]);
      final restored = store.events.values.single.single;
      expect(restored.systemEventId, isNull);
      expect(restored.systemCalendarId, isNull);
      expect(restored.seriesId, isNull);
      await expectLater(
        store.restoreBackup([
          eventJson(title: 'new'),
          eventJson(title: 'duplicate'),
        ]),
        throwsFormatException,
      );
      expect(store.events.values.single.single.title, '일정');
      await expectLater(
        store.restoreBackup([
          {...eventJson(), 'date': '2026-02-31'},
        ]),
        throwsFormatException,
      );
      expect(store.events.values.single.single.title, '일정');
      store.dispose();
    },
  );

  test(
    'malformed remote IDs cannot replace or acknowledge queued events',
    () async {
      final store = EventStore(
        syncRemote: (user, changes) async => [
          {
            'id': 'event-1',
            'deleted': false,
            'event': eventJson(id: 'different-id'),
          },
        ],
      );
      await store.selectAccount('alice');
      await store.restoreBackup([eventJson()]);
      expect(await store.sync(), isFalse);
      expect(store.events.values.single.single.id, 'event-1');
      store.dispose();
    },
  );

  test('backup timestamps cannot poison the local upload queue', () async {
    final batches = <List<Map<String, dynamic>>>[];
    final store = EventStore(
      syncRemote: (_, changes) async {
        batches.add(changes);
        return changes;
      },
    );
    await store.selectAccount('alice');
    await store.restoreBackup([
      {...eventJson(), 'updatedAt': '9999-12-31T23:59:59Z'},
    ]);
    expect(await store.sync(), isTrue);
    expect(
      DateTime.parse(batches.single.single['modifiedAt'] as String).year,
      DateTime.now().year,
    );
    expect(
      store.events.values.single.single.updatedAt,
      isNot(startsWith('9999')),
    );
    store.dispose();
  });

  test(
    'account change discards old synchronization and stale restore',
    () async {
      final response = Completer<List<Map<String, dynamic>>>();
      final requested = Completer<void>();
      final store = EventStore(
        syncRemote: (user, changes) {
          requested.complete();
          return response.future;
        },
      );
      await store.selectAccount('alice');
      await store.restoreBackup([eventJson()]);
      final generation = store.accountGeneration;
      final syncing = store.sync();
      await requested.future;
      final switching = store.selectAccount('bob');
      response.complete([
        {'id': 'event-1', 'event': eventJson(title: 'private Alice data')},
      ]);
      expect(await syncing, isFalse);
      await switching;
      expect(store.events, isEmpty);
      await expectLater(
        store.restoreBackup([
          eventJson(),
        ], expectedAccountGeneration: generation),
        throwsA(isA<Exception>()),
      );
      expect(store.events, isEmpty);
      store.dispose();
    },
  );

  test('guest cache and an account named guest are separate', () async {
    final store = EventStore(syncRemote: (user, changes) async => []);
    await store.load();
    await store.restoreBackup([eventJson(title: 'guest-only')]);
    // Legacy first-account migration is already owned by a different user.
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('calendar.events.legacy-owner', 'alice');
    await store.selectAccount('guest');
    expect(store.events, isEmpty);
    await store.restoreBackup([eventJson(title: 'signed-in')]);
    await store.selectAccount(null);
    expect(store.events.values.single.single.title, 'guest-only');
    store.dispose();
  });

  test(
    'CSV formula escaping restores original text without spreadsheet execution',
    () async {
      final dangerous = [
        '=HYPERLINK("https://example.com")',
        '  +SUM(1,2)',
        '\t@SUM(1)',
        '-1+2',
      ];
      final encoded = BackupService.encodeCsv([
        for (var i = 0; i < dangerous.length; i++)
          CalendarEvent.fromJson(
            eventJson(id: 'event-$i', title: dangerous[i]),
          ),
      ]);
      expect(encoded, contains("'=HYPERLINK"));
      expect(encoded, contains("'  +SUM"));
      final store = EventStore();
      await store.load();
      await BackupService.restoreContent(store, encoded, 'csv');
      expect(store.events.values.single.map((e) => e.title), dangerous);
      store.dispose();
    },
  );

  test('ICS output cannot inject properties with carriage returns', () {
    final encoded = BackupService.encodeIcs([
      CalendarEvent.fromJson(
        eventJson(title: 'title\rATTENDEE:attacker\r\nEND:VEVENT'),
      ),
    ]);
    expect(encoded, contains(r'SUMMARY:title\nATTENDEE:attacker\nEND:VEVENT'));
    expect(
      encoded.split('\r\n').where((line) => line == 'END:VEVENT'),
      hasLength(1),
    );
  });

  test(
    'oversized file streams stop before retaining the excess chunk',
    () async {
      var cancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final reading = BackupService.readBackupBytes(controller.stream);
      controller.add(Uint8List(BackupService.maxImportBytes));
      controller.add([0]);
      await expectLater(reading, throwsFormatException);
      expect(cancelled, isTrue);
      await controller.close();
    },
  );

  test('invalid CSV, ICS and deep JSON leave current events intact', () async {
    final store = EventStore();
    await store.load();
    await store.restoreBackup([eventJson()]);
    for (final sample in <(String, String)>[
      (
        'csv',
        'id,date,title,time,durationMinutes,color\nnew,2026-10-04,"unfinished,,60,#0A84FF',
      ),
      (
        'ics',
        'BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART:20260231\nSUMMARY:bad\nEND:VEVENT\nEND:VCALENDAR',
      ),
      ('json', '${'[' * 33}0${']' * 33}'),
    ]) {
      await expectLater(
        BackupService.restoreContent(store, sample.$2, sample.$1),
        throwsFormatException,
      );
      expect(store.events.values.single.single.id, 'event-1');
    }
    store.dispose();
  });

  test(
    'invalid remote settings cannot crash display or leak across accounts',
    () async {
      final response = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      final preferences = AccountPreferences(
        loadRemote: (user) {
          started.complete();
          return response.future;
        },
        saveRemote: (_, _) async {},
      );
      await preferences.selectAccount('alice');
      final syncing = preferences.sync();
      await started.future;
      final switching = preferences.selectAccount('bob');
      response.complete({'calendar.display.holidays': true});
      expect(await syncing, isFalse);
      await switching;
      expect(await preferences.get('calendar.display.holidays'), isNull);
    },
  );

  test('settings validate server schema and keep onboarding local', () async {
    final uploads = <Map<String, dynamic>>[];
    var remote = <String, dynamic>{};
    final preferences = AccountPreferences(
      loadRemote: (_) async => remote,
      saveRemote: (_, values) async => uploads.add(values),
    );
    await preferences.selectAccount('alice');
    await preferences.set('onboarding.completed.v1', true);
    expect(uploads, isEmpty);
    expect(await preferences.get('onboarding.completed.v1'), isTrue);
    remote = {'calendar.display.holidays': 'invalid type'};
    expect(await preferences.sync(), isFalse);
    expect(await preferences.get('calendar.display.holidays'), isNull);
    expect(await preferences.get('onboarding.completed.v1'), isTrue);
    remote = {
      'calendar.personal.lists.v1': jsonEncode([
        {'id': 'x', 'title': 'bad', 'color': 'invalid'},
      ]),
    };
    expect(await preferences.sync(), isFalse);
    expect(await preferences.get('calendar.personal.lists.v1'), isNull);
  });
}
