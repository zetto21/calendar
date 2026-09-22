import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native macOS notifications; false lets callers keep an in-app fallback.
class DesktopNotifications {
  static const _channel = MethodChannel('calendar/desktop_notifications');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Future<bool> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('show', {
            'id': id,
            'title': title,
            'body': body,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
