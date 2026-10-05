import 'dart:async';

import 'package:calendar_app_flutter/widgets/server_connection_monitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => ServerConnectionMonitor.available.value = null);

  Future<void> mount(WidgetTester tester, Future<bool> Function() check) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ServerConnectionMonitor(
          checkConnection: check,
          child: const Scaffold(body: Text('Calendar')),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tick(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
  }

  testWidgets(
    'transient failures do not interrupt the app; recovery resets failures',
    (tester) async {
      var connected = true;
      await mount(tester, () async => connected);
      connected = false;
      await tick(tester);
      await tick(tester);
      expect(ServerConnectionMonitor.available.value, isTrue);
      expect(find.text('서버에 연결할 수 없습니다'), findsNothing);
      connected = true;
      await tick(tester);
      connected = false;
      await tick(tester);
      await tick(tester);
      expect(find.text('서버에 연결할 수 없습니다'), findsNothing);
      await tick(tester);
      expect(ServerConnectionMonitor.available.value, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('서버에 연결할 수 없습니다'), findsOneWidget);
      connected = true;
      await tick(tester);
      expect(ServerConnectionMonitor.available.value, isTrue);
      expect(find.text('서버에 연결할 수 없습니다'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a probe finishing in the background does not display an outage',
    (tester) async {
      final pending = Completer<bool>();
      await mount(tester, () => pending.future);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(false);
      await tester.pump();
      expect(ServerConnectionMonitor.available.value, isNull);
      expect(find.text('서버에 연결할 수 없습니다'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
}
