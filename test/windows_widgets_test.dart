import 'dart:convert';

import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/native/home_widget.dart';
import 'package:flutter/services.dart';
import 'package:calendar_app_flutter/screens/windows_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('calendar_app/home_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('Windows exports display data and clears it on logout', () async {
    final snapshots = <Map<String, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
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
}
