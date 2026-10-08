import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/calendar_event.dart';

/// A minimal display snapshot; credentials and account identifiers stay in-app.
abstract final class CalendarHomeWidget {
  static const _channel = MethodChannel('calendar_app/home_widget');
  static Future<void> _queue = Future.value();
  static String? _last;

  static Future<void> update(EventMap events, {required bool signedIn}) {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.windows)) {
      return Future.value();
    }
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    // Keep current and upcoming days when the shared snapshot reaches its cap.
    final days = events.keys.toList()
      ..sort((a, b) {
        final aPast = a.compareTo(today) < 0;
        final bPast = b.compareTo(today) < 0;
        if (aPast != bPast) return aPast ? 1 : -1;
        return a.compareTo(b);
      });
    final snapshot = jsonEncode({
      'signedIn': signedIn,
      'events': [
        if (signedIn)
          for (final day in days)
            for (final event in events[day]!)
              {
                'date': event.date,
                'title': event.title.length > 120
                    ? event.title.substring(0, 120)
                    : event.title,
                'time': event.time,
                'duration': event.duration,
                'color': event.color,
              },
      ].take(500).toList(),
    });
    final operation = _queue.then((_) async {
      if (_last == snapshot) return;
      try {
        await _channel.invokeMethod<void>('update', {'snapshot': snapshot});
        _last = snapshot;
      } on PlatformException {
        // Retry on the next edit or foreground refresh.
      } on MissingPluginException {
        // Desktop and tests do not host mobile home-screen widgets.
      }
    });
    _queue = operation.catchError((Object _) {});
    return operation;
  }

  static Future<void> clear() => update(const {}, signedIn: false);
}
