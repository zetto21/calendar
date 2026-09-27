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
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 112),
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
        final isToday = date_utils.toDateKey(DateTime.now()) == key;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
              child: Row(
                children: [
                  Text(
                    '${date.month}월 ${date.day}일',
                    style: TextStyle(
                      color: isToday ? theme.accent : theme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    date_utils.weekdays[date.weekday % 7],
                    style: TextStyle(color: theme.textMuted, fontSize: 12),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.accent.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '오늘',
                        style: TextStyle(
                          color: theme.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${dayEvents.length}개',
                    style: TextStyle(color: theme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            for (
              var eventIndex = 0;
              eventIndex < dayEvents.length;
              eventIndex++
            )
              _EventRow(
                theme: theme,
                date: date,
                showDate: false,
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
        constraints: BoxConstraints(minHeight: showDate ? 94 : 62),
        padding: EdgeInsets.symmetric(vertical: showDate ? 9 : 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.border.withValues(alpha: 0.65)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: showDate ? 60 : 0,
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
              height: showDate ? 76 : 46,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            SizedBox(width: showDate ? 24 : 12),
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
