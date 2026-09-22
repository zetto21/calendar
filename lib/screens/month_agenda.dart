import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/date_utils.dart' as dates;
import '../models/calendar_event.dart';
import '../theme/app_theme.dart';
import 'month_view.dart';
import '../widgets/liquid_glass.dart';
import 'time_grid_view.dart';
import '../platform.dart';

/// Calendar and selected-day agenda share the available screen height.
class MonthAgenda extends StatefulWidget {
  final AppTheme theme;
  final DateTime viewDate;
  final EventMap events;
  final String selectedKey;
  final bool showHolidays;
  final Map<String, String> holidayNames;
  final Map<String, String> solarTermNames;
  final Map<String, List<String>> anniversaryNames;
  final bool showLunar;
  final ValueChanged<String> onSelectDate;
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;
  final ValueChanged<CalendarEvent> onEventPress;
  final void Function(DateTime, int) onSlotPress;
  final ValueChanged<VoidCallback>? onCollapseReady;
  final void Function(CalendarEvent event, DateTime date)? onEventMove;
  final ValueChanged<CalendarEvent?>? onEventHover;
  const MonthAgenda({
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
    this.onPreviousMonth,
    this.onNextMonth,
    required this.onEventPress,
    required this.onSlotPress,
    this.onCollapseReady,
    this.onEventMove,
    this.onEventHover,
  });

  @override
  State<MonthAgenda> createState() => _MonthAgendaState();
}

class _MonthAgendaState extends State<MonthAgenda> {
  bool _open = false;
  bool _timeline = false;
  double _drag = 0;
  double _horizontalDrag = 0;
  bool _collapseImmediately = false;

  void _collapse() {
    if (!_open) return;
    setState(() {
      _collapseImmediately = true;
      _open = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _collapseImmediately = false);
    });
  }

  @override
  void initState() {
    super.initState();
    widget.onCollapseReady?.call(_collapse);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final day = dates.parseDateKey(widget.selectedKey);
    final anniversaries = [
      for (final name
          in widget.anniversaryNames[widget.selectedKey] ?? const <String>[])
        CalendarEvent(
          id: 'anniversary:${widget.selectedKey}:$name',
          date: widget.selectedKey,
          title: name,
          description: '법정 기념일',
          duration: 1440,
          color: '#707078',
        ),
    ];
    final events = [...anniversaries, ...?widget.events[widget.selectedKey]]
      ..sort((a, b) => (a.time ?? '').compareTo(b.time ?? ''));
    final holidayName = widget.showHolidays
        ? widget.holidayNames[widget.selectedKey]
        : null;
    final rows =
        dates
            .getMonthMatrix(widget.viewDate.year, widget.viewDate.month - 1)
            .length ~/
        7;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (useDesktopLayout && constraints.maxWidth >= 760) {
          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: MonthView(
                    theme: theme,
                    viewDate: widget.viewDate,
                    events: widget.events,
                    selectedKey: widget.selectedKey,
                    showHolidays: widget.showHolidays,
                    holidayNames: widget.holidayNames,
                    solarTermNames: widget.solarTermNames,
                    anniversaryNames: widget.anniversaryNames,
                    showLunar: widget.showLunar,
                    rowHeight: math.max(
                      110,
                      (constraints.maxHeight - 28) / rows,
                    ),
                    onSelectDate: widget.onSelectDate,
                    onEventMove: widget.onEventMove,
                    onEventHover: widget.onEventHover,
                  ),
                ),
              ),
              Container(
                key: const ValueKey('macos-day-agenda'),
                width: constraints.maxWidth >= 1000 ? 280 : 230,
                decoration: BoxDecoration(
                  color: theme.bg,
                  border: Border(
                    left: BorderSide(color: theme.border, width: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
                      child: Text(
                        '${day.month}월 ${day.day}일 ${dates.weekdays[day.weekday % 7]}요일',
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Text(
                        '${widget.showLunar ? '${dates.formatLunarDate(day) ?? ''} · ' : ''}일정 ${events.length}개',
                        style: TextStyle(color: theme.textMuted, fontSize: 12),
                      ),
                    ),
                    if (holidayName != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Text(
                          holidayName,
                          style: TextStyle(color: theme.danger, fontSize: 13),
                        ),
                      ),
                    Divider(height: 1, color: theme.border),
                    Expanded(
                      child: events.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.event_available_outlined,
                                    color: theme.textMuted,
                                    size: 30,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '예정된 일정이 없습니다',
                                    style: TextStyle(
                                      color: theme.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: events.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final event = events[index];
                                final special = event.id.startsWith(
                                  'anniversary:',
                                );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: _AgendaRow(
                                    theme: theme,
                                    event: event,
                                    onTap: special
                                        ? null
                                        : () => widget.onEventPress(event),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          );
        }
        final compactHeight = math.min(
          rows * 51.0 + 28,
          constraints.maxHeight * 0.65,
        );
        return PopScope(
          canPop: !_open,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) setState(() => _open = false);
          },
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => _horizontalDrag = 0,
                onHorizontalDragUpdate: (details) =>
                    _horizontalDrag += details.delta.dx,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  final distance = _horizontalDrag;
                  _horizontalDrag = 0;
                  if (distance.abs() < 48 && velocity.abs() < 300) return;
                  final direction = velocity.abs() >= 300 ? velocity : distance;
                  if (direction < 0) {
                    widget.onNextMonth?.call();
                  } else {
                    widget.onPreviousMonth?.call();
                  }
                },
                onHorizontalDragCancel: () => _horizontalDrag = 0,
                child: AnimatedContainer(
                  duration:
                      _collapseImmediately ||
                          MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  height: _open ? compactHeight : constraints.maxHeight,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: MonthView(
                      theme: theme,
                      viewDate: widget.viewDate,
                      events: widget.events,
                      selectedKey: widget.selectedKey,
                      showHolidays: widget.showHolidays,
                      holidayNames: widget.holidayNames,
                      solarTermNames: widget.solarTermNames,
                      anniversaryNames: widget.anniversaryNames,
                      showLunar: widget.showLunar,
                      compact: _open,
                      rowHeight: math.max(
                        90,
                        (constraints.maxHeight - 28) / rows,
                      ),
                      onSelectDate: (key) {
                        setState(() => _open = true);
                        widget.onSelectDate(key);
                      },
                    ),
                  ),
                ),
              ),
              if (_open)
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    child: LiquidGlass(
                      // The outer clip rounds only the top. Keeping the glass
                      // square at the bottom removes the black gap below it.
                      radius: 0,
                      child: Column(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragStart: (_) => _drag = 0,
                            onVerticalDragUpdate: (details) =>
                                _drag += details.delta.dy,
                            onVerticalDragEnd: (details) {
                              if (_drag > 40 ||
                                  (details.primaryVelocity ?? 0) > 600) {
                                setState(() => _open = false);
                              }
                            },
                            child: Column(
                              children: [
                                Semantics(
                                  button: true,
                                  label: '일정 목록 접기',
                                  container: true,
                                  child: InkWell(
                                    onTap: () => setState(() => _open = false),
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: 24,
                                      child: Center(
                                        child: Container(
                                          width: 32,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: theme.textSecondary,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Text(
                                              '${day.month}. ${day.day}. ${dates.weekdays[day.weekday % 7]}',
                                              style: TextStyle(
                                                color: theme.text,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            if (widget.showLunar &&
                                                dates.formatLunarDate(day) !=
                                                    null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 8,
                                                ),
                                                child: Text(
                                                  dates.formatLunarDate(day)!,
                                                  style: TextStyle(
                                                    color: theme.textMuted,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (holidayName?.isNotEmpty == true)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: Text(
                                            holidayName!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: theme.danger,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      IconButton(
                                        tooltip: _timeline ? '목록 보기' : '시간표 보기',
                                        onPressed: () => setState(
                                          () => _timeline = !_timeline,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor: theme.bgSecondary,
                                          foregroundColor: theme.textSecondary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        icon: Icon(
                                          _timeline
                                              ? Icons.list_alt_outlined
                                              : Icons.view_timeline_outlined,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _timeline
                                ? TimeGridView(
                                    embedded: true,
                                    key: ValueKey(widget.selectedKey),
                                    theme: theme,
                                    days: [day],
                                    events: {
                                      ...widget.events,
                                      widget.selectedKey: events,
                                    },
                                    onSlotPress: widget.onSlotPress,
                                    onEventPress: (event) {
                                      if (!anniversaries.contains(event)) {
                                        widget.onEventPress(event);
                                      }
                                    },
                                  )
                                : ListView(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      100,
                                    ),
                                    children: [
                                      if (events.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          child: Text(
                                            '일정이 없습니다',
                                            style: TextStyle(
                                              color: theme.textMuted,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      for (final event in events)
                                        _AgendaRow(
                                          theme: theme,
                                          event: event,
                                          onTap: anniversaries.contains(event)
                                              ? null
                                              : () =>
                                                    widget.onEventPress(event),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AgendaRow extends StatelessWidget {
  final AppTheme theme;
  final CalendarEvent event;
  final VoidCallback? onTap;
  const _AgendaRow({required this.theme, required this.event, this.onTap});

  String _clock(int minutes) =>
      '${(minutes ~/ 60) % 12 == 0 ? 12 : (minutes ~/ 60) % 12}:${(minutes % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final start = event.time == null ? 0 : dates.minutesFromTime(event.time!);
    final end = start + event.duration;
    return Semantics(
      button: onTap != null,
      label: onTap != null
          ? '${event.title} 일정 수정'
          : '${event.title} 종일 ${event.description ?? ''}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: useDesktopLayout
                      ? 100 * MediaQuery.textScalerOf(context).scale(12) / 12
                      : 62,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            event.time == null
                                ? '종일'
                                : start < 720
                                ? '오전'
                                : '오후',
                            style: TextStyle(
                              color: theme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (event.time != null)
                            Text(
                              _clock(start),
                              style: TextStyle(color: theme.text, fontSize: 13),
                            ),
                        ],
                      ),
                      if (event.time != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              end >= 1440
                                  ? '다음 날'
                                  : start ~/ 720 != end ~/ 720
                                  ? '오후'
                                  : '',
                              style: TextStyle(
                                color: theme.textMuted,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              _clock(end),
                              style: TextStyle(
                                color: theme.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 3,
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(
                    color: withAlpha(colorFromHex(event.color), 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (event.location?.isNotEmpty ?? false)
                        Text(
                          event.location!,
                          style: TextStyle(
                            color: theme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      if (event.recurrence != null)
                        Text(
                          '↻ 반복 일정',
                          style: TextStyle(
                            color: theme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
