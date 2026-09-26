import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/event_sheet.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';

void main() {
  testWidgets(
    'embedded event editor fits sidebar and closes without popping page',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var closed = 0;
      CalendarEvent? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 230,
              height: 420,
              child: EventSheet(
                embedded: true,
                onClose: () => closed++,
                theme: darkTheme,
                draft: null,
                isEditing: false,
                initialDate: DateTime(2026, 9, 23),
                initialTime: '10:00',
                onSave: (event) => saved = event,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('일정 추가'), findsOneWidget);
      final saveY = tester.getCenter(find.text('저장  ⌘↵')).dy;
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('저장  ⌘↵')).dy, saveY);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(EditableText).first, '패널에서 추가');
      await tester.ensureVisible(find.text('저장  ⌘↵'));
      await tester.tap(find.text('저장  ⌘↵'));
      expect(saved?.title, '패널에서 추가');
      await tester.tap(find.text('취소'));
      expect(closed, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 2);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('macOS event sheet saves with the shortcut and picks a color', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    CalendarEvent? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 580,
              child: EventSheet(
                theme: lightTheme,
                draft: null,
                isEditing: false,
                initialDate: DateTime(2026, 9, 22),
                initialTime: '10:00',
                onSave: (event) async => saved = event,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('제목 없음'), findsOneWidget);
    expect(find.text('저장  ⌘↵'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, '디자인 리뷰');
    await tester.tap(find.byTooltip('코랄'));
    await tester.pump();
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump();

    expect(saved?.title, '디자인 리뷰');
    expect(saved?.time, '10:00');
    expect(saved?.color, '#F0654F');
    debugDefaultTargetPlatformOverride = null;
  });
}
