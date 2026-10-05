import 'dart:async';
import 'dart:convert';

import 'package:calendar_app_flutter/services/auth_service.dart';
import 'package:calendar_app_flutter/services/secure_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Transport extends http.BaseClient {
  _Transport(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() => closed = true;
}

void main() {
  test('release API configuration rejects insecure and ambiguous origins', () {
    for (final origin in [
      'http://api.example.com',
      'https://user:password@api.example.com',
      'https://api.example.com/path',
      'https://api.example.com?query=1',
      'https://api.example.com#fragment',
      'file:///tmp/session',
      '',
    ]) {
      expect(
        () => AuthService.resolveApiBase(
          origin,
          isAndroid: false,
          allowInsecureHttp: false,
        ),
        throwsFormatException,
      );
    }
    expect(
      AuthService.resolveApiBase(
        'https://api.example.com/',
        isAndroid: false,
        allowInsecureHttp: false,
      ),
      'https://api.example.com',
    );
    expect(
      AuthService.resolveApiBase(
        'http://localhost:3001/',
        isAndroid: true,
        allowInsecureHttp: true,
      ),
      'http://10.0.2.2:3001',
    );
  });

  test(
    'credential requests disable redirects and close their transport',
    () async {
      final transport = _Transport((request) async {
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
      });
      final response = await secureHttpRequest(
        Uri.https('api.example.com', '/api/auth/me'),
        headers: {'Authorization': 'Bearer test-token'},
        client: transport,
      );
      expect(response.body, '{}');
      expect(transport.closed, isTrue);
    },
  );

  test(
    'redirect responses are rejected instead of parsed as credentials',
    () async {
      final transport = _Transport(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
          307,
          headers: {'location': 'https://attacker.example'},
        ),
      );
      await expectLater(
        secureHttpRequest(
          Uri.https('api.example.com', '/api/auth/login'),
          client: transport,
        ),
        throwsFormatException,
      );
      expect(transport.closed, isTrue);
    },
  );

  test('response limit applies to declared and streamed bytes', () async {
    for (final contentLength in [null, 100]) {
      final transport = _Transport(
        (_) async => http.StreamedResponse(
          Stream.fromIterable([
            [1, 2, 3],
            [4, 5, 6],
          ]),
          200,
          contentLength: contentLength,
        ),
      );
      await expectLater(
        secureHttpRequest(
          Uri.https('api.example.com', '/api/settings'),
          maxResponseBytes: 4,
          client: transport,
        ),
        throwsFormatException,
      );
      expect(transport.closed, isTrue);
    }
  });

  test('timeout completes the abort signal and closes the client', () async {
    final aborted = Completer<void>();
    final transport = _Transport((request) {
      (request as http.Abortable).abortTrigger!.then((_) => aborted.complete());
      return Completer<http.StreamedResponse>().future;
    });
    await expectLater(
      secureHttpRequest(
        Uri.https('api.example.com', '/api/auth/login'),
        timeout: const Duration(milliseconds: 20),
        client: transport,
      ),
      throwsA(isA<TimeoutException>()),
    );
    await aborted.future;
    expect(transport.closed, isTrue);
  });

  test('JSON nesting limit ignores brackets inside escaped strings', () {
    expect(
      () => decodeBoundedJson('${'[' * 65}0${']' * 65}'),
      throwsFormatException,
    );
    final value = {'text': r'[[[\"{}]]]'};
    expect(decodeBoundedJson(jsonEncode(value), maxDepth: 1), value);
  });
}
