import 'dart:convert';

import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/native/home_widget.dart';
import 'package:calendar_app_flutter/native/windows_widgets.dart';
import 'package:calendar_app_flutter/screens/windows_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(WindowsWidgets.channel, null);
  });
  test('Windows exports display data and clears it on logout', () async {
    final snapshots = <Map<String, dynamic>>[];
    messenger.setMockMethodCallHandler(WindowsWidgets.channel, (call) async {
      if (call.method == 'update') {
        snapshots.add(
          jsonDecode((call.arguments as Map)['snapshot'] as String)
              as Map<String, dynamic>,
        );
      }
      return null;
    });
    await CalendarHomeWidget.update(const {
      '2026-10-09': [
        CalendarEvent(
          id: 'secret',
          date: '2026-10-09',
          title: 'Windows fixture',
          duration: 30,
          color: '#547be8',
          description: 'private',
        ),
      ],
    }, signedIn: true);
    expect(snapshots.single['events'].toString(), isNot(contains('secret')));
    expect(snapshots.single['events'].toString(), isNot(contains('private')));
    await CalendarHomeWidget.clear();
    expect(snapshots.last['signedIn'], false);
    expect(snapshots.last['events'], isEmpty);
  });
  for (final mode in ['today', 'month', 'upcoming']) {
    testWidgets('$mode fits a compact window and clears after logout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var signedIn = true;
      final now = DateTime.now();
      final key =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      messenger.setMockMethodCallHandler(WindowsWidgets.channel, (call) async {
        if (call.method == 'read') {
          return jsonEncode({
            'signedIn': signedIn,
            'events': [
              {
                'date': key,
                'title': '회의 "안녕" \${x}',
                'time': '09:00',
                'color': '#547be8',
              },
            ],
          });
        }
        return null;
      });
      await tester.pumpWidget(WindowsMiniApp(mode: mode));
      await tester.pump();
      expect(find.text('회의 "안녕" \${x}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      signedIn = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('회의 "안녕" \${x}'), findsNothing);
      expect(find.textContaining('로그인하면'), findsOneWidget);
      if (mode == 'month') {
        for (var month = 0; month < 12; month++) {
          await tester.tap(find.byTooltip('다음 달'));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
