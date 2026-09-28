import 'package:calendar_app_flutter/logic/time_event_layout.dart';
import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent event(String id, String time, int duration) => CalendarEvent(
  id: id,
  date: '2026-09-28',
  title: id,
  time: time,
  duration: duration,
  color: '#3B82F6',
);
void main() {
  test('adjacent events use full width without false overlaps', () {
    final result = layoutTimeEvents([
      event('a', '09:00', 15),
      event('b', '09:15', 30),
    ]);
    expect(result['a'], (left: 0.0, width: 1.0));
    expect(result['b'], (left: 0.0, width: 1.0));
  });
  test('lanes are reused and later independent events recover full width', () {
    final result = layoutTimeEvents([
      event('long', '09:00', 180),
      event('short', '09:00', 30),
      event('next', '09:30', 30),
      event('later', '12:00', 60),
    ]);
    expect(result['short']!.left, result['next']!.left);
    expect(
      result['long']!.left + result['long']!.width,
      greaterThan(result['short']!.left),
    );
    expect(result['later'], (left: 0.0, width: 1.0));
    for (final placement in result.values) {
      expect(placement.left + placement.width, lessThanOrEqualTo(1.00001));
    }
  });
}
