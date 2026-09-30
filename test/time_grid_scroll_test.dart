import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final part in ['top', 'body', 'bottom']) {
    testWidgets('trackpad scroll over event $part does not edit it', (
      tester,
    ) async {
      var moves = 0;
      var resizes = 0;
      const event = CalendarEvent(
        id: 'scroll-event',
        date: '2025-01-06',
        title: 'Event',
        time: '09:00',
        duration: 120,
        color: '#3B82F6',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeGridView(
              theme: lightTheme,
              days: [DateTime(2025, 1, 6)],
              events: const {
                '2025-01-06': [event],
              },
              onSlotPress: (_, _) {},
              onEventPress: (_) {},
              onEventMove: (_, _, _) => moves++,
              onEventResize: (_, _, _) => resizes++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(8 * 56);
      await tester.pump();
      final rect = tester.getRect(find.byKey(ValueKey(event.id)));
      final start = Offset(rect.center.dx, switch (part) {
        'top' => rect.top + 3,
        'bottom' => rect.bottom - 3,
        _ => rect.center.dy,
      });
      final before = scroll.position.pixels;
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(start);
      await gesture.panZoomUpdate(start, pan: const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.panZoomUpdate(start, pan: const Offset(0, -100));
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(before));
      expect(moves, 0);
      expect(resizes, 0);

      // Explicit mouse drags must still resize and move events.
      scroll.position.jumpTo(8 * 56);
      await tester.pump();
      final mouse = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(0, 25));
      await tester.pump();
      await mouse.moveBy(const Offset(0, 56));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(part == 'body' ? moves : resizes, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final dayCount in [1, 7]) {
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      testWidgets(
        '$dayCount days: $kind drag scrolls without creating an event',
        (tester) async {
          var creations = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TimeGridView(
                  theme: lightTheme,
                  days: List.generate(
                    dayCount,
                    (i) => DateTime(2025, 1, 6 + i),
                  ),
                  events: const {},
                  onSlotPress: (_, _) => creations++,
                  onRangeCreate: (_, _, _) => creations++,
                  onEventPress: (_) {},
                  onPrevious: () {},
                  onNext: () {},
                ),
              ),
            ),
          );
          await tester.pump();
          final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
          final before = scroll.position.pixels;
          final area = tester.getRect(find.byType(SingleChildScrollView));
          final start = Offset(area.left + 80, area.center.dy);
          final gesture = await tester.startGesture(start, kind: kind);
          await gesture.moveBy(const Offset(0, -100));
          await tester.pump(const Duration(milliseconds: 50));
          await gesture.moveBy(const Offset(0, -100));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(scroll.position.pixels, greaterThan(before));
          expect(creations, 0);

          // A tap still opens creation; holding and dragging selects a range.
          await tester.tapAt(start);
          await tester.pump();
          expect(creations, 1);
          final held = await tester.startGesture(start, kind: kind);
          await tester.pump(
            kLongPressTimeout + const Duration(milliseconds: 50),
          );
          await held.moveBy(const Offset(0, 70));
          await tester.pump();
          await held.up();
          await tester.pump();
          expect(creations, 2);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
