import 'package:calendar_app_flutter/screens/event_sheet.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final height in [650.0, 568.0]) {
    testWidgets(
      'editor keeps fields and save above keyboard at height $height',
      (tester) async {
        tester.view.physicalSize = Size(360, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showGeneralDialog<void>(
                    context: context,
                    pageBuilder: (_, _, _) => Align(
                      alignment: Alignment.bottomCenter,
                      child: Material(
                        color: Colors.transparent,
                        child: EventSheet(
                          theme: lightTheme,
                          draft: null,
                          isEditing: false,
                          initialTime: null,
                          initialDate: DateTime(2026, 10, 7),
                          onSave: (_) async {},
                        ),
                      ),
                    ),
                  ),
                  child: const Text('추가'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('추가'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final save = find.ancestor(
          of: find.byIcon(CupertinoIcons.check_mark),
          matching: find.byType(CupertinoButton),
        );
        expect(find.text('저장'), findsNothing);
        expect(tester.getRect(save).bottom, lessThanOrEqualTo(height - 300));
        expect(tester.getRect(find.text('일정')).top, greaterThanOrEqualTo(0));
        final url = find.byWidgetPredicate(
          (widget) =>
              widget is CupertinoTextField && widget.placeholder == 'URL',
        );
        await tester.ensureVisible(url);
        await tester.enterText(url, 'https://example.com');
        await tester.pumpAndSettle();
        expect(tester.getRect(url).bottom, lessThanOrEqualTo(height - 300));
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
