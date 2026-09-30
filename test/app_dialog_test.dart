import 'dart:async';

import 'package:calendar_app_flutter/widgets/app_dialog.dart';
import 'package:calendar_app_flutter/widgets/personal_calendars.dart';
import 'package:calendar_app_flutter/screens/event_sheet.dart';
import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'confirmation fits a small viewport and returns its result ($dark)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 550));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildMaterialTheme(dark ? darkTheme : lightTheme),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<bool>(
                      context: context,
                      builder: (context) => AppDialog(
                        title: const Text('캘린더 연동 해제'),
                        content: Text(
                          List.filled(20, '이 캘린더의 연동을 해제할까요?').join('\n'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('취소'),
                          ),
                          AppDialogAction(
                            isDestructiveAction: true,
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('해제'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('닫기'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('해제'));
        await tester.pumpAndSettle();
        expect(result, isTrue);
        expect(find.byType(AppDialog), findsNothing);
      },
    );
  }

  testWidgets(
    'calendar editor preserves save validation and busy close protection',
    (tester) async {
      final pending = Completer<void>();
      PersonalCalendar? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaterialTheme(lightTheme),
          home: Scaffold(
            body: PersonalCalendars(
              calendars: const [],
              personalVisible: true,
              onDelete: (_) async {},
              onPersonalVisibilityChanged: (_) {},
              onSave: (calendar) {
                saved = calendar;
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('캘린더 추가'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '프로젝트');
      await tester.pump();
      await tester.tap(find.text('저장'));
      await tester.pump();
      expect(saved?.title, '프로젝트');
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '닫기',
              ),
            )
            .onPressed,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
    },
  );

  for (final embedded in [true, false]) {
    testWidgets(
      'desktop event editor keeps its fields and save action ($embedded)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.binding.setSurfaceSize(const Size(900, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        CalendarEvent? saved;
        const event = CalendarEvent(
          id: 'edit',
          date: '2026-09-30',
          title: '회의',
          location: '회의실',
          time: '10:00',
          duration: 60,
          color: '#3B82F6',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildMaterialTheme(darkTheme),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: embedded ? 360 : 600,
                  child: EventSheet(
                    theme: darkTheme,
                    embedded: embedded,
                    draft: event,
                    isEditing: true,
                    initialDate: DateTime(2026, 9, 30),
                    initialTime: '10:00',
                    onSave: (value) => saved = value,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppDialogHeader), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('반복 안 함'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('매주'));
        await tester.pump();
        await tester.tap(find.text('저장'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('저장  ⌘↵'));
        await tester.pump();
        expect(saved?.title, '회의');
        expect(saved?.location, '회의실');
        expect(saved?.time, '10:00');
        expect(saved?.recurrence?.frequency, RepeatFrequency.weekly);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
