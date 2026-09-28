import '../models/calendar_event.dart';
import 'date_utils.dart' as dates;

/// Fractions of a day column. Adjacent cards overlap while retaining an
/// exposed strip for pointer access; events never move vertically.
typedef TimeEventPlacement = ({double left, double width});

Map<String, TimeEventPlacement> layoutTimeEvents(List<CalendarEvent> events) {
  final sorted = [...events]
    ..sort((a, b) {
      final start = a.time!.compareTo(b.time!);
      if (start != 0) return start;
      final duration = b.duration.compareTo(a.duration);
      return duration != 0 ? duration : a.id.compareTo(b.id);
    });
  final result = <String, TimeEventPlacement>{};
  var group = <CalendarEvent>[];
  var groupEnd = -1;

  void flush() {
    if (group.isEmpty) return;
    final lanes = <List<CalendarEvent>>[];
    final ends = <int>[];
    final laneById = <String, int>{};
    for (final event in group) {
      final start = dates.minutesFromTime(event.time!);
      var lane = ends.indexWhere((end) => end <= start);
      if (lane == -1) {
        lane = lanes.length;
        lanes.add([]);
        ends.add(0);
      }
      lanes[lane].add(event);
      ends[lane] = start + event.duration;
      laneById[event.id] = lane;
    }
    final units = lanes.length + 0.5;
    for (final event in group) {
      final lane = laneById[event.id]!;
      final start = dates.minutesFromTime(event.time!);
      final end = start + event.duration;
      var span = 1;
      for (var next = lane + 1; next < lanes.length; next++) {
        if (lanes[next].any((other) {
          final otherStart = dates.minutesFromTime(other.time!);
          return start < otherStart + other.duration && otherStart < end;
        })) {
          break;
        }
        span++;
      }
      result[event.id] = (left: lane / units, width: (span + 0.5) / units);
    }
    group = [];
  }

  for (final event in sorted) {
    final start = dates.minutesFromTime(event.time!);
    if (group.isNotEmpty && start >= groupEnd) flush();
    if (group.isEmpty) groupEnd = start;
    group.add(event);
    if (start + event.duration > groupEnd) groupEnd = start + event.duration;
  }
  flush();
  return result;
}
