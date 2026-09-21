import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/date_utils.dart' as date_utils;
import '../models/calendar_event.dart';
import '../theme/app_theme.dart';

const double _hourHeight = 56;
const double _labelWidth = 42;

/// Port of components/TimeGridView.tsx: an hour-by-hour grid (day or week),
/// an all-day chip row, and a live "now" line.
class TimeGridView extends StatefulWidget {
  final bool embedded;
  final AppTheme theme;
  final List<DateTime> days;
  final EventMap events;
  final void Function(DateTime date, int hour) onSlotPress;
  final ValueChanged<CalendarEvent> onEventPress;
  final void Function(CalendarEvent event, DateTime date, String? time)?
  onEventMove;
  final void Function(CalendarEvent event, int duration)? onEventResize;
  final ValueChanged<CalendarEvent?>? onEventHover;
  final DateTime? selectedDate;
  final int? selectedHour;

  const TimeGridView({
    super.key,
    this.embedded = false,
    required this.theme,
    required this.days,
    required this.events,
    required this.onSlotPress,
    required this.onEventPress,
    this.onEventMove,
    this.onEventResize,
    this.onEventHover,
    this.selectedDate,
    this.selectedHour,
  });

  @override
  State<TimeGridView> createState() => _TimeGridViewState();
}

class _TimeGridViewState extends State<TimeGridView> {
  final _scrollController = ScrollController();
  DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = DateTime.now()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hour = widget.days.any((d) => date_utils.isSameDay(d, _now))
          ? (_now.hour - 1).clamp(0, 23)
          : 7;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_hourHeight * hour);
      }
    });
  }

  @override
  void didUpdateWidget(TimeGridView old) {
    super.didUpdateWidget(old);
    final hour = widget.selectedHour;
    if (hour == null || hour == old.selectedHour) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final top = _hourHeight * hour;
    final visibleTop = position.pixels;
    final visibleBottom = visibleTop + position.viewportDimension - 120;
    if (top < visibleTop) {
      _scrollController.animateTo(
        top.clamp(0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    } else if (top + _hourHeight > visibleBottom) {
      _scrollController.animateTo(
        (top + _hourHeight - position.viewportDimension + 120).clamp(
          0,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _draggableAllDay(CalendarEvent e) {
    final chip = _AllDayChip(
      theme: widget.theme,
      event: e,
      onTap: () => widget.onEventPress(e),
    );
    if (widget.onEventMove == null || !isMovableEvent(e)) return chip;
    return MouseRegion(
      onEnter: (_) => widget.onEventHover?.call(e),
      onExit: (_) => widget.onEventHover?.call(null),
      child: Draggable<CalendarEvent>(
        data: e,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: 140, child: chip),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: chip),
        child: chip,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildGrid(context, constraints.maxWidth),
  );

  Widget _buildGrid(BuildContext context, double width) {
    final colWidth = (width - _labelWidth) / widget.days.length;
    final allDayByDate = widget.days
        .map(
          (d) =>
              (widget.events[date_utils.toDateKey(d)] ??
                      const <CalendarEvent>[])
                  .where((e) => e.time == null)
                  .toList(),
        )
        .toList();
    final hasAllDay = allDayByDate.any((list) => list.isNotEmpty);

    return Column(
      children: [
        if (!widget.embedded)
          Row(
            children: [
              const SizedBox(width: _labelWidth),
              for (final d in widget.days)
                SizedBox(
                  width: colWidth,
                  child: Column(
                    children: [
                      Text(
                        date_utils.weekdays[d.weekday % 7],
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.theme.textMuted,
                        ),
                      ),
                      Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: date_utils.isSameDay(d, _now)
                              ? widget.theme.accent
                              : null,
                        ),
                        child: Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 15,
                            color: date_utils.isSameDay(d, _now)
                                ? Colors.white
                                : widget.theme.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        if (hasAllDay)
          Container(
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: widget.theme.border),
              ),
            ),
            constraints: const BoxConstraints(minHeight: 34),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: _labelWidth,
                  alignment: Alignment.center,
                  color: widget.theme.bgSecondary,
                  child: Text(
                    '하루종일',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      color: widget.theme.textSecondary,
                    ),
                  ),
                ),
                for (var i = 0; i < widget.days.length; i++)
                  DragTarget<CalendarEvent>(
                    onWillAcceptWithDetails: (details) =>
                        widget.onEventMove != null &&
                        details.data.time == null &&
                        details.data.date !=
                            date_utils.toDateKey(widget.days[i]),
                    onAcceptWithDetails: (details) =>
                        widget.onEventMove!(details.data, widget.days[i], null),
                    builder: (context, candidates, _) => Container(
                      width: colWidth,
                      color: candidates.isNotEmpty
                          ? widget.theme.accent.withValues(alpha: 0.12)
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          for (final e in allDayByDate[i]) _draggableAllDay(e),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _labelWidth,
                    child: Column(
                      children: [
                        for (final h in date_utils.hoursOfDay)
                          SizedBox(
                            height: _hourHeight,
                            child: h == 0
                                ? null
                                : Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Text(
                                        date_utils.formatHourLabel(h),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: widget.theme.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                  for (final d in widget.days)
                    _DayColumn(
                      theme: widget.theme,
                      day: d,
                      width: colWidth,
                      now: _now,
                      events: widget.events,
                      onSlotPress: widget.onSlotPress,
                      onEventPress: widget.onEventPress,
                      onEventMove: widget.onEventMove,
                      onEventResize: widget.onEventResize,
                      onEventHover: widget.onEventHover,
                      selectedHour:
                          widget.selectedDate != null &&
                              date_utils.isSameDay(d, widget.selectedDate!)
                          ? widget.selectedHour
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AllDayChip extends StatelessWidget {
  final AppTheme theme;
  final CalendarEvent event;
  final VoidCallback onTap;
  const _AllDayChip({
    required this.theme,
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tone = eventCardTone(colorFromHex(event.color), theme);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: tone.title,
              ),
            ),
            if (event.location != null && event.location!.isNotEmpty)
              Text(
                event.location!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: tone.detail),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayColumn extends StatefulWidget {
  final AppTheme theme;
  final DateTime day;
  final double width;
  final DateTime now;
  final EventMap events;
  final void Function(DateTime date, int hour) onSlotPress;
  final ValueChanged<CalendarEvent> onEventPress;
  final void Function(CalendarEvent event, DateTime date, String? time)?
  onEventMove;
  final void Function(CalendarEvent event, int duration)? onEventResize;
  final ValueChanged<CalendarEvent?>? onEventHover;
  final int? selectedHour;

  const _DayColumn({
    required this.theme,
    required this.day,
    required this.width,
    required this.now,
    required this.events,
    required this.onSlotPress,
    required this.onEventPress,
    this.onEventMove,
    this.onEventResize,
    this.onEventHover,
    this.selectedHour,
  });

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  final _columnKey = GlobalKey();

  /// Snap a dropped block's top edge to 15-minute steps.
  String _timeAt(Offset globalTopLeft) {
    final box = _columnKey.currentContext!.findRenderObject() as RenderBox;
    final y = box.globalToLocal(globalTopLeft).dy;
    final minutes = ((y / _hourHeight * 60) / 15).round() * 15;
    return date_utils.timeFromMinutes(minutes.clamp(0, 24 * 60 - 15));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final day = widget.day;
    final dateKey = date_utils.toDateKey(day);
    final timedEvents = (widget.events[dateKey] ?? const <CalendarEvent>[])
        .where((e) => e.time != null)
        .toList();
    final isToday = date_utils.isSameDay(day, widget.now);
    final nowMinutes = widget.now.hour * 60 + widget.now.minute;

    return DragTarget<CalendarEvent>(
      onWillAcceptWithDetails: (details) => widget.onEventMove != null,
      onAcceptWithDetails: (details) {
        if (details.data.time == null) return;
        widget.onEventMove!(details.data, day, _timeAt(details.offset));
      },
      builder: (context, candidates, _) => SizedBox(
        key: _columnKey,
        width: widget.width,
        child: Stack(
          children: [
            Column(
              children: [
                for (final h in date_utils.hoursOfDay)
                  InkWell(
                    onTap: () => widget.onSlotPress(day, h),
                    child: Container(
                      height: _hourHeight,
                      decoration: BoxDecoration(
                        color: widget.selectedHour == h
                            ? theme.accent.withValues(alpha: 0.12)
                            : (candidates.isNotEmpty
                                  ? theme.accent.withValues(alpha: 0.04)
                                  : null),
                        border: Border(
                          top: BorderSide(color: theme.border, width: 0.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            for (final e in timedEvents)
              _EventBlock(
                theme: theme,
                event: e,
                onTap: () => widget.onEventPress(e),
                movable: widget.onEventMove != null && isMovableEvent(e),
                onResize: widget.onEventResize == null
                    ? null
                    : (duration) => widget.onEventResize!(e, duration),
                onHover: widget.onEventHover,
              ),
            if (isToday)
              Positioned(
                top: (nowMinutes / 60) * _hourHeight,
                left: 0,
                right: 0,
                child: Container(height: 1.5, color: theme.danger),
              ),
          ],
        ),
      ),
    );
  }
}

class _EventBlock extends StatefulWidget {
  final AppTheme theme;
  final CalendarEvent event;
  final VoidCallback onTap;
  final bool movable;
  final ValueChanged<int>? onResize;
  final ValueChanged<CalendarEvent?>? onHover;
  const _EventBlock({
    required this.theme,
    required this.event,
    required this.onTap,
    this.movable = false,
    this.onResize,
    this.onHover,
  });

  @override
  State<_EventBlock> createState() => _EventBlockState();
}

class _EventBlockState extends State<_EventBlock> {
  /// Pixels the bottom edge has been dragged while resizing.
  double _resizePx = 0;

  int get _duration => (widget.event.duration + _resizePx / _hourHeight * 60)
      .round()
      .clamp(15, 24 * 60);

  Widget _body(double height, {double? width}) {
    final event = widget.event;
    final tone = eventCardTone(colorFromHex(event.color), widget.theme);
    return Container(
      width: width,
      padding: EdgeInsets.symmetric(
        horizontal: 6,
        vertical: height < 30 ? 2 : 6,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: tone.title,
            ),
          ),
          if (height > 38 &&
              event.location != null &&
              event.location!.isNotEmpty)
            Text(
              event.location!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: tone.detail),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final startMin = date_utils.minutesFromTime(event.time!);
    final top = (startMin / 60) * _hourHeight;
    final height = (((_duration) / 60) * _hourHeight)
        .clamp(22, double.infinity)
        .toDouble();
    Widget content = InkWell(onTap: widget.onTap, child: _body(height));
    if (widget.movable) {
      content = MouseRegion(
        cursor: SystemMouseCursors.grab,
        onEnter: (_) => widget.onHover?.call(event),
        onExit: (_) => widget.onHover?.call(null),
        child: Draggable<CalendarEvent>(
          data: event,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: SizedBox(
                width: 140,
                height: height,
                child: _body(height, width: 140),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: content),
          child: content,
        ),
      );
    }
    return Positioned(
      top: top,
      left: 2,
      right: 12,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(child: content),
          if (widget.movable && widget.onResize != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) =>
                      setState(() => _resizePx += d.delta.dy),
                  onVerticalDragEnd: (_) {
                    final snapped = (_duration / 15).round() * 15;
                    setState(() => _resizePx = 0);
                    widget.onResize!(snapped.clamp(15, 24 * 60));
                  },
                  onVerticalDragCancel: () => setState(() => _resizePx = 0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
