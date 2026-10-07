import 'package:calendar_app_flutter/widgets/event_time_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'one picker applies date and both times together, including midnight',
    (tester) async {
      tester.view.physicalSize = const Size(360, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ({DateTime start, int duration})? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<({DateTime start, int duration})>(
                    context: context,
                    builder: (_) => EventTimePicker(
                      start: DateTime(2026, 10, 7, 9),
                      durationMinutes: 60,
                    ),
                  );
                },
                child: const Text('선택'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('선택'));
      await tester.pumpAndSettle();
      tester
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(DateTime(2026, 10, 8));
      await tester.pumpAndSettle();
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(DateTime(2026, 10, 8, 23));
      await tester.pumpAndSettle();
      final end = find.textContaining(RegExp(r'^종료 ')).first;
      await tester.ensureVisible(end);
      await tester.tap(end);
      await tester.pumpAndSettle();
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(DateTime(2026, 10, 9, 1, 30));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();
      expect(result?.start, DateTime(2026, 10, 8, 23));
      expect(result?.duration, 150);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('선택'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );
}
