import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/screens/event_sheet.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';

void main() {
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
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump();

    expect(saved?.title, '디자인 리뷰');
    expect(saved?.time, '10:00');
    expect(saved?.color, '#F0654F');
    debugDefaultTargetPlatformOverride = null;
  });
}
