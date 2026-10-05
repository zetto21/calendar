@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:calendar_app_flutter/services/oauth_browser_web.dart';

void main() {
  late JSAny? originalOpen;
  late JSObject popup;
  late web.HTMLIFrameElement frame;
  var closed = false;

  setUp(() {
    originalOpen = web.window.getProperty('open'.toJS);
    closed = false;
    frame = web.HTMLIFrameElement();
    web.document.body!.append(frame);
    popup = frame.contentWindow!;
    popup.setProperty('close'.toJS, (() => closed = true).toJS);
    web.window.setProperty(
      'open'.toJS,
      ((String url, String target, String features) => popup).toJS,
    );
  });

  tearDown(() {
    web.window.setProperty('open'.toJS, originalOpen);
    frame.remove();
  });

  void message({
    required String origin,
    required JSObject source,
    JSAny? data,
  }) {
    web.window.dispatchEvent(
      web.MessageEvent(
        'message',
        web.MessageEventInit(origin: origin, source: source, data: data),
      ),
    );
  }

  test(
    'rejects other sources, other origins, and malformed callback messages',
    () async {
      var completed = false;
      final future = authenticateOAuthBrowser(url: 'https://api.example/start')
          .then((value) {
            completed = true;
            return value;
          });
      final callback = '${Uri.base.origin}/auth.html?code=${'a' * 43}';
      final data = {'flutter-web-auth-2': callback}.jsify();
      message(origin: 'https://evil.example', source: popup, data: data);
      message(origin: Uri.base.origin, source: web.window, data: data);
      message(origin: Uri.base.origin, source: popup, data: 'invalid'.toJS);
      message(
        origin: Uri.base.origin,
        source: popup,
        data: {'flutter-web-auth-2': callback, 'extra': true}.jsify(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      message(origin: Uri.base.origin, source: popup, data: data);
      expect(await future, callback);
      expect(closed, isTrue);

      // A second callback after completion must not complete the Future twice.
      message(origin: Uri.base.origin, source: popup, data: data);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('rejects executable browser URLs before opening a popup', () async {
    await expectLater(
      authenticateOAuthBrowser(url: 'javascript:alert(1)'),
      throwsA(isA<PlatformException>()),
    );
    expect(closed, isFalse);
  });

  test(
    'reports a blocked popup without registering a callback listener',
    () async {
      web.window.setProperty(
        'open'.toJS,
        ((String url, String target, String features) => null).toJS,
      );
      await expectLater(
        authenticateOAuthBrowser(url: 'https://api.example/start'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
