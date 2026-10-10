import '../models/calendar_event.dart';

bool isUpcomingEvent(CalendarEvent event, DateTime now) {
  final date = DateTime.parse(event.date);
  if (event.isAllDay) {
    return DateTime(date.year, date.month, date.day + 1).isAfter(now);
  }
  final explicitEnd = DateTime.tryParse(event.endsAt ?? '');
  final time = event.time!.split(':');
  final end =
      explicitEnd ??
      DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(time[0]),
        int.parse(time[1]),
      ).add(Duration(minutes: event.duration));
  return end.isAfter(now);
}
