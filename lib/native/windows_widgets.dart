import 'dart:convert';

import 'package:flutter/services.dart';

abstract final class WindowsWidgets {
  static const channel = MethodChannel('calendar_app/home_widget');
  static Future<void> launch(String mode) =>
      channel.invokeMethod('launchMini', mode);
  static Future<void> pin(bool pinned) => channel.invokeMethod('pin', pinned);
  static Future<void> openCalendar() => channel.invokeMethod('openCalendar');
  static Future<Map<String, dynamic>> read() async {
    final json = await channel.invokeMethod<String>('read');
    if (json == null || json.isEmpty) return {'signedIn': false, 'events': []};
    return jsonDecode(json) as Map<String, dynamic>;
  }
}
