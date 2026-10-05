/// URL checks used before handing untrusted links to a browser or accepting
/// browser authentication results. Never include the raw URL in an error.
final _urlWhitespace = RegExp(r'[\x00-\x20\x7f]');
final _codePattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

Uri? secureHttpsUri(String? raw) {
  if (raw == null || raw.isEmpty || raw.length > 4096) return null;
  if (_urlWhitespace.hasMatch(raw)) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Uri? secureBrowserAuthUri(String raw, {bool allowInsecureLoopback = false}) {
  final secure = secureHttpsUri(raw);
  if (secure != null) return secure;
  if (!allowInsecureLoopback || _urlWhitespace.hasMatch(raw)) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      raw.length > 4096 ||
      uri.scheme != 'http' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      !const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host)) {
    return null;
  }
  return uri;
}

Map<String, String> _callbackParameters(
  String raw, {
  required Set<String> allowedParameters,
  Uri? webOrigin,
}) {
  if (raw.length > 4096 || _urlWhitespace.hasMatch(raw)) {
    throw const FormatException('잘못된 인증 응답입니다. 다시 시도해 주세요.');
  }
  final callback = Uri.tryParse(raw);
  final validDestination =
      callback != null &&
      callback.userInfo.isEmpty &&
      !callback.hasFragment &&
      (webOrigin == null
          ? callback.scheme == 'calendar' &&
                callback.host == 'auth' &&
                !callback.hasPort &&
                callback.path.isEmpty
          : const {'https', 'http'}.contains(callback.scheme) &&
                callback.hasAuthority &&
                callback.origin == webOrigin.origin &&
                callback.path == '/auth.html');
  if (!validDestination) {
    throw const FormatException('잘못된 인증 응답입니다. 다시 시도해 주세요.');
  }
  final parameters = callback.queryParametersAll;
  if (parameters.entries.any(
    (entry) =>
        !allowedParameters.contains(entry.key) || entry.value.length != 1,
  )) {
    throw const FormatException('잘못된 인증 응답입니다. 다시 시도해 주세요.');
  }
  return parameters.map((key, value) => MapEntry(key, value.single));
}

String? _callbackError(Map<String, String> parameters) {
  final error = parameters['error'];
  if (error != null &&
      (error.isEmpty ||
          error.length > 512 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(error))) {
    throw const FormatException('잘못된 인증 응답입니다. 다시 시도해 주세요.');
  }
  return error;
}

class SocialAuthCallback {
  final String? code;
  final String? error;

  const SocialAuthCallback({this.code, this.error});
}

SocialAuthCallback parseSocialAuthCallback(String raw, {Uri? webOrigin}) {
  final parameters = _callbackParameters(
    raw,
    allowedParameters: const {'code', 'error'},
    webOrigin: webOrigin,
  );
  final code = parameters['code'];
  final error = _callbackError(parameters);
  if ((code == null) == (error == null) ||
      (code != null && (code.length != 43 || !_codePattern.hasMatch(code)))) {
    throw const FormatException('로그인 응답을 확인하지 못했습니다. 다시 시도해 주세요.');
  }
  return SocialAuthCallback(code: code, error: error);
}

class CalendarImportCallback {
  final bool success;
  final String? error;

  const CalendarImportCallback({required this.success, this.error});
}

CalendarImportCallback parseCalendarImportCallback(
  String raw, {
  required String provider,
  Uri? webOrigin,
}) {
  final parameters = _callbackParameters(
    raw,
    allowedParameters: const {'calendar_import', 'result', 'error'},
    webOrigin: webOrigin,
  );
  final error = _callbackError(parameters);
  final success = parameters['result'] == 'success';
  if (parameters['calendar_import'] != provider ||
      success == (error != null) ||
      (!success && parameters.containsKey('result'))) {
    throw const FormatException('캘린더 연결 응답을 확인하지 못했습니다. 다시 시도해 주세요.');
  }
  return CalendarImportCallback(success: success, error: error);
}
