import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/security_urls.dart';

Future<String> authenticateOAuthBrowser({required String url}) async {
  if (secureBrowserAuthUri(url, allowInsecureLoopback: !kReleaseMode) == null) {
    throw PlatformException(code: 'invalid_url', message: '인증 주소를 확인하지 못했습니다.');
  }
  if (Platform.isWindows &&
      Uri.parse(url).path.startsWith('/api/auth/oauth/')) {
    return _authenticateExternalBrowser(Uri.parse(url));
  }
  return FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: 'calendar');
}

Future<String> _authenticateExternalBrowser(Uri start) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final nonce = List.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  final callback = Uri.parse('http://127.0.0.1:${server.port}/auth/$nonce');
  final result = Completer<String>();
  final subscription = server.listen((request) async {
    if (request.method != 'GET' ||
        request.uri.path != callback.path ||
        request.headers.value(HttpHeaders.hostHeader) != callback.authority) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final response = Uri.parse('calendar://auth')
        .replace(query: request.uri.query)
        .toString();
    try {
      parseSocialAuthCallback(response);
    } on FormatException {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.html;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.headers.set('Referrer-Policy', 'no-referrer');
    request.response.write(
      '<!doctype html><html lang="ko"><meta charset="utf-8">'
      '<title>캘린더 로그인</title><body>로그인 응답을 받았습니다. '
      '캘린더 앱으로 돌아가세요.</body></html>',
    );
    await request.response.close();
    if (!result.isCompleted) result.complete(response);
  });
  try {
    final launched = await launchUrl(
      start.replace(
        queryParameters: {
          ...start.queryParameters,
          'client': 'desktop',
          'return': callback.toString(),
        },
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw PlatformException(
        code: 'browser_unavailable',
        message: '브라우저를 열지 못했습니다.',
      );
    }
    return await result.future.timeout(const Duration(minutes: 5));
  } finally {
    await subscription.cancel();
    await server.close(force: true);
  }
}
