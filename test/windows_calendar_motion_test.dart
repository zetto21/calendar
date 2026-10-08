import 'package:calendar_app_flutter/screens/month_agenda.dart';
import 'package:calendar_app_flutter/screens/month_view.dart';
import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:calendar_app_flutter/widgets/calendar_view_transition.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('view changes retain the old frame without its focus or input', (
    tester,
  ) async {
    final oldFocus = FocusNode();
    var oldClicks = 0;
    Widget view(String key) => host(
      CalendarViewTransition(
        viewKey: key,
        child: key == 'month'
            ? Focus(
                focusNode: oldFocus,
                child: TextButton(
                  onPressed: () => oldClicks++,
                  child: const Text('month'),
                ),
              )
            : const Center(child: Text('week')),
      ),
    );
    await tester.pumpWidget(view('month'));
    oldFocus.requestFocus();
    await tester.pump();
    await tester.pumpWidget(view('week'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('month'), findsOneWidget);
    expect(find.text('week'), findsOneWidget);
    expect(oldFocus.hasFocus, false);
    await tester.tap(find.text('month'), warnIfMissed: false);
    expect(oldClicks, 0);
    // Reverse before completion: keep a rendered frame and finish on the latest view.
    await tester.pumpWidget(
      host(
        const CalendarViewTransition(
          viewKey: 'month',
          child: Center(child: Text('month')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('week'), findsNothing);
    expect(find.text('month'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    oldFocus.dispose();
  });

  testWidgets('reduced motion switches views without lingering old content', (
    tester,
  ) async {
    Widget view(String name) => host(
      CalendarViewTransition(viewKey: name, child: Text(name)),
      reduceMotion: true,
    );
    await tester.pumpWidget(view('month'));
    await tester.pumpWidget(view('week'));
    await tester.pumpAndSettle();
    expect(find.text('month'), findsNothing);
    expect(find.text('week'), findsOneWidget);
  });

  testWidgets('Windows month reversal keeps the calendar in place', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      Widget month(int number) => host(
        MonthAgenda(
          theme: lightTheme,
          viewDate: DateTime(2026, number),
          selectedKey: '2026-10-09',
          events: const {},
          onSelectDate: (_) {},
          onEventPress: (_) {},
          onSlotPress: (_, _) {},
        ),
      );
      await tester.pumpWidget(month(10));
      await tester.pumpAndSettle();
      final startX = tester.getTopLeft(find.byType(MonthView)).dx;
      await tester.pumpWidget(month(11));
      await tester.pump(const Duration(milliseconds: 70));
      for (final element in find.byType(MonthView).evaluate()) {
        expect(tester.getTopLeft(find.byWidget(element.widget)).dx, startX);
      }
      await tester.pumpWidget(month(10));
      await tester.pumpAndSettle();
      expect(find.byType(MonthView), findsOneWidget);
      expect(
        tester.widget<MonthView>(find.byType(MonthView)).viewDate.month,
        10,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Windows date navigation stays within a small offset and preserves scroll',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        Widget day(int number) => host(
          TimeGridView(
            theme: lightTheme,
            days: [DateTime(2026, 10, number)],
            events: const {},
            onSlotPress: (_, _) {},
            onEventPress: (_) {},
          ),
        );
        const page = ValueKey('time-grid-current-page');
        await tester.pumpWidget(day(9));
        await tester.pumpAndSettle();
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        position.jumpTo(420);
        await tester.pump();
        final startX = tester.getTopLeft(find.byKey(page)).dx;
        await tester.pumpWidget(day(10));
        expect(
          (tester.getTopLeft(find.byKey(page)).dx - startX).abs(),
          lessThanOrEqualTo(24),
        );
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpWidget(day(9));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(page)).dx, startX);
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position
              .pixels,
          420,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
