import 'dart:async';

import 'package:flutter/services.dart';

/// Opens the Flutter DevTools server attached to this macOS app's VM.
class FlutterDevToolsLauncher {
  static const _channel = MethodChannel('calendar_app/devtools');

  static Future<void> open() async {
    await _channel.invokeMethod<void>('open');
  }
}
