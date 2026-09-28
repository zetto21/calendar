import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/time_grid_view.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:calendar_app_flutter/widgets/macos_calendar_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
