import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:web/web.dart';

import '../logic/security_urls.dart';

/// Only the popup opened by this authentication attempt can finish it.
/// Credentials never pass through localStorage or a shared window name.
Future<String> authenticateOAuthBrowser({required String url}) async {
  if (secureBrowserAuthUri(url, allowInsecureLoopback: !kReleaseMode) == null) {
    throw PlatformException(code: 'invalid_url', message: '인증 주소를 확인하지 못했습니다.');
  }
  try {
    window.localStorage.removeItem('flutter-web-auth-2');
  } catch (_) {
    // Storage may be disabled; this flow never uses it for credentials.
  }
  final popup = window.open(url, '_blank', 'popup,width=500,height=700');
  if (popup == null) {
    throw PlatformException(code: 'popup_blocked', message: '로그인 팝업을 허용해 주세요.');
  }
  final completer = Completer<String>();
  StreamSubscription<MessageEvent>? subscription;
  Timer? timeout;
  Timer? closedCheck;
  try {
    subscription = window.onMessage.listen((event) {
      if (completer.isCompleted ||
          event.origin != Uri.base.origin ||
          event.source != popup) {
        return;
      }
      final data = event.data.dartify();
      if (data is! Map || data.length != 1) return;
      final callback = data['flutter-web-auth-2'];
      if (callback is! String || callback.length > 4096) return;
      completer.complete(callback);
    });
    timeout = Timer(const Duration(minutes: 5), () {
      if (!completer.isCompleted) {
        completer.completeError(
          PlatformException(code: 'timeout', message: '로그인 시간이 만료되었습니다.'),
        );
      }
    });
    closedCheck = Timer.periodic(const Duration(seconds: 1), (_) {
      if (popup.closed && !completer.isCompleted) {
        completer.completeError(
          PlatformException(code: 'canceled', message: '로그인이 취소되었습니다.'),
        );
      }
    });
    return await completer.future;
  } finally {
    timeout?.cancel();
    closedCheck?.cancel();
    await subscription?.cancel();
    popup.close();
  }
}
