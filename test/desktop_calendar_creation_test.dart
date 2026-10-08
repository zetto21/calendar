import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/month_agenda.dart';
import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Windows narrow month can create after selecting a date', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.binding.setSurfaceSize(const Size(720, 800));
      final created = <DateTime>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonthAgenda(
              theme: lightTheme,
              viewDate: DateTime(2026, 10),
              selectedKey: '2026-10-09',
              events: const {},
              onSelectDate: (_) {},
              onCreateDate: created.add,
              onEventPress: (_) {},
              onSlotPress: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('9'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle(kDoubleTapTimeout);
      await tester.tap(find.text('9'), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('9'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(created, [DateTime(2026, 10, 9)]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets('$platform month double-click creates on the clicked date', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.binding.setSurfaceSize(const Size(1100, 800));
        final selected = <String>[];
        final created = <DateTime>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MonthAgenda(
                theme: lightTheme,
                viewDate: DateTime(2026, 10),
                selectedKey: '2026-10-08',
                events: const {
                  '2026-10-09': [
                    CalendarEvent(
                      id: 'existing',
                      date: '2026-10-09',
                      title: 'Existing event',
                      duration: 1440,
                      color: '#3B82F6',
                    ),
                  ],
                },
                onSelectDate: selected.add,
                onCreateDate: created.add,
                onEventPress: (_) {},
                onSlotPress: (_, _) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final cell = find
            .ancestor(of: find.text('9'), matching: find.byType(InkWell))
            .first;
        final rect = tester.getRect(cell);
        final empty = Offset(rect.center.dx, rect.bottom - 12);
        await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle(kDoubleTapTimeout);
        expect(selected, ['2026-10-09']);
        expect(created, isEmpty);

        await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(created, [DateTime(2026, 10, 9)]);

        // Double-clicking an existing event must not create a duplicate.
        await tester.tap(
          find.text('Existing event'),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(
          find.text('Existing event'),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(created, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.binding.setSurfaceSize(null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    for (final reverse in [false, true]) {
      testWidgets(
        '$platform week mouse drag creates a range (reverse=$reverse)',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          try {
            final slots = <(DateTime, int)>[];
            final ranges = <(DateTime, String, int)>[];
            var shiftedDays = 0;
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: TimeGridView(
                    theme: lightTheme,
                    days: List.generate(7, (i) => DateTime(2026, 10, 4 + i)),
                    events: const {},
                    onShiftDays: (days) => shiftedDays += days,
                    onSlotPress: (day, hour) => slots.add((day, hour)),
                    onRangeCreate: (day, time, duration) =>
                        ranges.add((day, time, duration)),
                    onEventPress: (_) {},
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final scroll = tester.state<ScrollableState>(
              find.byType(Scrollable),
            );
            scroll.position.jumpTo(8 * 56);
            await tester.pump();
            final area = tester.getRect(find.byType(SingleChildScrollView));
            final start = Offset(
              area.left + 42 + (area.width - 42) / 14,
              area.top + 8 + (reverse ? 154 : 70),
            );
            await tester.tapAt(start, kind: PointerDeviceKind.mouse);
            await tester.pumpAndSettle();
            expect(slots, [(DateTime(2026, 10, 4), reverse ? 10 : 9)]);
            final before = scroll.position.pixels;
            final drag = await tester.startGesture(
              start,
              kind: PointerDeviceKind.mouse,
            );
            await drag.moveBy(Offset(0, reverse ? -28 : 28));
            await tester.pump();
            await drag.moveBy(Offset(0, reverse ? -56 : 56));
            await tester.pump();
            await drag.up();
            await tester.pumpAndSettle();
            expect(ranges, [(DateTime(2026, 10, 4), '09:15', 90)]);
            expect(slots, hasLength(1));
            expect(scroll.position.pixels, before);

            // Touch keeps scrolling without opening another editor.
            final touch = await tester.startGesture(
              start,
              kind: PointerDeviceKind.touch,
            );
            await touch.moveBy(const Offset(0, -60));
            await tester.pump();
            await touch.moveBy(const Offset(0, -60));
            await touch.up();
            await tester.pumpAndSettle();
            expect(scroll.position.pixels, greaterThan(before));
            expect(ranges, hasLength(1));
            expect(slots, hasLength(1));

            final trackpad = await tester.createGesture(
              kind: PointerDeviceKind.trackpad,
            );
            final beforeTrackpad = scroll.position.pixels;
            await trackpad.panZoomStart(start);
            await trackpad.panZoomUpdate(start, pan: const Offset(0, -40));
            await tester.pump();
            await trackpad.panZoomUpdate(start, pan: const Offset(0, -100));
            await trackpad.panZoomEnd();
            await tester.pumpAndSettle();
            expect(scroll.position.pixels, greaterThan(beforeTrackpad));

            // Horizontal mouse navigation still pans dates instead of creating.
            final horizontal = await tester.startGesture(
              start,
              kind: PointerDeviceKind.mouse,
            );
            await horizontal.moveBy(const Offset(70, 0));
            await tester.pump();
            await horizontal.moveBy(const Offset(140, 0));
            await horizontal.up();
            await tester.pumpAndSettle();
            expect(shiftedDays, isNonZero);
            expect(ranges, hasLength(1));
            expect(slots, hasLength(1));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }
}
