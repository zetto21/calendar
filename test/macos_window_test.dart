import 'package:calendar_app_flutter/native/macos_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
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

  test(
    'login, calendar and logout request their native window modes',
    () async {
      await MacosWindow.showCalendar(false);
      await MacosWindow.showCalendar(true);
      await MacosWindow.showCalendar(false);
      expect(calls.map((call) => call.method), everyElement('setScreen'));
      expect(calls.map((call) => call.arguments), [
        'login',
        'calendar',
        'login',
      ]);
    },
  );

  test('mobile never requests a desktop window change', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await MacosWindow.showCalendar(true);
    expect(calls, isEmpty);
  });
}
