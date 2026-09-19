import 'package:calendar_app_flutter/native/live_activity.dart';
import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/settings_screen.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  testWidgets(
    'Android bridges status, start, update and end to native notifications',
    (tester) async {
      const channel = MethodChannel('calendar_app/live_activity');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'status')
          return {
            'supported': true,
            'enabled': true,
            'eventIDs': ['test'],
          };
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final status = await LiveActivity.status();
      expect(status.supported, isTrue);
      expect(status.eventIDs, ['test']);
      final event = LiveCalendarEvent(
        const CalendarEvent(
          id: 'test',
          date: '2026-09-20',
          title: '집중 시간',
          duration: 30,
          color: '#3B82F6',
          time: '10:00',
        ),
        DateTime.utc(2026, 9, 20, 1),
        DateTime.utc(2026, 9, 20, 1, 30),
      );
      await LiveActivity.start(event);
      await LiveActivity.update(event);
      await LiveActivity.end();
      expect(calls.map((call) => call.method), [
        'status',
        'start',
        'update',
        'end',
      ]);
      expect(calls[1].arguments, event.payload);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('Android settings exposes live updates', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          theme: lightTheme,
          accountLabel: '게스트',
          onLogout: () {},
          onLiveActivities: () => opened = true,
        ),
      ),
    );
    await tester.tap(find.text('일정 실시간 업데이트'));
    expect(opened, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  test('candidates include imminent events but exclude distant, all-day and expired events', () {
    tz_data.initializeTimeZones();
    final now = DateTime.utc(2026, 9, 20, 10);
    CalendarEvent event(String title, String? time, int duration) =>
        CalendarEvent(
          id: title,
          date: '2026-09-20',
          title: title,
          time: time,
          duration: duration,
          color: '#3B82F6',
        );
    final result = liveActivityCandidates(
      {
        '2026-09-20': [
          event('ongoing', '09:50', 30),
          event('soon', '10:10', 30),
          event('later', '10:11', 30),
          event('ended', '09:00', 30),
          event('all-day', null, 60),
        ],
      },
      tz.UTC,
      now,
    );
    expect(result.map((event) => event.event.title), ['ongoing', 'soon']);
  });
}
