import '../models/calendar_event.dart';
import 'date_utils.dart' as dates;

(String, String) calendarEventRange(
  ViewMode view,
  DateTime anchor,
  DateTime now,
) {
  if (view == ViewMode.list) {
    // Include overnight events, and expand upcoming recurring/imported events
    // independently of the month the user viewed before opening the list.
    final today = DateTime(now.year, now.month, now.day);
    return (
      dates.toDateKey(today.subtract(const Duration(days: 7))),
      dates.toDateKey(DateTime(today.year + 1, today.month, today.day)),
    );
  }
  return (
    dates.toDateKey(DateTime(anchor.year, anchor.month - 1, 24)),
    dates.toDateKey(DateTime(anchor.year, anchor.month + 1, 7)),
  );
}
