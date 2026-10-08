// Run with: flutter run -d windows -t tool/windows_oauth_smoke.dart
// Reproduces closing the WebView during an OAuth navigation callback.
import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (runWebViewTitleBarWidget(args)) return;
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('로그인 창 종료 검증 중'))),
    ),
  );
  final folder = await getApplicationSupportDirectory();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write(
      '<html><title>OAuth regression check</title><body>'
      '<input placeholder="Login test"><script>setTimeout(() => {'
      'location.href="calendar://auth?code=${'A' * 43}";}, 300);</script></body></html>',
    );
    await request.response.close();
  });
  try {
    for (var attempt = 0; attempt < 3; attempt++) {
      var receivedCallback = false;
      final view = await WebviewWindow.create(
        configuration: CreateConfiguration(
          title: '로그인 종료 검증 ${attempt + 1}',
          userDataFolderWindows: '${folder.path}/oauth-regression-check',
        ),
      );
      view.setOnUrlRequestCallback((url) {
        final uri = Uri.parse(url);
        if (uri.scheme == 'calendar' && uri.host == 'auth') {
          receivedCallback = true;
          view.close();
          // flutter_web_auth_2 returns true after closing the view.
          // Its old native reply handler then accessed the destroyed object.
        }
        return true;
      });
      view.launch('http://127.0.0.1:${server.port}/');
      await view.onClose.timeout(const Duration(seconds: 15));
      if (!receivedCallback) {
        throw StateError('OAuth callback was not received');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      debugPrint('WINDOWS_OAUTH_CLOSE_PASS ${attempt + 1}');
    }
    debugPrint('WINDOWS_OAUTH_SMOKE_PASS');
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('로그인 창 종료 검증 통과'))),
      ),
    );
  } finally {
    await server.close(force: true);
  }
}
