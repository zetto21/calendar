import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/month_agenda.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:calendar_app_flutter/widgets/macos_calendar_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('macOS calendar resizes and supports navigation and shortcuts', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var creates = 0;
    var previous = 0;
    var edits = 0;
    var selected = '2026-09-20';
    var view = ViewMode.month;
    for (final theme in [lightTheme, darkTheme]) {
      for (final size in [
        const Size(1440, 900),
        const Size(1024, 700),
        const Size(800, 600),
        const Size(390, 600),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildMaterialTheme(theme),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => MacosCalendarShell(
                  theme: theme,
                  title: '2026년 9월',
                  account: 'hello@example.com',
                  view: view,
                  onViewChanged: (value) => update(() => view = value),
                  onPrevious: () => previous++,
                  onNext: () {},
                  onToday: () {},
                  onCreate: () => creates++,
                  onSearch: () {},
                  onManage: () {},
                  selectedDate: DateTime(2026, 9, 20),
                  onDateSelected: (date) => update(
                    () => selected =
                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                  ),
                  child: MonthAgenda(
                    theme: theme,
                    viewDate: DateTime(2026, 9),
                    selectedKey: selected,
                    events: {
                      '2026-09-20': [
                        CalendarEvent(
                          id: 'sample',
                          date: '2026-09-20',
                          title: '프로젝트 리뷰',
                          time: '10:00',
                          duration: 60,
                          color: '#3B82F6',
                        ),
                      ],
                    },
                    onSelectDate: (value) => update(() => selected = value),
                    onEventPress: (_) => edits++,
                    onSlotPress: (_, _) => creates++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('macos-calendar-sidebar')),
          size.width >= 1000 ? findsOneWidget : findsNothing,
        );
        if (size.width == 1440) {
          expect(
            find.byKey(const ValueKey('macos-day-agenda')),
            findsOneWidget,
          );
          await tester.tap(find.text('프로젝트 리뷰').last);
          expect(edits, greaterThan(0));
          await tester.tap(find.byTooltip('주간 · ⌘2'));
          expect(view, ViewMode.week);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          expect(creates, greaterThan(0));
          await tester.tap(find.byTooltip('이전 · ⌘←'));
          expect(previous, greaterThan(0));
          await tester.pumpAndSettle();
          await tester.tap(find.text('21').first);
          await tester.pumpAndSettle();
          expect(selected, '2026-09-21');
          selected = '2026-09-20';
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
