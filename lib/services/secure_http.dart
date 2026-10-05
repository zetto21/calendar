import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Invalid configuration must fail before sending passwords or bearer tokens.
Uri validateApiBase(String value, {required bool allowInsecureHttp}) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      (uri.scheme != 'https' && !(allowInsecureHttp && uri.scheme == 'http'))) {
    throw const FormatException('API 주소는 HTTPS 출처로 설정해 주세요.');
  }
  return uri.replace(path: '');
}

/// Returns a bounded response and aborts the transport on timeout. Redirects
/// are rejected before they can carry credentials to another endpoint.
Future<http.Response> secureHttpRequest(
  Uri uri, {
  String method = 'GET',
  Map<String, String> headers = const {},
  String? body,
  Duration timeout = const Duration(seconds: 15),
  int maxResponseBytes = 16 << 20,
  http.Client? client,
}) async {
  final transport = client ?? http.Client();
  final abort = Completer<void>();
  final request = http.AbortableRequest(method, uri, abortTrigger: abort.future)
    ..followRedirects = false
    ..maxRedirects = 0
    ..headers.addAll(headers);
  if (body != null) request.body = body;
  try {
    return await (() async {
      final response = await transport.send(request);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const FormatException('서버 리디렉션은 허용하지 않습니다.');
      }
      if ((response.contentLength ?? 0) > maxResponseBytes) {
        throw const FormatException('서버 응답이 너무 큽니다.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw const FormatException('서버 응답이 너무 큽니다.');
        }
        bytes.add(chunk);
      }
      return http.Response.bytes(
        bytes.takeBytes(),
        response.statusCode,
        headers: response.headers,
        request: request,
        reasonPhrase: response.reasonPhrase,
      );
    })().timeout(timeout);
  } finally {
    if (!abort.isCompleted) abort.complete();
    transport.close();
  }
}

Object? decodeBoundedJson(String source, {int maxDepth = 64}) {
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (final code in source.codeUnits) {
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (code == 92) {
        escaped = true;
      } else if (code == 34) {
        quoted = false;
      }
    } else if (code == 34) {
      quoted = true;
    } else if (code == 123 || code == 91) {
      if (++depth > maxDepth) {
        throw const FormatException('JSON 중첩이 너무 깊습니다.');
      }
    } else if (code == 125 || code == 93) {
      depth--;
    }
  }
  return jsonDecode(source);
}
