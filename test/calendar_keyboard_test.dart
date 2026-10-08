import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:calendar_app_flutter/widgets/macos_calendar_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Windows desktop uses Ctrl shortcuts', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var created = 0;
    ViewMode? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MacosCalendarShell(
            theme: lightTheme,
            title: '캘린더',
            account: 'guest',
            view: ViewMode.month,
            onViewChanged: (value) => selected = value,
            onPrevious: () {},
            onNext: () {},
            onToday: () {},
            onCreate: () => created++,
            onSearch: () {},
            onManage: () {},
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(selected, ViewMode.week);
    expect(created, 1);
    expect(find.byTooltip('일정 추가 · Ctrl+N'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Arrow keys navigate with an editor open but preserve text editing',
    (tester) async {
      var moves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MacosCalendarShell(
              eventEditorOpen: true,
              theme: lightTheme,
              title: '주간',
              account: 'guest',
              view: ViewMode.week,
              onViewChanged: (_) {},
              onPrevious: () {},
              onNext: () {},
              onToday: () {},
              onCreate: () {},
              onSearch: () {},
              onManage: () {},
              onNavigate: (dx, dy) => moves += dx,
              child: Column(
                children: [
                  const TextField(),
                  Expanded(
                    child: TimeGridView(
                      theme: lightTheme,
                      days: [DateTime(2025)],
                      events: const {},
                      onSlotPress: (_, _) {},
                      onEventPress: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(moves, 1);
      await tester.tap(find.text('주간').first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(moves, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(moves, 1);
      await tester.enterText(find.byType(TextField), 'calendar');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(moves, 1);
      final input = tester.widget<EditableText>(find.byType(EditableText));
      expect(input.controller.selection.baseOffset, 7);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
