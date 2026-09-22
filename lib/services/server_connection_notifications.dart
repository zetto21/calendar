import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Android system notifications for server connectivity transitions.
///
/// The monitor calls this only when the connection state changes, never for
/// every health-check tick.
class ServerConnectionNotifications {
  ServerConnectionNotifications._();

  static const _channel = MethodChannel(
    'calendar/server_connection_notifications',
  );
  static Future<void>? _initialization;

  static Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<void> _initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;
    // Android 13+ permission is requested by the native implementation.
    // Failures here must never block the connection monitor itself.
    try {
      await _channel.invokeMethod<void>('initialize');
    } on PlatformException {
      // The in-app connection alert remains available if notifications fail.
    }
  }

  static Future<void> showDisconnected() => _show(
    id: 4101,
    title: '서버에 연결할 수 없습니다',
    body: '인터넷 연결을 확인한 후 새로고침해 주세요.',
  );

  static Future<void> showReconnected() =>
      _show(id: 4102, title: '서버 연결 복구', body: '서버에 다시 연결되었습니다.');

  static Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    await initialize();
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('show', {
        'id': id,
        'title': title,
        'body': body,
      });
    } on PlatformException {
      // Notification permission may have been denied by the user.
    }
  }
}
