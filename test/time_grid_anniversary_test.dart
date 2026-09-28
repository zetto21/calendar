import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final count in [1, 7]) {
    testWidgets('$count days: anniversaries appear and respect visibility', (
      tester,
    ) async {
      Widget build(bool visible) => MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            theme: lightTheme,
            days: List.generate(count, (i) => DateTime(2026, 9, 28 + i)),
            events: const {},
            anniversaryNames: visible
                ? const {
                    '2026-09-28': ['기념일 A', '기념일 B'],
                  }
                : const {},
            onShiftDays: (_) {},
            onSlotPress: (_, _) {},
            onEventPress: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(find.text('기념일 A'), findsOneWidget);
      expect(find.text('기념일 B'), findsOneWidget);
      expect(find.text('하루종일'), findsOneWidget);
      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      expect(find.text('기념일 A'), findsNothing);
      expect(find.text('기념일 B'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
