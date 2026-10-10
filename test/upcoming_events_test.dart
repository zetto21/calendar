import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_app_flutter/logic/upcoming_events.dart';
import 'package:calendar_app_flutter/models/calendar_event.dart';

void main() {
  CalendarEvent event({
    String date = '2026-10-10',
    String? time,
    int duration = 60,
    String? endsAt,
  }) => CalendarEvent(
    id: 'test',
    date: date,
    title: '일정',
    time: time,
    duration: duration,
    color: '#7657FF',
    endsAt: endsAt,
  );

  test('keeps ongoing and future events, hides events at their end', () {
    final now = DateTime(2026, 10, 10, 12);
    expect(isUpcomingEvent(event(time: '10:00'), now), isFalse);
    expect(isUpcomingEvent(event(time: '11:00'), now), isFalse);
    expect(isUpcomingEvent(event(time: '11:30'), now), isTrue);
    expect(isUpcomingEvent(event(time: '13:00'), now), isTrue);
  });

  test('all-day events remain through today and disappear at midnight', () {
    expect(isUpcomingEvent(event(), DateTime(2026, 10, 10, 23, 59)), isTrue);
    expect(isUpcomingEvent(event(), DateTime(2026, 10, 11)), isFalse);
    expect(
      isUpcomingEvent(event(date: '2026-10-09'), DateTime(2026, 10, 10)),
      isFalse,
    );
  });

  test('keeps overnight events until their end', () {
    final overnight = event(date: '2026-10-09', time: '23:30', duration: 120);
    expect(isUpcomingEvent(overnight, DateTime(2026, 10, 10, 1)), isTrue);
    expect(isUpcomingEvent(overnight, DateTime(2026, 10, 10, 1, 30)), isFalse);
  });

  test('uses the explicit end instant for timezone-aware events', () {
    final zoned = event(time: '09:00', endsAt: '2026-10-10T10:00:00+09:00');
    expect(isUpcomingEvent(zoned, DateTime.utc(2026, 10, 10, 0, 59)), isTrue);
    expect(isUpcomingEvent(zoned, DateTime.utc(2026, 10, 10, 1)), isFalse);
  });
}
