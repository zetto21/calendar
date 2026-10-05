import 'package:calendar_app_flutter/screens/consent_screen.dart';
import 'package:calendar_app_flutter/widgets/consent_gate.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ConsentGate(child: Scaffold(body: Text('Login'))),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'first install requires consent; optional consent is not required',
    (tester) async {
      await mount(tester);
      expect(find.text('Login'), findsNothing);
      final continueButton = find.byKey(const ValueKey('consentContinue'));
      expect(tester.widget<CupertinoButton>(continueButton).onPressed, isNull);
      for (final label in [
        '[필수] 만 14세 이상입니다',
        '[필수] 이용약관 동의',
        '[필수] 개인정보처리방침 동의',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(
        tester.widget<CupertinoButton>(continueButton).onPressed,
        isNotNull,
      );
      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
      expect(find.text('Login'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(
        DateTime.tryParse(prefs.getString(ConsentScreen.storageKey)!),
        isNotNull,
      );
      expect(prefs.getBool(ConsentScreen.marketingStorageKey), isFalse);
      await tester.pumpWidget(const SizedBox());
      await mount(tester);
      expect(find.byType(ConsentScreen), findsNothing);
      expect(find.text('Login'), findsOneWidget);
    },
  );

  testWidgets('invalid stored consent does not bypass the first-run screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({ConsentScreen.storageKey: ''});
    await mount(tester);
    expect(find.byType(ConsentScreen), findsOneWidget);
    expect(find.text('Login'), findsNothing);
  });
}
