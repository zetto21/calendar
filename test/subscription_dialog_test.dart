import 'dart:async';

import 'package:calendar_app_flutter/widgets/subscription_dialog.dart';
import 'package:calendar_app_flutter/services/kbo_schedule.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openDialog(
  WidgetTester tester,
  Future<void> Function(KboTeam, bool) onToggle,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SubscriptionDialog(
                existingTeamCodes: const {'HT'},
                onToggle: onToggle,
              ),
            ),
            child: const Text('구독 추가하기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('구독 추가하기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'switches add and remove subscriptions without closing the two-column popup',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final changes = <String>[];
      await openDialog(tester, (team, enabled) async {
        changes.add('${team.code}:$enabled');
      });
      final kia = find.byKey(const ValueKey('subscription-HT'));
      final kt = find.byKey(const ValueKey('subscription-KT'));
      expect(tester.widget<CupertinoSwitch>(kia).value, isTrue);
      expect(tester.getCenter(kia).dy, tester.getCenter(kt).dy);
      expect(find.text('SSG 랜더스'), findsOneWidget);
      await tester.tap(kt);
      await tester.pumpAndSettle();
      expect(tester.widget<CupertinoSwitch>(kt).value, isTrue);
      await tester.tap(kia);
      await tester.pumpAndSettle();
      expect(tester.widget<CupertinoSwitch>(kia).value, isFalse);
      expect(changes, ['KT:true', 'HT:false']);
      expect(find.byType(SubscriptionDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed changes retain the switch state and allow retry', (
    tester,
  ) async {
    final pending = Completer<void>();
    await openDialog(tester, (_, _) => pending.future);
    final kt = find.byKey(const ValueKey('subscription-KT'));
    await tester.tap(kt);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<CupertinoSwitch>(
            find.byKey(const ValueKey('subscription-HT')),
          )
          .onChanged,
      isNull,
    );
    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(kt).value, isFalse);
    expect(tester.widget<CupertinoSwitch>(kt).onChanged, isNotNull);
    expect(find.textContaining('다시 시도'), findsOneWidget);
  });

  testWidgets('narrow popup scrolls to every team without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openDialog(tester, (_, _) async {});
    final hanwha = find.byKey(const ValueKey('subscription-HH'));
    await tester.ensureVisible(hanwha);
    await tester.pumpAndSettle();
    await tester.tap(hanwha);
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(hanwha).value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
