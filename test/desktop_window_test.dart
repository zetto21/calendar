import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_app_flutter/native/macos_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MacosWindow.channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MacosWindow.channel, null);
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    test('$platform switches between fixed authentication and calendar', () async {
      debugDefaultTargetPlatformOverride = platform;
      await MacosWindow.showCalendar(false);
      await MacosWindow.showCalendar(true);
      await MacosWindow.showCalendar(false);
      expect(calls.map((call) => call.method), everyElement('setScreen'));
      expect(calls.map((call) => call.arguments), ['login', 'calendar', 'login']);
    });
  }

  test('mobile does not call the desktop window channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await MacosWindow.showCalendar(false);
    expect(calls, isEmpty);
  });
}
