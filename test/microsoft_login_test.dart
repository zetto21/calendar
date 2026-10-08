import 'dart:convert';

import 'package:calendar_app_flutter/screens/login_screen.dart';
import 'package:calendar_app_flutter/services/auth_service.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:calendar_app_flutter/widgets/brand_marks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('Microsoft mark paints four visible color squares', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: MicrosoftMark())),
    );
    final squares = find.descendant(
      of: find.byType(MicrosoftMark),
      matching: find.byType(ColoredBox),
    );
    expect(squares, findsNWidgets(4));
    for (final square in squares.evaluate()) {
      expect(tester.getSize(find.byWidget(square.widget)), const Size(10, 10));
    }
  });

  test('Microsoft is enabled only when advertised by the server', () async {
    for (final enabled in [false, true]) {
      final service = AuthService.forTesting(
        clientFactory: () => MockClient((request) async {
          expect(request.url.path, '/api/auth/oauth/providers');
          return http.Response(
            jsonEncode({
              'providers': ['google', if (enabled) 'microsoft'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final providers = await service.enabledSocialProviders();
      expect(providers.contains(SocialProvider.microsoft), enabled);
      expect(providers, contains(SocialProvider.google));
    }
  });

  test('Microsoft uses the existing OAuth code challenge flow', () {
    final challenge = 'A' * 43;
    final url = Uri.parse(
      AuthService.forTesting().socialLoginStartURL(
        SocialProvider.microsoft,
        codeChallenge: challenge,
      ),
    );
    expect(url.path, '/api/auth/oauth/microsoft/start');
    expect(url.queryParameters['client_challenge'], challenge);
    expect(
      () => AuthService.forTesting().socialLoginStartURL(
        SocialProvider.microsoft,
        codeChallenge: 'invalid',
      ),
      throwsA(isA<AuthException>()),
    );
  });

  testWidgets('Windows uses the Mac login form in the fixed window', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(520, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          theme: lightTheme,
          onAuthenticated: (_) {},
          onSignup: () {},
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('일상 캘린더에 오신 것을 환영해요'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(MicrosoftMark), findsOneWidget);
    expect(find.byTooltip('Microsoft 계정으로 로그인'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    debugDefaultTargetPlatformOverride = null;
  });
}
