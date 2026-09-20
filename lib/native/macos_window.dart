import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Changes the macOS window only when the authentication destination changes.
class MacosWindow {
  static const channel = MethodChannel('calendar_app/window');

  static Future<void> showCalendar(bool calendar) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await channel.invokeMethod<void>(
        'setScreen',
        calendar ? 'calendar' : 'login',
      );
    } on MissingPluginException {
      // Widget tests and older native runners have no window channel.
    } on PlatformException catch (error) {
      debugPrint('Window transition failed: ${error.code}');
    }
  }
}
