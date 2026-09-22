import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../logic/date_utils.dart' as date_utils;
import '../models/calendar_event.dart';
import '../theme/app_theme.dart';

const double _hourHeight = 56;
const double _labelWidth = 42;

/// Port of components/TimeGridView.tsx: an hour-by-hour grid (day or week),
/// an all-day chip row, and a live "now" line.
class TimeGridView extends StatefulWidget {
  final ValueChanged<int>? onShiftDays;
  final bool embedded;
  final VoidCallback? onPrevious, onNext;
  final AppTheme theme;
  final List<DateTime> days;
  final EventMap events;
  final void Function(DateTime date, int hour) onSlotPress;
  final ValueChanged<CalendarEvent> onEventPress;
  final void Function(CalendarEvent event, DateTime date, String? time)?
  onEventMove;
  final void Function(CalendarEvent event, String time, int duration)?
  onEventResize;
  final void Function(DateTime date, String time, int duration)? onRangeCreate;
  final ValueChanged<CalendarEvent?>? onEventHover;
  final DateTime? selectedDate;
  final int? selectedHour;

  const TimeGridView({
    super.key,
    this.embedded = false,
    this.onShiftDays,
    this.onPrevious,
    this.onNext,
    required this.theme,
    required this.days,
    required this.events,
    required this.onSlotPress,
    required this.onEventPress,
    this.onEventMove,
    this.onEventResize,
    this.onRangeCreate,
    this.onEventHover,
    this.selectedDate,
    this.selectedHour,
  });

  @override
  State<TimeGridView> createState() => _TimeGridViewState();
}

class _TimeGridViewState extends State<TimeGridView>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  DateTime _now = DateTime.now();
  Timer? _clock;
  Timer? _scrollIdle;
  double _horizontalDistance = 0;
  bool _scrollNavigated = false;
  double _columnWidth = 1;
  double _continuousOffset = 0;
  bool _shiftInProgress = false;

  void _scrollDays(double delta) {
    if (_outgoing == null && _transition.isAnimating) {
      _continuousOffset +=
          _transitionDrag *
          (1 - Curves.easeOutCubic.transform(_transition.value));
    }
    _transition.stop();
    _outgoing = null;
    _transitionDrag = 0;
    _dragOffset = 0;
    _transition.value = 1;
    setState(() => _continuousOffset += delta);
    final days = (-_continuousOffset / _columnWidth).truncate();
    if (days != 0) {
      _continuousOffset += days * _columnWidth;
      _shiftInProgress = true;
      widget.onShiftDays!(days);
    }
  }

  late final AnimationController _transition;
  TimeGridView? _outgoing;
  ScrollController? _outgoingScroll;
  double _direction = 1;
  double _dragOffset = 0;
  double _transitionDrag = 0;

  void _resetDrag() {
    if (_dragOffset == 0) return;
    _transitionDrag = _dragOffset;
    _dragOffset = 0;
    _outgoing = null;
    _transition.forward(from: 0);
  }

  void _finishSwipe(DragEndDetails details) {
    if (widget.onShiftDays != null) {
      // Keep the fractional column offset where the gesture ended.
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    if (_horizontalDistance.abs() >= 48 || velocity.abs() >= 400) {
      final direction = velocity.abs() >= 400 ? velocity : _horizontalDistance;
      (direction < 0 ? widget.onNext : widget.onPrevious)?.call();
    }
    _horizontalDistance = 0;
    _resetDrag();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dx.abs() <= event.scrollDelta.dy.abs()) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _scrollIdle?.cancel();
      if (widget.onShiftDays != null) {
        _scrollDays(-event.scrollDelta.dx);
        return;
      }
      _scrollIdle = Timer(const Duration(milliseconds: 180), () {
        _horizontalDistance = 0;
        _scrollNavigated = false;
      });
      if (_scrollNavigated) return;
      _horizontalDistance += event.scrollDelta.dx;
      if (_horizontalDistance.abs() >= 48) {
        _scrollNavigated = true;
        (_horizontalDistance > 0 ? widget.onNext : widget.onPrevious)?.call();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _transition =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 280),
          value: 1,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _outgoing = null);
          }
        });
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
    if (!date_utils.isSameDay(old.days.first, widget.days.first) ||
        old.days.length != widget.days.length) {
      if (_shiftInProgress) {
        _shiftInProgress = false;
      } else {
        _continuousOffset = 0;
        _outgoingScroll?.dispose();
        _outgoingScroll = ScrollController(
          initialScrollOffset: _scrollController.hasClients
              ? _scrollController.offset
              : 0,
        );
        _outgoing = old;
        _direction = widget.days.first.isBefore(old.days.first) ? -1 : 1;
        _transitionDrag = _dragOffset != 0
            ? _dragOffset
            : (_transition.isAnimating ? _transitionDrag : 0);
        _dragOffset = 0;
        if (MediaQuery.disableAnimationsOf(context)) {
          _outgoing = null;
          _transition.value = 1;
        } else {
          _transition.forward(from: 0);
        }
      }
    }
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
    _scrollIdle?.cancel();
    _transition.dispose();
    _outgoingScroll?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _draggableAllDay(CalendarEvent e, TimeGridView view) {
    final chip = _AllDayChip(
      theme: view.theme,
      event: e,
      onTap: () => view.onEventPress(e),
    );
    if (view.onEventMove == null || !isMovableEvent(e)) return chip;
    return MouseRegion(
      onEnter: (_) => view.onEventHover?.call(e),
      onExit: (_) => view.onEventHover?.call(null),
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
  Widget build(BuildContext context) {
    final navigable =
        widget.onShiftDays != null ||
        widget.onPrevious != null ||
        widget.onNext != null;
    return Listener(
      onPointerSignal: navigable ? _onPointerSignal : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Horizontal drags on empty space pan dates; event drags keep their own recognizer.
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
        onHorizontalDragStart: navigable
            ? (_) {
                _horizontalDistance = 0;
                _transitionDrag = 0;
              }
            : null,
        onHorizontalDragUpdate: navigable
            ? (details) => setState(() {
                if (widget.onShiftDays != null) {
                  _scrollDays(details.delta.dx);
                  return;
                }
                _horizontalDistance += details.delta.dx;
                if (!MediaQuery.disableAnimationsOf(context)) {
                  _dragOffset = _horizontalDistance;
                }
              })
            : null,
        onHorizontalDragEnd: navigable ? _finishSwipe : null,
        onHorizontalDragCancel: navigable
            ? () {
                _horizontalDistance = 0;
                if (widget.onShiftDays == null) _resetDrag();
              }
            : null,
        child: LayoutBuilder(
          builder: (context, constraints) => ClipRect(
            child: AnimatedBuilder(
              animation: _transition,
              builder: (context, _) {
                final width = constraints.maxWidth;
                _columnWidth = (width - _labelWidth) / widget.days.length;
                final progress = Curves.easeOutCubic.transform(
                  _transition.value,
                );
                final incoming = _outgoing != null
                    ? (_direction * width + _transitionDrag) * (1 - progress)
                    : _transitionDrag * (1 - progress);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_outgoing != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: Transform.translate(
                              offset: Offset(
                                _transitionDrag * (1 - progress) -
                                    _direction * width * progress,
                                0,
                              ),
                              child: _buildGrid(
                                context,
                                width,
                                view: _outgoing!,
                                controller: _outgoingScroll!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Transform.translate(
                      key: const ValueKey('time-grid-current-page'),
                      offset: Offset(
                        widget.onShiftDays != null && _outgoing == null
                            ? 0
                            : incoming + _dragOffset,
                        0,
                      ),
                      child: _buildGrid(
                        context,
                        width,
                        view: widget,
                        controller: _scrollController,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateRow(
    double columnWidth, {
    required bool continuous,
    required List<Widget> children,
  }) {
    if (!continuous) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }
    final offset =
        _continuousOffset +
        (_outgoing == null
            ? _transitionDrag *
                  (1 - Curves.easeOutCubic.transform(_transition.value))
            : 0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        children.first,
        Expanded(
          child: ClipRect(
            child: OverflowBox(
              fit: OverflowBoxFit.deferToChild,
              alignment: Alignment.topLeft,
              minWidth: columnWidth * (children.length - 1),
              maxWidth: columnWidth * (children.length - 1),
              child: Transform.translate(
                offset: Offset(-2 * columnWidth + offset, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children.skip(1).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(
    BuildContext context,
    double width, {
    required TimeGridView view,
    required ScrollController controller,
  }) {
    final colWidth = (width - _labelWidth) / view.days.length;
    final continuous = view.onShiftDays != null;
    final days = continuous
        ? List.generate(
            view.days.length + 4,
            (i) => date_utils.addDays(view.days.first, i - 2),
          )
        : view.days;
    final allDayByDate = days
        .map(
          (d) =>
              (view.events[date_utils.toDateKey(d)] ?? const <CalendarEvent>[])
                  .where((e) => e.time == null)
                  .toList(),
        )
        .toList();
    final hasAllDay = allDayByDate.any((list) => list.isNotEmpty);

    return Column(
      children: [
        if (!view.embedded)
          _dateRow(
            colWidth,
            continuous: continuous,
            children: [
              const SizedBox(width: _labelWidth),
              for (final d in days)
                SizedBox(
                  width: colWidth,
                  child: Column(
                    children: [
                      Text(
                        date_utils.weekdays[d.weekday % 7],
                        style: TextStyle(
                          fontSize: 11,
                          color: view.theme.textMuted,
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
                              ? view.theme.accent
                              : null,
                        ),
                        child: Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 15,
                            color: date_utils.isSameDay(d, _now)
                                ? Colors.white
                                : view.theme.text,
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
                horizontal: BorderSide(color: view.theme.border),
              ),
            ),
            constraints: const BoxConstraints(minHeight: 34),
            child: _dateRow(
              colWidth,
              continuous: continuous,
              children: [
                Container(
                  width: _labelWidth,
                  alignment: Alignment.center,
                  color: view.theme.bgSecondary,
                  child: Text(
                    '하루종일',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      color: view.theme.textSecondary,
                    ),
                  ),
                ),
                for (var i = 0; i < days.length; i++)
                  DragTarget<CalendarEvent>(
                    onWillAcceptWithDetails: (details) =>
                        view.onEventMove != null &&
                        details.data.time == null &&
                        details.data.date != date_utils.toDateKey(days[i]),
                    onAcceptWithDetails: (details) =>
                        view.onEventMove!(details.data, days[i], null),
                    builder: (context, candidates, _) => Container(
                      width: colWidth,
                      color: candidates.isNotEmpty
                          ? view.theme.accent.withValues(alpha: 0.12)
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          for (final e in allDayByDate[i])
                            _draggableAllDay(e, view),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            controller: controller,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              child: _dateRow(
                colWidth,
                continuous: continuous,
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
                                          color: view.theme.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                  for (final d in days)
                    _DayColumn(
                      key: ValueKey(date_utils.toDateKey(d)),
                      theme: view.theme,
                      day: d,
                      width: colWidth,
                      now: _now,
                      events: view.events,
                      onSlotPress: view.onSlotPress,
                      onEventPress: view.onEventPress,
                      onEventMove: view.onEventMove,
                      onEventResize: view.onEventResize,
                      onRangeCreate: view.onRangeCreate,
                      onEventHover: view.onEventHover,
                      selectedHour:
                          view.selectedDate != null &&
                              date_utils.isSameDay(d, view.selectedDate!)
                          ? view.selectedHour
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
  final void Function(CalendarEvent event, String time, int duration)?
  onEventResize;
  final void Function(DateTime date, String time, int duration)? onRangeCreate;
  final ValueChanged<CalendarEvent?>? onEventHover;
  final int? selectedHour;

  const _DayColumn({
    super.key,
    required this.theme,
    required this.day,
    required this.width,
    required this.now,
    required this.events,
    required this.onSlotPress,
    required this.onEventPress,
    this.onEventMove,
    this.onEventResize,
    this.onRangeCreate,
    this.onEventHover,
    this.selectedHour,
  });

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  final _columnKey = GlobalKey();
  int? _createFrom, _createTo; // minutes, while dragging on empty space
  int? _dropMinute; // snapped start of an event being dragged over this day
  int _dropDuration = 60;

  /// Notion-style lanes: overlapping events sit side by side.
  Map<String, (int lane, int lanes)> _layout(List<CalendarEvent> events) {
    final sorted = [...events]
      ..sort(
        (a, b) => date_utils
            .minutesFromTime(a.time!)
            .compareTo(date_utils.minutesFromTime(b.time!)),
      );
    final result = <String, (int, int)>{};
    var cluster = <CalendarEvent>[];
    var clusterEnd = 0;
    void flush() {
      if (cluster.isEmpty) return;
      final laneEnds = <int>[];
      final lanes = <String, int>{};
      for (final e in cluster) {
        final start = date_utils.minutesFromTime(e.time!);
        var lane = laneEnds.indexWhere((end) => end <= start);
        if (lane == -1) {
          lane = laneEnds.length;
          laneEnds.add(0);
        }
        laneEnds[lane] = start + (e.duration < 30 ? 30 : e.duration);
        lanes[e.id] = lane;
      }
      for (final e in cluster) {
        result[e.id] = (lanes[e.id]!, laneEnds.length);
      }
      cluster = [];
    }

    for (final e in sorted) {
      final start = date_utils.minutesFromTime(e.time!);
      if (cluster.isNotEmpty && start >= clusterEnd) flush();
      cluster.add(e);
      final end = start + (e.duration < 30 ? 30 : e.duration);
      if (cluster.length == 1 || end > clusterEnd) clusterEnd = end;
    }
    flush();
    return result;
  }

  int _minuteAt(double y) =>
      (((y / _hourHeight * 60) / 15).round() * 15).clamp(0, 24 * 60);

  void _finishCreate() {
    final from = _createFrom, to = _createTo;
    setState(() => _createFrom = _createTo = null);
    if (from == null || to == null || widget.onRangeCreate == null) return;
    final start = from < to ? from : to;
    final end = from < to ? to : from;
    if (end - start < 15) return;
    widget.onRangeCreate!(
      widget.day,
      date_utils.timeFromMinutes(start.clamp(0, 24 * 60 - 15)),
      end - start,
    );
  }

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
    final lanes = _layout(timedEvents);

    return DragTarget<CalendarEvent>(
      onWillAcceptWithDetails: (details) => widget.onEventMove != null,
      onMove: (details) {
        if (details.data.time == null) return;
        final minute = date_utils.minutesFromTime(_timeAt(details.offset));
        if (minute != _dropMinute) {
          setState(() {
            _dropMinute = minute;
            _dropDuration = details.data.duration;
          });
        }
      },
      onLeave: (_) => setState(() => _dropMinute = null),
      onAcceptWithDetails: (details) {
        setState(() => _dropMinute = null);
        if (details.data.time == null) return;
        widget.onEventMove!(details.data, day, _timeAt(details.offset));
      },
      builder: (context, candidates, _) => SizedBox(
        key: _columnKey,
        width: widget.width,
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: widget.onRangeCreate == null
                  ? null
                  : (d) => setState(() {
                      _createFrom = _minuteAt(d.localPosition.dy);
                      _createTo = _createFrom;
                    }),
              onVerticalDragUpdate: widget.onRangeCreate == null
                  ? null
                  : (d) => setState(
                      () => _createTo = _minuteAt(d.localPosition.dy),
                    ),
              onVerticalDragEnd: widget.onRangeCreate == null
                  ? null
                  : (_) => _finishCreate(),
              onVerticalDragCancel: () =>
                  setState(() => _createFrom = _createTo = null),
              child: Column(
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
            ),
            if (_createFrom != null && _createTo != null)
              Positioned(
                top:
                    (_createFrom! < _createTo! ? _createFrom! : _createTo!) /
                    60 *
                    _hourHeight,
                left: 2,
                right: 12,
                height: ((_createTo! - _createFrom!).abs() / 60 * _hourHeight)
                    .clamp(4, double.infinity)
                    .toDouble(),
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.25),
                      border: Border.all(color: theme.accent),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      '${date_utils.formatTimeLabel(date_utils.timeFromMinutes((_createFrom! < _createTo! ? _createFrom! : _createTo!).clamp(0, 1439)))} · ${date_utils.formatDurationLabel((_createTo! - _createFrom!).abs())}',
                      style: TextStyle(fontSize: 11, color: theme.text),
                    ),
                  ),
                ),
              ),
            if (_dropMinute != null)
              Positioned(
                top: _dropMinute! / 60 * _hourHeight,
                left: 2,
                right: 12,
                height: (_dropDuration / 60 * _hourHeight)
                    .clamp(22, double.infinity)
                    .toDouble(),
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.18),
                      border: Border.all(color: theme.accent, width: 1.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      date_utils.formatTimeLabel(
                        date_utils.timeFromMinutes(_dropMinute!),
                      ),
                      style: TextStyle(fontSize: 11, color: theme.text),
                    ),
                  ),
                ),
              ),
            for (final e in timedEvents)
              _EventBlock(
                key: ValueKey(e.id),
                theme: theme,
                event: e,
                left:
                    2 +
                    (lanes[e.id]?.$1 ?? 0) *
                        (widget.width - 14) /
                        (lanes[e.id]?.$2 ?? 1),
                width: (widget.width - 14) / (lanes[e.id]?.$2 ?? 1),
                onTap: () => widget.onEventPress(e),
                movable: widget.onEventMove != null && isMovableEvent(e),
                onResize: widget.onEventResize == null
                    ? null
                    : (time, duration) =>
                          widget.onEventResize!(e, time, duration),
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
  final double left, width;
  final bool movable;
  final void Function(String time, int duration)? onResize;
  final ValueChanged<CalendarEvent?>? onHover;
  const _EventBlock({
    super.key,
    required this.theme,
    required this.event,
    required this.onTap,
    required this.left,
    required this.width,
    this.movable = false,
    this.onResize,
    this.onHover,
  });

  @override
  State<_EventBlock> createState() => _EventBlockState();
}

class _EventBlockState extends State<_EventBlock> {
  /// Pixels the top / bottom edge has been dragged while resizing.
  double _topPx = 0, _bottomPx = 0;

  bool get _resizing => _topPx != 0 || _bottomPx != 0;

  int _snap(double px) => (px / _hourHeight * 60 / 15).round() * 15;

  /// Start and duration in minutes after applying the in-flight resize.
  (int start, int duration) get _range {
    final start0 = date_utils.minutesFromTime(widget.event.time!);
    final end0 = start0 + widget.event.duration;
    final start = (start0 + _snap(_topPx)).clamp(0, 24 * 60 - 15);
    final end = (end0 + _snap(_bottomPx)).clamp(start + 15, 24 * 60);
    return (start, end - start);
  }

  Widget _body(double height, {double? width}) {
    final event = widget.event;
    final tone = eventCardTone(colorFromHex(event.color), widget.theme);
    final (start, duration) = _range;
    return Container(
      width: width,
      padding: EdgeInsets.symmetric(
        horizontal: 6,
        vertical: height < 30 ? 2 : 6,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(3),
        border: _resizing
            ? Border.all(color: widget.theme.accent, width: 1.5)
            : null,
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
          if (_resizing && height > 34)
            Text(
              '${date_utils.formatTimeLabel(date_utils.timeFromMinutes(start))} · ${date_utils.formatDurationLabel(duration)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: tone.detail),
            )
          else if (height > 38 &&
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

  Widget _handle({required bool top}) => Positioned(
    left: 0,
    right: 0,
    top: top ? 0 : null,
    bottom: top ? null : 0,
    height: 8,
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => setState(() {
          if (top) {
            _topPx += d.delta.dy;
          } else {
            _bottomPx += d.delta.dy;
          }
        }),
        onVerticalDragEnd: (_) {
          final (start, duration) = _range;
          final changed = _resizing;
          setState(() => _topPx = _bottomPx = 0);
          if (changed) {
            widget.onResize!(date_utils.timeFromMinutes(start), duration);
          }
        },
        onVerticalDragCancel: () => setState(() => _topPx = _bottomPx = 0),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final (start, duration) = _range;
    final top = (start / 60) * _hourHeight;
    final height = ((duration / 60) * _hourHeight)
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
                width: widget.width,
                height: height,
                child: _body(height, width: widget.width),
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
      left: widget.left,
      width: widget.width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(child: content),
          if (widget.movable && widget.onResize != null) ...[
            _handle(top: true),
            _handle(top: false),
          ],
        ],
      ),
    );
  }
}
