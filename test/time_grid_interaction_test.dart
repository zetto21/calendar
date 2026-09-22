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
  DateTime? date,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  void Function(DateTime, String, int)? onRangeCreate,
  void Function(CalendarEvent, String, int)? onEventResize,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 600,
      height: 1300,
      child: TimeGridView(
        onPrevious: onPrevious,
        onNext: onNext,
        theme: lightTheme,
        days: [date ?? DateTime(2026, 9, 22)],
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
  testWidgets(
    'horizontal scrolling follows pixels and advances one day at a time',
    (tester) async {
      var first = DateTime(2026, 9, 20);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => TimeGridView(
                theme: lightTheme,
                days: List.generate(7, (i) => first.add(Duration(days: i))),
                events: const {},
                onSlotPress: (_, _) {},
                onEventPress: (_) {},
                onShiftDays: (days) =>
                    update(() => first = first.add(Duration(days: days))),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final x = tester.getCenter(find.text('22')).dx;
      final position = tester.getCenter(find.byType(TimeGridView));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(25, 0),
        ),
      );
      await tester.pump();
      expect(tester.getCenter(find.text('22')).dx, closeTo(x - 25, 0.1));
      expect(first, DateTime(2026, 9, 20));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(100, 0),
        ),
      );
      await tester.pump();
      expect(first, DateTime(2026, 9, 21));
      expect(tester.getCenter(find.text('22')).dx, closeTo(x - 125, 0.1));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getCenter(find.text('22')).dx, closeTo(x - 125, 0.1));
      expect(first, DateTime(2026, 9, 21));
      // Releasing a mouse drag also preserves a partially visible day.
      final drag = await tester.startGesture(
        position,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(-35, 0));
      await tester.pump();
      await drag.moveBy(const Offset(-25, 0));
      await tester.pump();
      final releaseX = tester.getCenter(find.text('22')).dx;
      await drag.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getCenter(find.text('22')).dx, closeTo(releaseX, 0.1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date changes slide in the navigation direction and retain scroll',
    (tester) async {
      await tester.pumpWidget(
        _grid(events: const {}, date: DateTime(2026, 9, 22)),
      );
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offset = scroll.position.pixels;
      final page = find
          .descendant(
            of: find.byKey(const ValueKey('time-grid-current-page')),
            matching: find.byType(Column),
          )
          .first;
      final origin = tester.getTopLeft(page).dx;
      await tester.pumpWidget(
        _grid(events: const {}, date: DateTime(2026, 9, 23)),
      );
      expect(tester.getTopLeft(page).dx, greaterThan(origin));
      expect(find.text('22'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 140));
      final halfway = tester.getTopLeft(page).dx;
      expect(halfway, greaterThan(origin));
      expect(halfway, lessThan(600));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(page).dx, origin);
      expect(find.text('22'), findsNothing);
      expect(scroll.position.pixels, offset);
      await tester.pumpWidget(
        _grid(events: const {}, date: DateTime(2026, 9, 21)),
      );
      expect(tester.getTopLeft(page).dx, lessThan(origin));
      // A second navigation while moving must settle on the latest date.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(
        _grid(events: const {}, date: DateTime(2026, 10, 1)),
      );
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(tester.getTopLeft(page).dx, origin);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('horizontal swipes navigate without changing the hour scroll', (
    tester,
  ) async {
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(
      _grid(
        events: const {},
        onPrevious: () => previous++,
        onNext: () => next++,
      ),
    );
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final offset = scroll.position.pixels;
    await tester.drag(find.byType(TimeGridView), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(next, 1);
    expect(previous, 0);
    expect(scroll.position.pixels, offset);
    await tester.drag(find.byType(TimeGridView), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(previous, 1);
  });

  testWidgets('horizontal wheel momentum navigates once per gesture', (
    tester,
  ) async {
    var next = 0;
    await tester.pumpWidget(_grid(events: const {}, onNext: () => next++));
    final position = tester.getCenter(find.byType(TimeGridView));
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(30, 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(next, 1);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: position, scrollDelta: const Offset(60, 0)),
    );
    expect(next, 2);
    await tester.pump(const Duration(milliseconds: 200));
  });

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
