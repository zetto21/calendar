import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/native/live_activity.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  final zone = tz.getLocation('Asia/Seoul');
  final now = tz.TZDateTime(zone, 2026, 10, 6, 12);
  CalendarEvent event(String id, String? time, {String date = '2026-10-06'}) =>
      CalendarEvent(
        id: id,
        date: date,
        title: id,
        time: time,
        duration: 60,
        color: '#3B82F6',
      );

  test('automatic queue prioritizes ongoing events then upcoming today', () {
    final candidates = automaticLiveEvents(
      {
        '2026-10-06': [
          event('later', '18:00'),
          event('finished', '09:00'),
          event('all-day', null),
          event('ongoing', '11:30'),
          event('next', '13:00'),
        ],
        '2026-10-07': [event('tomorrow', '09:00', date: '2026-10-07')],
      },
      zone,
      now,
    );
    expect(candidates.map((e) => e.event.id), ['ongoing', 'next', 'later']);
    final afterFirst = automaticLiveEvents(
      {'2026-10-06': candidates.map((e) => e.event).toList()},
      zone,
      now.add(const Duration(hours: 1)),
    );
    expect(afterFirst.map((e) => e.event.id), ['next', 'later']);
  });

  test(
    'sync transmits the queue and empty queue clears automatic updates',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('calendar_app/live_activity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final item = LiveCalendarEvent(
        event('ongoing', '11:30'),
        now,
        now.add(const Duration(hours: 1)),
      );
      await LiveActivity.syncAutomatic([item]);
      await LiveActivity.syncAutomatic([]);
      expect(calls.map((call) => call.method), [
        'syncAutomatic',
        'syncAutomatic',
      ]);
      expect(calls.first.arguments, {
        'events': [item.payload],
      });
      expect(calls.last.arguments, {'events': []});
    },
  );
}
