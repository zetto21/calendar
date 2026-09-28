import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dayCount in [1, 7]) {
    testWidgets(
      '$dayCount days: overlapping events retain full readable titles',
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
        Rect? previous;
        for (final event in events) {
          final title = find.text(event.title);
          expect(title, findsOneWidget);
          final text = tester.widget<Text>(title);
          expect(text.maxLines, isNull);
          expect(text.overflow, isNull);
          final rect = tester.getRect(
            find.byKey(ValueKey('event-title:${event.id}')),
          );
          expect(rect.width, greaterThan((800 - 42) / dayCount * 0.8));
          if (previous != null) {
            expect(rect.top, greaterThanOrEqualTo(previous.bottom));
          }
          previous = rect;
        }
        await tester.tap(find.text(events.first.title));
        expect(selected?.id, events.first.id);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
