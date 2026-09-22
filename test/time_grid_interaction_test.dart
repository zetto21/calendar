import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';

CalendarEvent _event(String id, String time, int duration) => CalendarEvent(
  id: id,
  date: '2026-09-22',
  title: id,
  time: time,
  duration: duration,
  color: '#3B82F6',
);

Widget _grid({
  required EventMap events,
  void Function(DateTime, String, int)? onRangeCreate,
  void Function(CalendarEvent, String, int)? onEventResize,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 600,
      height: 1300,
      child: TimeGridView(
        theme: lightTheme,
        days: [DateTime(2026, 9, 22)],
        events: events,
        onSlotPress: (_, _) {},
        onEventPress: (_) {},
        onEventMove: (_, _, _) {},
        onEventResize: onEventResize,
        onRangeCreate: onRangeCreate,
      ),
    ),
  ),
);

void main() {
  testWidgets('overlapping events share the column side by side', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        events: {
          '2026-09-22': [_event('A', '10:00', 60), _event('B', '10:30', 60)],
        },
      ),
    );
    final a = tester.getRect(find.text('A'));
    final b = tester.getRect(find.text('B'));
    expect(a.left, lessThan(b.left));
    expect(b.left - a.left, greaterThan(100));
  });

  testWidgets('dragging empty space creates a snapped range', (tester) async {
    DateTime? date;
    String? time;
    int? duration;
    await tester.pumpWidget(
      _grid(
        events: const {},
        onRangeCreate: (d, t, m) {
          date = d;
          time = t;
          duration = m;
        },
      ),
    );
    final origin = tester.getTopLeft(find.byType(TimeGridView));
    // Hour height is 56px and the grid starts 8px + header below the top.
    final start =
        tester.getCenter(find.byType(TimeGridView)) + const Offset(0, -100);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 28));
    await gesture.up();
    await tester.pump();
    expect(origin, isNotNull);
    expect(date, DateTime(2026, 9, 22));
    expect(time, isNotNull);
    expect(duration! % 15, 0);
    expect(duration, greaterThanOrEqualTo(30));
  });

  testWidgets('dragging the bottom edge resizes the event', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? time;
    int? duration;
    await tester.pumpWidget(
      _grid(
        events: {
          '2026-09-22': [_event('A', '10:00', 60)],
        },
        onEventResize: (e, t, m) {
          time = t;
          duration = m;
        },
      ),
    );
    final handles = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeUpDown,
    );
    final bottomHandle = handles.last;
    final gesture = await tester.startGesture(
      tester.getCenter(bottomHandle),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 0));
    await gesture.up();
    await tester.pump();
    expect(time, '10:00');
    expect(duration, greaterThan(60));
    expect(duration! % 15, 0);
  });
}
