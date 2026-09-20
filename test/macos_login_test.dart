import 'package:calendar_app_flutter/screens/login_screen.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('macOS login adapts to window size and validates credentials', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var guests = 0;
    var signups = 0;
    for (final theme in [lightTheme, darkTheme]) {
      for (final size in [
        const Size(1200, 800),
        const Size(520, 720),
        const Size(600, 500),
        const Size(360, 640),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildMaterialTheme(theme),
            home: LoginScreen(
              theme: theme,
              onAuthenticated: (_) {},
              onSignup: () => signups++,
              onContinueAsGuest: () => guests++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('나의 하루를\n차곡차곡.'),
          size.width >= 900 ? findsOneWidget : findsNothing,
        );
      }
    }
    await tester.ensureVisible(find.text('로그인'));
    await tester.tap(find.text('로그인'));
    await tester.pump();
    expect(find.text('올바른 이메일 주소를 입력해 주세요.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'hello@example.com');
    await tester.ensureVisible(find.text('로그인'));
    await tester.tap(find.text('로그인'));
    await tester.pump();
    expect(find.text('비밀번호를 입력해 주세요.'), findsOneWidget);
    await tester.ensureVisible(find.text('처음이신가요? 회원가입'));
    await tester.tap(find.text('처음이신가요? 회원가입'));
    expect(signups, 1);
    expect(find.text('로그인 없이 둘러보기 →'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
