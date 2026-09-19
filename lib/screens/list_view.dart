import 'package:flutter/material.dart';

import '../logic/date_utils.dart' as date_utils;
import '../models/calendar_event.dart';
import '../theme/app_theme.dart';

/// Port of components/ListView.tsx: a flat, date-grouped agenda of every event.
class EventListView extends StatelessWidget {
  final AppTheme theme;
  final EventMap events;
  final ValueChanged<CalendarEvent> onEventPress;

  const EventListView({
    super.key,
    required this.theme,
    required this.events,
    required this.onEventPress,
  });

  @override
  Widget build(BuildContext context) {
    final keys = events.keys.where((key) => events[key]!.isNotEmpty).toList()
      ..sort();
    if (keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        child: Text(
          '일정이 없습니다',
          style: TextStyle(color: theme.textMuted, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 112),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        final date = date_utils.parseDateKey(key);
        final dayEvents = [...events[key]!]
          ..sort((a, b) {
            if (a.time == null) return -1;
            if (b.time == null) return 1;
            return date_utils
                .minutesFromTime(a.time!)
                .compareTo(date_utils.minutesFromTime(b.time!));
          });
        return Column(
          children: [
            for (
              var eventIndex = 0;
              eventIndex < dayEvents.length;
              eventIndex++
            )
              _EventRow(
                theme: theme,
                date: date,
                showDate: eventIndex == 0,
                event: dayEvents[eventIndex],
                onTap: () => onEventPress(dayEvents[eventIndex]),
              ),
          ],
        );
      },
    );
  }
}

class _EventRow extends StatelessWidget {
  final AppTheme theme;
  final DateTime date;
  final bool showDate;
  final CalendarEvent event;
  final VoidCallback onTap;

  const _EventRow({
    required this.theme,
    required this.date,
    required this.showDate,
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(event.color);
    final weekdayColor = date.weekday == DateTime.sunday
        ? const Color(0xFFFF6B52)
        : date.weekday == DateTime.saturday
        ? const Color(0xFF0A84FF)
        : theme.text;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 94),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.border.withValues(alpha: 0.65)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: showDate
                  ? Column(
                      children: [
                        Text(
                          date_utils.weekdays[date.weekday % 7],
                          style: TextStyle(
                            color: weekdayColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            color: weekdayColor,
                            fontSize: 27,
                            fontWeight: FontWeight.w500,
                            height: 1,
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
            SizedBox(
              width: 7,
              height: 76,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (event.time != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _timeRange(),
                        style: TextStyle(color: theme.text, fontSize: 15),
                      ),
                    ],
                    if (event.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeRange() {
    final start = date_utils.minutesFromTime(event.time!);
    final end = date_utils.timeFromMinutes(start + event.duration);
    return '${date_utils.formatTimeLabel(event.time!)} – ${date_utils.formatTimeLabel(end)}';
  }
}
