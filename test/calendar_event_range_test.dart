import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_app_flutter/logic/calendar_event_range.dart';
import 'package:calendar_app_flutter/logic/recurrence.dart';
import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  test('list range and future repeats do not depend on the previously viewed month', () {
    final now = DateTime(2026, 10, 11);
    final october = calendarEventRange(
      ViewMode.list,
      DateTime(2026, 10, 11),
      now,
    );
    final november = calendarEventRange(
      ViewMode.list,
      DateTime(2026, 11, 11),
      now,
    );
    expect(october, november);
    const event = CalendarEvent(
      id: 'repeat',
      date: '2026-10-15',
      title: '반복',
      duration: 60,
      time: '10:00',
      color: '#3B82F6',
      recurrence: EventRecurrence(frequency: RepeatFrequency.monthly),
    );
    final expanded = expandEvents(
      {
        '2026-10-15': [event],
      },
      october.$1,
      october.$2,
      tz.UTC,
    );
    expect(expanded['2026-11-15'], isNotEmpty);
    expect(expanded['2027-01-15'], isNotEmpty);
  });

  test('month range follows the displayed month', () {
    expect(
      calendarEventRange(
        ViewMode.month,
        DateTime(2026, 11, 11),
        DateTime(2026, 10, 11),
      ),
      ('2026-10-24', '2026-12-07'),
    );
  });
}
