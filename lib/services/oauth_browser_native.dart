import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../logic/security_urls.dart';

Future<String> authenticateOAuthBrowser({required String url}) {
  if (secureBrowserAuthUri(url, allowInsecureLoopback: !kReleaseMode) == null) {
    throw PlatformException(code: 'invalid_url', message: '인증 주소를 확인하지 못했습니다.');
  }
  return FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: 'calendar');
}
