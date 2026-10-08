import 'dart:async';
import 'dart:convert';

import 'package:calendar_app_flutter/services/auth_service.dart';
import 'package:calendar_app_flutter/services/kbo_schedule.dart';
import 'package:calendar_app_flutter/storage/imported_events.dart';
import 'package:calendar_app_flutter/storage/account_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const calendars = [ImportCalendar(id: 'LG', title: 'LG 트윈스', color: '#C30452')];
final from = DateTime(2026, 10, 1);
final to = DateTime(2026, 10, 31);

KboGame game(String id, String date, {int? homeScore, int? awayScore}) =>
    KboGame(
      gameId: id,
      date: date,
      time: '18:30',
      homeCode: 'LG',
      homeName: 'LG',
      awayCode: 'KT',
      awayName: 'KT',
      cancelled: false,
      finished: homeScore != null,
      homeScore: homeScore,
      awayScore: awayScore,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'resume reload keeps games visible while settings and schedule load',
    () async {
      final response = Completer<List<KboGame>>();
      var pending = false;
      final imports = ImportedEvents(
        fetchKboSchedule: (_, _) async =>
            pending ? response.future : [game('game', '2026-10-09')],
      );
      addTearDown(imports.dispose);
      await imports.load();
      await imports.refresh('kbo', calendars, from, to);
      final reload = imports.load(preserveEvents: true);
      expect(imports.events['2026-10-09'], hasLength(1));
      expect(imports.sources['kbo'], hasLength(1));
      await reload;
      expect(imports.events['2026-10-09'], hasLength(1));
      pending = true;
      final refresh = imports.refresh('kbo', calendars, from, to);
      expect(imports.events['2026-10-09'], hasLength(1));
      response.complete([game('game', '2026-10-09')]);
      await refresh;
      expect(imports.events['2026-10-09'], hasLength(1));

      // A removed subscription must still disappear after settings synchronization.
      await AccountPreferences.instance.set('calendar.import.sources.v1', '{}');
      await imports.load(preserveEvents: true);
      expect(imports.events, isEmpty);
    },
  );

  test(
    'a new account session cannot retain the previous session games',
    () async {
      final imports = ImportedEvents(
        fetchKboSchedule: (_, _) async => [game('game', '2026-10-09')],
      );
      addTearDown(imports.dispose);
      await imports.load();
      await imports.refresh('kbo', calendars, from, to);
      await AccountPreferences.instance.selectAccount(null);
      final reload = imports.load(preserveEvents: true);
      expect(imports.events, isEmpty);
      await reload;
      expect(imports.events, isEmpty);
    },
  );

  test('failed KBO fetch preserves games until a successful update', () async {
    var fail = false;
    var empty = false;
    final imports = ImportedEvents(
      fetchKboSchedule: (_, _) async {
        if (fail) throw http.ClientException('offline');
        return empty ? [] : [game('first', '2026-10-09')];
      },
    );
    addTearDown(imports.dispose);
    await imports.refresh('kbo', calendars, from, to);
    var changes = 0;
    imports.addListener(() => changes++);
    fail = true;
    await expectLater(
      imports.refresh('kbo', calendars, from, to),
      throwsA(isA<http.ClientException>()),
    );
    expect(imports.events['2026-10-09'], hasLength(1));
    expect(changes, 0);
    fail = false;
    empty = true;
    await imports.refresh('kbo', calendars, from, to);
    expect(imports.events, isEmpty);
    expect(changes, 1);
  });

  test(
    'late response cannot overwrite the latest visible date range',
    () async {
      final responses = <Completer<List<KboGame>>>[];
      final imports = ImportedEvents(
        fetchKboSchedule: (_, _) {
          final response = Completer<List<KboGame>>();
          responses.add(response);
          return response.future;
        },
      );
      addTearDown(imports.dispose);
      final oldRequest = imports.refresh('kbo', calendars, from, to);
      final newRequest = imports.refresh(
        'kbo',
        calendars,
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 30),
      );
      responses[1].complete([game('new', '2026-11-02')]);
      await newRequest;
      responses[0].complete([game('old', '2026-10-09')]);
      await oldRequest;
      expect(imports.events.keys, ['2026-11-02']);
    },
  );

  test('unchanged games do not repaint, while changed scores do', () async {
    var scored = false;
    final imports = ImportedEvents(
      fetchKboSchedule: (_, _) async => [
        game(
          'game',
          '2026-10-09',
          homeScore: scored ? 3 : null,
          awayScore: scored ? 1 : null,
        ),
      ],
    );
    addTearDown(imports.dispose);
    await imports.refresh('kbo', calendars, from, to);
    var changes = 0;
    imports.addListener(() => changes++);
    await imports.refresh('kbo', calendars, from, to);
    expect(changes, 0);
    scored = true;
    await imports.refresh('kbo', calendars, from, to);
    expect(changes, 1);
    expect(imports.events['2026-10-09']!.single.title, 'KT 1 vs 3 LG');
  });

  test(
    'disconnect prevents an in-flight refresh from restoring a team',
    () async {
      final response = Completer<List<KboGame>>();
      var pending = false;
      final imports = ImportedEvents(
        fetchKboSchedule: (_, _) async =>
            pending ? response.future : [game('game', '2026-10-09')],
      );
      addTearDown(imports.dispose);
      await imports.refresh('kbo', calendars, from, to);
      pending = true;
      final request = imports.refresh('kbo', calendars, from, to);
      await imports.disconnect('kbo', 'LG');
      response.complete([game('game', '2026-10-09')]);
      await request;
      expect(imports.events, isEmpty);
      expect(imports.sources.containsKey('kbo'), false);
    },
  );

  test(
    'KBO transport distinguishes errors from a valid empty schedule',
    () async {
      for (final status in [403, 429, 503]) {
        await expectLater(
          KboScheduleService.fetchSchedule(
            from,
            to,
            client: MockClient((_) async => http.Response('{}', status)),
          ),
          throwsA(isA<http.ClientException>()),
        );
      }
      await expectLater(
        KboScheduleService.fetchSchedule(
          from,
          to,
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        await KboScheduleService.fetchSchedule(
          from,
          to,
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'result': {'games': []},
              }),
              200,
            ),
          ),
        ),
        isEmpty,
      );
    },
  );
}
