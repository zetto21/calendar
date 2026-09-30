import 'package:calendar_app_flutter/widgets/personal_calendars.dart';
import 'package:calendar_app_flutter/widgets/app_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const work = PersonalCalendar(id: 'work', title: '업무', color: '#3B82F6');

Future<void> hold(WidgetTester tester, String title) async {
  final mouse = await tester.startGesture(
    tester.getCenter(find.text(title)),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await mouse.up();
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester, {
  Future<void> Function(PersonalCalendar)? onDelete,
  ValueChanged<bool>? onVisibility,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: PersonalCalendars(
        calendars: const [PersonalCalendar.initial, work],
        onSave: (_) async {},
        onDelete: onDelete ?? (_) async {},
        personalVisible: true,
        onPersonalVisibilityChanged: onVisibility ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'a click does not edit; holding opens actions and edit opens the editor',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('업무'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      await hold(tester, '업무');
      expect(find.text('수정'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      expect(find.text('캘린더 편집'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '업무',
      );
    },
  );

  testWidgets(
    'delete requires confirmation and cancelling preserves the calendar',
    (tester) async {
      var deletions = 0;
      await mount(
        tester,
        onDelete: (calendar) async {
          expect(calendar.id, 'work');
          deletions++;
        },
      );
      await hold(tester, '업무');
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(deletions, 0);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(deletions, 0);
      await hold(tester, '업무');
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(deletions, 1);
    },
  );

  testWidgets(
    'default calendar keeps visibility control and cannot be deleted',
    (tester) async {
      bool? visible;
      await mount(tester, onVisibility: (value) => visible = value);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(visible, isFalse);
      await hold(tester, '내 캘린더');
      final deletion = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, '삭제 불가 · 기본 캘린더'),
      );
      expect(deletion.enabled, isFalse);
    },
  );
}
