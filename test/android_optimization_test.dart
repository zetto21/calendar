import 'package:calendar_app_flutter/screens/search_screen.dart';
import 'package:calendar_app_flutter/screens/list_view.dart';
import 'package:calendar_app_flutter/storage/event_store.dart';
import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:calendar_app_flutter/widgets/liquid_glass.dart';
import 'package:calendar_app_flutter/widgets/top_bar.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class SearchStore extends EventStore {
  @override
  EventMap get events => {
    '2026-09-01': [
      const CalendarEvent(
        id: '1',
        date: '2026-09-01',
        title: 'Weekly Meeting',
        duration: 60,
        color: '#3B82F6',
        recurrence: EventRecurrence(frequency: RepeatFrequency.weekly),
      ),
      const CalendarEvent(
        id: '2',
        date: '2026-09-01',
        title: 'Other',
        duration: 60,
        color: '#3B82F6',
      ),
    ],
  };
}

void main() {
  testWidgets(
    'search still finds recurring occurrences outside the series start date',
    (tester) async {
      tz_data.initializeTimeZones();
      final store = SearchStore();
      await tester.pumpWidget(
        ChangeNotifierProvider<EventStore>.value(
          value: store,
          child: MaterialApp(
            home: SearchScreen(
              rangeFrom: '2026-09-08',
              rangeTo: '2026-09-08',
              deviceZone: tz.UTC,
              onEventPress: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('찾으려는 일정 제목을 입력해 주세요'), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' meeting ');
      await tester.pumpAndSettle();
      expect(find.text('Weekly Meeting'), findsWidgets);
      expect(
        tester
            .widget<EventListView>(find.byType(EventListView))
            .events['2026-09-08']!
            .single
            .id,
        '1::2026-09-08',
      );
      expect(find.text('Other'), findsNothing);
      await tester.enterText(find.byType(TextField), 'no match');
      await tester.pumpAndSettle();
      expect(find.text('검색 결과가 없습니다'), findsOneWidget);
      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pumpAndSettle();
      expect(find.text('찾으려는 일정 제목을 입력해 주세요'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('Android surfaces keep taps without a backdrop filter', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidGlass(
            child: TextButton(onPressed: () => taps++, child: const Text('선택')),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.text('선택'));
    expect(taps, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'Android toolbar has accessible targets and Material date selection',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TopBar(
              theme: lightTheme,
              title: '2026. 9.',
              selectedDate: DateTime(2026, 9, 10),
              onDateSelected: (value) => selected = value,
              onPrev: () {},
              onNext: () {},
              onToday: () {},
              onMenu: () {},
              onSearch: () {},
            ),
          ),
        ),
      );
      for (final tooltip in ['캘린더 메뉴', '일정 검색', '보기 방식: 월간']) {
        expect(
          tester.getSize(find.byTooltip(tooltip)).shortestSide,
          greaterThanOrEqualTo(48),
        );
      }
      await tester.tap(find.textContaining('2026. 9.'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('선택'));
      await tester.pumpAndSettle();
      expect(selected, DateTime(2026, 9, 10));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
