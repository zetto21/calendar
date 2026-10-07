import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dayCount in [1, 3, 7]) {
    testWidgets(
      '$dayCount days: staggered overlap keeps exact times and each card accessible',
      (tester) async {
        final events = List.generate(
          4,
          (i) => CalendarEvent(
            id: 'overlap-$i',
            date: '2026-09-28',
            title: '서로 겹치는 일정 $i 긴 제목도 마지막 글자까지 표시합니다',
            time: '09:00',
            duration: [15, 30, 60, 360][i],
            color: '#3B82F6',
          ),
        );
        CalendarEvent? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TimeGridView(
                theme: lightTheme,
                days: List.generate(dayCount, (i) => DateTime(2026, 9, 28 + i)),
                events: {'2026-09-28': events},
                onSlotPress: (_, _) {},
                onEventPress: (e) => selected = e,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
        scroll.position.jumpTo(9 * 56);
        await tester.pump();
        final first = tester.getRect(find.byKey(ValueKey(events.first.id)));
        final rects = <Rect>[];
        for (final event in events) {
          final rect = tester.getRect(find.byKey(ValueKey(event.id)));
          expect(rect.top, first.top);
          expect(rect.height, closeTo(event.duration / 60 * 56, 0.01));
          rects.add(rect);
          final tooltip = tester.widget<Tooltip>(
            find.descendant(
              of: find.byKey(ValueKey(event.id)),
              matching: find.byType(Tooltip),
            ),
          );
          expect(tooltip.message, contains(event.title));
        }
        rects.sort((a, b) => a.left.compareTo(b.left));
        for (var i = 1; i < rects.length; i++) {
          expect(rects[i].left, greaterThan(rects[i - 1].left));
          expect(rects[i].overlaps(rects[i - 1]), isTrue);
        }
        expect(find.byType(PopupMenuButton<CalendarEvent>), findsNothing);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        for (final event in events.reversed) {
          await mouse.moveTo(Offset.zero);
          await tester.pump();
          final rect = tester.getRect(find.byKey(ValueKey(event.id)));
          final exposed = rect.topLeft + const Offset(3, 5);
          await mouse.moveTo(exposed);
          await tester.pump();
          await tester.tapAt(exposed);
          expect(selected?.id, event.id);
        }
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
