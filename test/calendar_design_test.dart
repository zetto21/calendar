import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_app_flutter/screens/month_agenda.dart';
import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:calendar_app_flutter/widgets/top_bar.dart';

void main() {
  testWidgets('anniversaries appear in agenda and all-day timeline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var edits = 0;
    Widget calendar(Map<String, List<String>> names) => MaterialApp(
      theme: buildMaterialTheme(lightTheme),
      home: Scaffold(
        body: MonthAgenda(
          theme: lightTheme,
          viewDate: DateTime(2026, 10),
          events: const {},
          selectedKey: '2026-10-01',
          anniversaryNames: names,
          onSelectDate: (_) {},
          onEventPress: (_) => edits++,
          onSlotPress: (_, _) {},
        ),
      ),
    );
    await tester.pumpWidget(
      calendar({
        '2026-10-01': ['국군의 날'],
      }),
    );
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    expect(find.text('국군의 날'), findsOneWidget);
    expect(find.text('일정이 없습니다'), findsNothing);
    await tester.tap(find.text('국군의 날'));
    expect(edits, 0);
    await tester.tap(find.byTooltip('시간표 보기'));
    await tester.pumpAndSettle();
    expect(find.text('국군의 날'), findsOneWidget);
    await tester.tap(find.text('국군의 날'));
    expect(edits, 0);
    await tester.pumpWidget(calendar({}));
    await tester.pumpAndSettle();
    expect(find.text('국군의 날'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('left swipe goes next and right swipe goes previous', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialTheme(lightTheme),
        home: Scaffold(
          body: MonthAgenda(
            theme: lightTheme,
            viewDate: DateTime(2026, 9),
            events: const {},
            selectedKey: '2026-09-23',
            onSelectDate: (_) {},
            onEventPress: (_) {},
            onSlotPress: (_, _) {},
            onPreviousMonth: () => previous++,
            onNextMonth: () => next++,
          ),
        ),
      ),
    );
    await tester.drag(find.text('23'), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(previous, 0);
    expect(next, 1);
    await tester.drag(find.text('23'), const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(previous, 1);
    expect(next, 1);
    await tester.tap(find.text('23'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('23'), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(previous, 1);
    expect(next, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('solar terms appear only in calendar', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget calendar(Map<String, String> terms) => MaterialApp(
      theme: buildMaterialTheme(lightTheme),
      home: Scaffold(
        body: MonthAgenda(
          theme: lightTheme,
          viewDate: DateTime(2026, 9),
          events: const {},
          selectedKey: '2026-09-23',
          showHolidays: false,
          solarTermNames: terms,
          onSelectDate: (_) {},
          onEventPress: (_) {},
          onSlotPress: (_, _) {},
        ),
      ),
    );
    await tester.pumpWidget(calendar({'2026-09-23': '추분'}));
    expect(find.text('추분'), findsOneWidget);
    await tester.tap(find.text('23'));
    await tester.pumpAndSettle();
    expect(find.text('추분'), findsNothing);
    expect(find.text('종일'), findsNothing);
    expect(find.text('일정이 없습니다'), findsOneWidget);
    await tester.tap(find.byTooltip('시간표 보기'));
    await tester.pumpAndSettle();
    expect(find.text('추분'), findsNothing);
    await tester.tap(find.byTooltip('목록 보기'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(calendar({}));
    await tester.pumpAndSettle();
    expect(find.text('추분'), findsNothing);
    expect(find.text('일정이 없습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date picker opens and selects today', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopBar(
            theme: lightTheme,
            title: '2026. 9.',
            selectedDate: DateTime(2026, 9, 10),
            onDateSelected: (_) {},
            onPrev: () {},
            onNext: () {},
            onToday: () {},
            onMenu: () {},
            onSearch: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('2026. 9.'));
    await tester.pump();
    expect(find.text('오늘'), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final theme in [lightTheme, darkTheme]) {
    testWidgets(
      'agenda opens, switches and collapses on a small screen (${theme.isDark})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildMaterialTheme(theme),
            home: Scaffold(
              body: MonthAgenda(
                theme: theme,
                viewDate: DateTime(2026, 9),
                events: const {},
                selectedKey: '2026-09-10',
                onSelectDate: (_) {},
                onEventPress: (_) {},
                onSlotPress: (_, _) {},
              ),
            ),
          ),
        );
        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();
        expect(find.text('일정이 없습니다'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('시간표 보기'));
        await tester.pumpAndSettle();
        expect(find.byType(TimeGridView), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.bySemanticsLabel('일정 목록 접기'));
        await tester.pumpAndSettle();
        expect(find.byType(TimeGridView), findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
