import 'dart:convert';

import 'package:calendar_app_flutter/models/calendar_event.dart';
import 'package:calendar_app_flutter/native/home_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('calendar_app/home_widget');
  test('publishes only display data and removes events on logout', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final snapshots = <Map<String, dynamic>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      snapshots.add(
        jsonDecode((call.arguments as Map)['snapshot'] as String)
            as Map<String, dynamic>,
      );
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    const events = {
      '2026-10-07': [
        CalendarEvent(
          id: 'private-id',
          date: '2026-10-07',
          title: '회의',
          description: 'private description',
          location: 'private location',
          time: '09:00',
          duration: 60,
          color: '#FF6600',
        ),
      ],
    };
    await CalendarHomeWidget.update(events, signedIn: true);
    await CalendarHomeWidget.update(events, signedIn: true);
    expect(snapshots, hasLength(1));
    expect((snapshots.single['events'] as List).single, {
      'date': '2026-10-07',
      'title': '회의',
      'time': '09:00',
      'duration': 60,
      'color': '#FF6600',
    });
    await CalendarHomeWidget.update(events, signedIn: false);
    expect(snapshots.last['events'], isEmpty);
    expect(snapshots.last['signedIn'], false);
  });
  test('snapshot cap keeps current events ahead of past month events', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    Map<String, dynamic>? snapshot;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      snapshot = jsonDecode(
        (call.arguments as Map)['snapshot'] as String,
      ) as Map<String, dynamic>;
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    final now = DateTime.now();
    String key(DateTime day) =>
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final today = key(now);
    final yesterday = key(DateTime(now.year, now.month, now.day - 1));
    CalendarEvent event(String date, String title) => CalendarEvent(
      id: title,
      date: date,
      title: title,
      duration: 60,
      color: '#FF6600',
    );
    await CalendarHomeWidget.update({
      yesterday: List.generate(500, (i) => event(yesterday, '과거 $i')),
      today: [event(today, '오늘 일정')],
    }, signedIn: true);
    final saved = snapshot!['events'] as List;
    expect(saved, hasLength(500));
    expect((saved.first as Map)['title'], '오늘 일정');
  });
}
