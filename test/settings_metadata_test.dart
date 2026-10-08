import 'package:calendar_app_flutter/screens/settings_screen.dart';
import 'package:calendar_app_flutter/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('Windows settings show the actual version and zetto metadata', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      PackageInfo.setMockInitialValues(
        appName: '일상 캘린더',
        packageName: 'calendar_app_flutter',
        version: '0.9.2',
        buildNumber: '7',
        buildSignature: '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(
              theme: lightTheme,
              accountLabel: 'guest',
              onLogout: () {},
              onEventReminders: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0.9.2'), findsOneWidget);
      expect(find.text('0.1.0 베타'), findsNothing);
      expect(find.text('개발자'), findsOneWidget);
      expect(find.text('제작사'), findsOneWidget);
      expect(find.text('zetto'), findsNWidgets(2));
      expect(find.text('일정 시작 알림'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
