import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/services/windows_event_reminders.dart';
import 'package:calendar_app_flutter/screens/windows_reminder_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

CalendarEvent event({
  String id = 'meeting',
  String date = '2026-10-09',
  String title = '회의',
  String? time = '15:00',
  String? startsAt,
  EventRecurrence? recurrence,
}) => CalendarEvent(
  id: id,
  date: date,
  title: title,
  time: time,
  startsAt: startsAt,
  recurrence: recurrence,
  duration: 60,
  color: '#3B82F6',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  data.initializeTimeZones();
  final zone = tz.getLocation('Asia/Seoul');
  final now = DateTime.utc(2026, 10, 9, 3);
  final calls = <MethodCall>[];
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowsEventReminders.channel, (call) async {
          calls.add(call);
          return null;
        });
    await WindowsEventReminders.clear();
    calls.clear();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowsEventReminders.channel, null);
  });

  test('Seoul wall time schedules exactly ten minutes before start', () {
    final plan = buildWindowsReminders(
      {
        '2026-10-09': [event()],
      },
      zone,
      now,
      'a',
    );
    expect(plan, hasLength(1));
    expect(
      plan.single['at'],
      DateTime.utc(2026, 10, 9, 5, 50).millisecondsSinceEpoch,
    );
    expect(
      plan.single['expires'],
      DateTime.utc(2026, 10, 9, 7).millisecondsSinceEpoch,
    );
    expect(plan.single['body'], contains('15:00 시작'));
    expect((plan.single['id'] as String).length, 16);
  });

  test(
    'all-day, expired, special days and distant events have no reminders',
    () {
      final plan = buildWindowsReminders(
        {
          '2026-10-09': [
            event(id: 'all-day', time: null),
            event(id: 'expired', time: '10:00'),
            event(id: 'holiday:2026-10-09'),
            event(id: 'anniversary:2026-10-09'),
          ],
          '2026-11-09': [event(date: '2026-11-09')],
        },
        zone,
        now,
        'a',
      );
      expect(plan, isEmpty);
    },
  );

  test('recurrence expands the next week independently of visible dates', () {
    final plan = buildWindowsReminders(
      {
        '2026-09-01': [
          event(
            date: '2026-09-01',
            recurrence: const EventRecurrence(frequency: RepeatFrequency.daily),
          ),
        ],
      },
      zone,
      now,
      'a',
    );
    expect(plan, hasLength(7));
    expect(plan.map((entry) => entry['id']).toSet(), hasLength(7));
  });

  test(
    'account, title and time changes invalidate the old notification ID',
    () {
      String id(CalendarEvent value, String account) =>
          buildWindowsReminders(
                {
                  value.date: [value],
                },
                zone,
                now,
                account,
              ).single['id']
              as String;
      final original = id(event(), 'a');
      expect(id(event(), 'b'), isNot(original));
      expect(id(event(title: '변경된 회의'), 'a'), isNot(original));
      expect(id(event(time: '16:00'), 'a'), isNot(original));
    },
  );

  test('absolute timestamps are respected and delivered IDs survive snooze refresh', () {
    final plan = buildWindowsReminders(
      {
        '2026-10-09': [event(startsAt: '2026-10-09T03:05:00Z')],
      },
      zone,
      now,
      'a',
    );
    expect(
      plan.single['at'],
      DateTime.utc(2026, 10, 9, 2, 55).millisecondsSinceEpoch,
    );
    expect(
      plan.single['expires'],
      DateTime.utc(2026, 10, 9, 4, 5).millisecondsSinceEpoch,
    );
  });

  test('unchanged plans are not re-registered and deleting an event clears its plan', () async {
    final tomorrow = tz.TZDateTime.from(
      DateTime.now().add(const Duration(days: 1)),
      zone,
    );
    final key =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    final events = {
      key: [event(date: key)],
    };
    await WindowsEventReminders.update(
      account: 'a',
      events: events,
      zone: zone,
    );
    await WindowsEventReminders.update(
      account: 'a',
      events: events,
      zone: zone,
    );
    expect(calls.where((call) => call.method == 'schedule'), hasLength(1));
    await WindowsEventReminders.update(
      account: 'a',
      events: const {},
      zone: zone,
    );
    expect(calls.last.arguments, isEmpty);
  });

  test('logout supersedes an update still loading settings', () async {
    final pending = WindowsEventReminders.update(
      account: 'a',
      events: const {},
      zone: zone,
    );
    await WindowsEventReminders.clear();
    await pending;
    expect(calls.map((call) => call.method), ['clear']);
  });

  test(
    'enable preference belongs to the current account on this device',
    () async {
      expect(await WindowsEventReminders.enabled('a'), true);
      await WindowsEventReminders.setEnabled('a', false);
      expect(await WindowsEventReminders.enabled('a'), false);
      expect(await WindowsEventReminders.enabled('b'), true);
    },
  );

  testWidgets('settings toggle cancels reservations and offers a test alert', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWindowsReminderSettings(
                context,
                account: 'a',
                onChanged: () async {},
              ),
              child: const Text('settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(await WindowsEventReminders.enabled('a'), false);
    expect(calls.last.method, 'clear');
    await tester.tap(find.text('알림 테스트'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'test');
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
