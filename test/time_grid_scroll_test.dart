import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
