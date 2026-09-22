import 'package:calendar_app_flutter/services/desktop_notifications.dart';
import 'package:calendar_app_flutter/services/server_connection_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('calendar/desktop_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('server transitions use native macOS notification content', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    expect(await ServerConnectionNotifications.showDisconnected(), isTrue);
    expect(await ServerConnectionNotifications.showReconnected(), isTrue);
    expect(calls.map((call) => call.arguments['id']), [4101, 4102]);
    expect(calls.first.arguments['title'], '서버에 연결할 수 없습니다');
    expect(calls.last.arguments['title'], '서버 연결 복구');
  });

  test(
    'denied permission and native errors enable the in-app fallback',
    () async {
      Future<bool> send() =>
          DesktopNotifications.show(id: 1, title: '알림', body: '내용');
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      expect(await send(), isFalse);
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'unavailable');
      });
      expect(await send(), isFalse);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await send(), isFalse);
    },
  );

  test('other platforms do not invoke the macOS channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('macOS channel must not be called');
    });
    expect(
      await DesktopNotifications.show(id: 1, title: '알림', body: '내용'),
      isFalse,
    );
  });
}
