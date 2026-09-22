import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

import '../logic/date_utils.dart' as date_utils;
import '../models/calendar_event.dart';
import '../theme/app_theme.dart';
import '../platform.dart';

/// Month grid matching the expanded event bars and compact agenda layout.
class MonthView extends StatelessWidget {
  final AppTheme theme;
  final DateTime viewDate;
  final EventMap events;
  final String? selectedKey;
  final bool showHolidays;
  final Map<String, String> holidayNames;
  final Map<String, String> solarTermNames;
  final Map<String, List<String>> anniversaryNames;
  final bool showLunar;
  final ValueChanged<String> onSelectDate;
  final bool compact;
  final double rowHeight;
  final void Function(CalendarEvent event, DateTime date)? onEventMove;
  final ValueChanged<CalendarEvent?>? onEventHover;

  const MonthView({
    super.key,
    required this.theme,
    required this.viewDate,
    required this.events,
    required this.selectedKey,
    this.showHolidays = true,
    this.holidayNames = const {},
    this.solarTermNames = const {},
    this.anniversaryNames = const {},
    this.showLunar = false,
    required this.onSelectDate,
    this.compact = false,
    this.rowHeight = 108,
    this.onEventMove,
    this.onEventHover,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final cells = date_utils.getMonthMatrix(viewDate.year, viewDate.month - 1);

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: Center(
                    child: Text(
                      date_utils.weekdays[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: i == 0
                            ? const Color(0xFFEF4444)
                            : i == 6
                            ? const Color(0xFF3B82F6)
                            : theme.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisExtent: compact ? 51 : rowHeight,
          padding: EdgeInsets.zero,
          children: [
            for (final cell in cells)
              _MonthCell(
                theme: theme,
                cell: cell,
                today: today,
                events: events,
                selectedKey: selectedKey,
                showHolidays: showHolidays,
                holidayNames: holidayNames,
                solarTermNames: solarTermNames,
                anniversaryNames: anniversaryNames,
                showLunar: showLunar,
                onSelectDate: onSelectDate,
                compact: compact,
                onEventMove: onEventMove,
                onEventHover: onEventHover,
              ),
          ],
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  final AppTheme theme;
  final date_utils.MonthCell cell;
  final DateTime today;
  final EventMap events;
  final String? selectedKey;
  final bool showHolidays;
  final Map<String, String> holidayNames;
  final Map<String, String> solarTermNames;
  final Map<String, List<String>> anniversaryNames;
  final bool showLunar;
  final ValueChanged<String> onSelectDate;
  final bool compact;
  final void Function(CalendarEvent event, DateTime date)? onEventMove;
  final ValueChanged<CalendarEvent?>? onEventHover;

  const _MonthCell({
    required this.theme,
    required this.cell,
    required this.today,
    required this.events,
    required this.selectedKey,
    required this.showHolidays,
    required this.holidayNames,
    required this.solarTermNames,
    required this.anniversaryNames,
    required this.showLunar,
    required this.onSelectDate,
    required this.compact,
    this.onEventMove,
    this.onEventHover,
  });

  Widget _draggableChip(CalendarEvent event, double height, Widget chip) {
    if (onEventMove == null || !isMovableEvent(event)) return chip;
    return MouseRegion(
      onEnter: (_) => onEventHover?.call(event),
      onExit: (_) => onEventHover?.call(null),
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          onEventHover?.call(event);
          onSelectDate(event.date);
        },
        child: Draggable<CalendarEvent>(
          data: event,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              height: height - 4,
              constraints: const BoxConstraints(maxWidth: 160),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: colorFromHex(event.color).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: chip),
          child: chip,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = useDesktopLayout;
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final key = date_utils.toDateKey(cell.date);
    final holiday = holidayNames[key];
    final dayEvents = [
      if (showHolidays && holiday != null)
        CalendarEvent(
          id: 'holiday:$key',
          date: key,
          title: holiday,
          duration: 1440,
          color: '#FF526F',
        ),
      if (solarTermNames[key] case final String name)
        CalendarEvent(
          id: 'solarTerm:$key',
          date: key,
          title: name,
          duration: 1440,
          color: '#929297',
        ),
      for (final name in anniversaryNames[key] ?? const <String>[])
        CalendarEvent(
          id: 'anniversary:$key:$name',
          date: key,
          title: name,
          duration: 1440,
          color: '#707078',
        ),
      ...?events[key],
    ];
    bool isSpecialDay(CalendarEvent event) =>
        event.id == 'holiday:$key' ||
        event.id == 'solarTerm:$key' ||
        event.id.startsWith('anniversary:$key:');
    final isToday = date_utils.isSameDay(cell.date, today);
    final isSelected = selectedKey == key;
    final opacity = cell.inMonth ? 1.0 : 0.35;
    final weekday = cell.date.weekday % 7;

    if (desktop && !compact) {
      return DragTarget<CalendarEvent>(
        onWillAcceptWithDetails: (details) =>
            onEventMove != null && details.data.date != key,
        onAcceptWithDetails: (details) => onEventMove!(details.data, cell.date),
        builder: (context, candidates, _) => InkWell(
          onTap: () => onSelectDate(key),
          child: Container(
            decoration: BoxDecoration(
              color: candidates.isNotEmpty
                  ? theme.accent.withValues(alpha: 0.14)
                  : (isSelected ? theme.bgSecondary : theme.bg),
              border: Border(
                top: BorderSide(color: theme.border, width: 0.5),
                right: BorderSide(color: theme.border, width: 0.5),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(5, 6, 5, 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 25,
                      height: 25,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday
                            ? theme.text
                            : (isSelected ? theme.border : null),
                      ),
                      child: Text(
                        '${cell.date.day}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isToday
                              ? theme.bg
                              : (weekday == 0 || holiday != null
                                        ? const Color(0xFFFF526F)
                                        : weekday == 6
                                        ? const Color(0xFF7C85FF)
                                        : theme.text)
                                    .withValues(alpha: opacity),
                        ),
                      ),
                    ),
                    if (showLunar)
                      Expanded(
                        child: Text(
                          date_utils
                                  .formatLunarDate(cell.date)
                                  ?.replaceFirst('음력 ', '음 ') ??
                              '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: theme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final eventHeight =
                          14 + MediaQuery.textScalerOf(context).scale(12);
                      final slots = (constraints.maxHeight / eventHeight)
                          .floor()
                          .clamp(0, 20);
                      final overflow = dayEvents.length > slots;
                      final visible = overflow
                          ? (slots - 1).clamp(0, 20)
                          : slots;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final event in dayEvents.take(visible))
                            _draggableChip(
                              event,
                              eventHeight,
                              Tooltip(
                                message:
                                    '${event.title} · ${event.time == null ? '종일' : date_utils.formatTimeLabel(event.time!)}',
                                child: Container(
                                  height: eventHeight - 4,
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  decoration: BoxDecoration(
                                    color: event.time != null
                                        ? Colors.transparent
                                        : withAlpha(
                                            colorFromHex(event.color),
                                            (event.id.startsWith(
                                                      'anniversary:$key:',
                                                    )
                                                    ? 0.20
                                                    : 0.12) *
                                                opacity,
                                          ),
                                    borderRadius: BorderRadius.circular(5),
                                    border: isSpecialDay(event)
                                        ? null
                                        : Border(
                                            left: BorderSide(
                                              color: withAlpha(
                                                colorFromHex(event.color),
                                                0.6 * opacity,
                                              ),
                                              width: 3,
                                            ),
                                          ),
                                  ),
                                  child: Text(
                                    event.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          (isSpecialDay(event)
                                                  ? colorFromHex(event.color)
                                                  : theme.text)
                                              .withValues(alpha: opacity),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (overflow && slots > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                '+${dayEvents.length - visible}개 더',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.textMuted,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => onSelectDate(key),
      child: Container(
        decoration: BoxDecoration(
          color: !compact && isSelected ? theme.bgSecondary : theme.bg,
          border: compact
              ? null
              : Border(
                  top: BorderSide(color: theme.border, width: 0.5),
                  right: BorderSide(
                    color: desktop ? theme.border : Colors.transparent,
                    width: 0.5,
                  ),
                ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Container(
              width: compact ? 30 : (desktop ? 26 : 18),
              height: compact ? 30 : (desktop ? 26 : 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday
                    ? (theme.isDark
                          ? const Color(0xFFE9E9E7)
                          : const Color(0xFF262629))
                    : (isSelected ? theme.border : null),
              ),
              child: Text(
                '${cell.date.day}',
                style: TextStyle(
                  fontSize: compact ? 14 : (desktop ? 13 : 11),
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  color:
                      (isToday
                              ? theme.bg
                              : holiday != null || weekday == 0
                              ? const Color(0xFFFF526F)
                              : weekday == 6
                              ? const Color(0xFF7C85FF)
                              : theme.text)
                          .withValues(alpha: isToday ? 1 : opacity),
                ),
              ),
            ),
            const SizedBox(height: 2),
            if (!compact && showLunar)
              Text(
                date_utils
                        .formatLunarDate(cell.date)
                        ?.replaceFirst('음력 ', '') ??
                    '',
                style: TextStyle(
                  color: theme.textMuted.withValues(alpha: opacity),
                  fontSize: 8,
                ),
              ),
            if (!compact)
              Expanded(
                child: Column(
                  children: [
                    for (final event in dayEvents.take(3))
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: event.time != null
                              ? Colors.transparent
                              : android
                              ? colorFromHex(event.color)
                                    .withValues(alpha: opacity)
                              : withAlpha(
                                  colorFromHex(event.color),
                                  (event.id.startsWith('anniversary:$key:')
                                          ? 0.20
                                          : 0.12) *
                                      opacity,
                                ),
                          borderRadius: android
                              ? BorderRadius.circular(4)
                              : isSpecialDay(event)
                              ? BorderRadius.circular(2)
                              : null,
                          border: android || isSpecialDay(event)
                              ? null
                              : Border(
                                  left: BorderSide(
                                    color: withAlpha(
                                      colorFromHex(event.color),
                                      0.6 * opacity,
                                    ),
                                    width: 2,
                                  ),
                                ),
                        ),
                        child: android
                            ? Row(
                                children: [
                                  if (event.time != null) ...[
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: colorFromHex(event.color)
                                            .withValues(alpha: opacity),
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                  ],
                                  Expanded(
                                    child: Text(
                                      event.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: event.time != null
                                            ? theme.text.withValues(
                                                alpha: opacity,
                                              )
                                            : (ThemeData.estimateBrightnessForColor(
                                                        colorFromHex(
                                                          event.color,
                                                        ),
                                                      ) ==
                                                      Brightness.light
                                                  ? Colors.black87
                                                  : Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      (isSpecialDay(event)
                                              ? colorFromHex(event.color)
                                              : theme.text)
                                          .withValues(alpha: opacity),
                                ),
                              ),
                      ),
                    if (dayEvents.length > 3)
                      Text(
                        '+${dayEvents.length - 3}개 더',
                        style: TextStyle(fontSize: 10, color: theme.textMuted),
                      ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 3,
                children: [
                  for (final color in {
                    if (anniversaryNames[key]?.isNotEmpty ?? false) '#707078',
                    for (final e in events[key] ?? const <CalendarEvent>[])
                      e.color,
                  }.take(4))
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: colorFromHex(color),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
