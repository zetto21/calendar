import 'package:calendar_app_flutter/widgets/login_failure_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'long errors fit a small screen with enlarged text and can be dismissed',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const LoginFailureDialog(
                    message: '간편 로그인에 실패했습니다. 인터넷 연결을 확인한 후 다시 시도해 주세요. 잠시 후에도 문제가 계속되면 다른 로그인 방법을 이용해 주세요.',
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('확인'));
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginFailureDialog), findsNothing);
    },
  );
}
