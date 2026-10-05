import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

import '../models/calendar_event.dart';
import 'secure_http.dart';
import 'session_storage_stub.dart'
    if (dart.library.js_interop) 'session_storage_web.dart'
    as browser_session;

class ImportCalendar {
  final String id, title, color;
  final String category;
  final bool nameUnavailable;
  const ImportCalendar({
    required this.id,
    required this.title,
    required this.color,
    this.category = '',
    this.nameUnavailable = false,
  });
  factory ImportCalendar.fromJson(Map<String, dynamic> json) {
    final id = _checkedString(json['id'], maxLength: 500);
    final title = _checkedString(json['title'], maxLength: 4096);
    final color = _checkedColor(json['color'] ?? '#707078');
    final category = _checkedString(
      json['category'] ?? '',
      maxLength: 64,
      allowEmpty: true,
    );
    if (json['nameUnavailable'] != null && json['nameUnavailable'] is! bool) {
      throw const FormatException('캘린더 형식이 올바르지 않습니다.');
    }
    return ImportCalendar(
      id: id,
      title: title,
      color: color,
      category: category,
      nameUnavailable: json['nameUnavailable'] == true,
    );
  }
}

class ImportedEvent {
  final String id, date, title, color;
  final String? time;
  final int duration;
  const ImportedEvent({
    required this.id,
    required this.date,
    required this.title,
    required this.color,
    this.time,
    required this.duration,
  });
  factory ImportedEvent.fromJson(Map<String, dynamic> json) {
    final event = CalendarEvent.fromJson({
      ...json,
      'color': json['color'] ?? '#707078',
    });
    return ImportedEvent(
      id: event.id,
      date: event.date,
      title: event.title,
      color: event.color,
      time: event.time,
      duration: event.duration,
    );
  }
}

class AuthUser {
  final String id;
  final String email;
  final String name;
  final String createdAt;
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: _checkedString(json['id'], maxLength: 256),
    email: _checkedString(
      json['email'] ?? '',
      maxLength: 254,
      allowEmpty: true,
    ),
    name: _checkedString(json['name'] ?? '', maxLength: 4096, allowEmpty: true),
    createdAt: _checkedString(
      json['createdAt'] ?? '',
      maxLength: 64,
      allowEmpty: true,
    ),
  );
}

String _checkedString(
  Object? value, {
  required int maxLength,
  bool allowEmpty = false,
}) {
  if (value is! String ||
      value.length > maxLength ||
      value.contains('\u0000') ||
      (!allowEmpty && value.trim().isEmpty)) {
    throw const FormatException('서버 응답 형식이 올바르지 않습니다.');
  }
  return value;
}

String _checkedColor(Object? value) {
  final color = _checkedString(value, maxLength: 7);
  if (!RegExp(r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(color)) {
    throw const FormatException('색상 형식이 올바르지 않습니다.');
  }
  return color;
}

bool _validSessionToken(String token) =>
    RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token);

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

enum SocialProvider { naver, kakao, google, apple, facebook }

class ServerConnectionException extends AuthException {
  ServerConnectionException()
    : super('서버에 연결할 수 없습니다. 인터넷 연결을 확인한 후 다시 시도해 주세요.');
}

/// Port of calendar_app/lib/auth.ts + lib/sessionStorage.ts, talking to the
/// same calendar_api backend — email/password auth plus social/OAuth login
/// (an in-app browser session redirecting back to the calendar:// scheme,
/// mirroring components/LoginScreen.tsx's use of expo-web-browser).
class AuthService {
  AuthService._() : this._withClient(null);
  static final AuthService instance = AuthService._();

  @visibleForTesting
  AuthService.forTesting({http.Client Function()? clientFactory})
    : this._withClient(clientFactory);

  AuthService._withClient(this._clientFactory);

  final http.Client Function()? _clientFactory;

  static const _sessionChannel = MethodChannel('calendar_app/session');
  bool get _persistSession =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  String? _sessionToken;
  AuthUser? _sessionUser;
  int _sessionGeneration = 0;
  Future<void> _sessionStorageQueue = Future.value();
  bool _sessionReadAllowed = true;

  /// Tab-scoped browser storage survives reloads without leaving a long-lived
  /// bearer token in localStorage after the tab closes.
  String get _webSessionKey => 'calendar.session.$apiBase';

  String _encodeSession(String token, AuthUser user) => jsonEncode({
    'token': token,
    'user': {
      'id': user.id,
      'email': user.email,
      'name': user.name,
      'createdAt': user.createdAt,
    },
  });

  Future<void> _queueSessionStorage(Future<void> Function() operation) {
    final pending = _sessionStorageQueue.then((_) => operation());
    _sessionStorageQueue = pending.catchError((Object _) {});
    return pending;
  }

  Future<void> _saveSession(String token, AuthUser user, int generation) async {
    if (!_validSessionToken(token)) {
      throw AuthException('로그인 응답 형식이 올바르지 않습니다.');
    }
    await _queueSessionStorage(() async {
      if (generation != _sessionGeneration) {
        throw AuthException('로그인 요청이 취소되었습니다. 다시 로그인해 주세요.');
      }
      if (kIsWeb) {
        try {
          browser_session.deleteLegacySession(_webSessionKey);
          browser_session.writeSession(
            _webSessionKey,
            _encodeSession(token, user),
          );
        } catch (_) {
          /* Keep a memory session if browser storage is blocked. */
        }
      }
      if (_persistSession) {
        await _sessionChannel.invokeMethod<void>('write', {
          'account': apiBase,
          'value': _encodeSession(token, user),
        });
      }
      if (generation != _sessionGeneration) {
        throw AuthException('로그인 요청이 취소되었습니다. 다시 로그인해 주세요.');
      }
      _sessionToken = token;
      _sessionUser = user;
      _sessionReadAllowed = false;
    });
  }

  Future<void> _clearSession() async {
    _sessionGeneration++;
    _sessionToken = null;
    _sessionUser = null;
    _sessionReadAllowed = false;
    await _queueSessionStorage(() async {
      if (kIsWeb) {
        try {
          browser_session.deleteSession(_webSessionKey);
          browser_session.deleteLegacySession(_webSessionKey);
        } catch (_) {}
      }
      if (_persistSession) {
        await _sessionChannel.invokeMethod<void>('delete', {
          'account': apiBase,
        });
      }
    });
  }

  /// Same `https://api.ilsngcal.com` default as calendar_app/.env.example.
  /// Override at build/run time with `--dart-define=API_BASE_URL=...` (a LAN
  /// IP) when testing on a physical device.
  static const _configuredBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.ilsangcal.com/',
  );

  static String get apiBase {
    return resolveApiBase(
      _configuredBase,
      isAndroid: !kIsWeb && Platform.isAndroid,
    );
  }

  @visibleForTesting
  static String resolveApiBase(
    String configuredBase, {
    required bool isAndroid,
    bool allowInsecureHttp = !kReleaseMode,
  }) {
    var base = validateApiBase(
      configuredBase,
      allowInsecureHttp: allowInsecureHttp,
    ).toString();
    // The Android emulator's own loopback isn't the host machine's; 10.0.2.2
    // is the special alias Android provides for reaching it.
    if (isAndroid) {
      base = base.replaceFirstMapped(
        RegExp(r'^(https?://)(localhost|127\.0\.0\.1)(?=[:/]|$)'),
        (match) => '${match[1]}10.0.2.2',
      );
    }
    return base;
  }

  /// Probe reachability without depending on the OAuth provider configuration.
  /// Closing this dedicated client also cancels a request that times out.
  Future<bool> checkConnection({
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final probe = client ?? http.Client();
    try {
      final response = await secureHttpRequest(
        Uri.parse('$apiBase/api/auth/oauth/providers'),
        timeout: timeout,
        maxResponseBytes: 64 << 10,
        client: probe,
      );
      return response.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      probe.close();
    }
  }

  Future<T> _request<T>(
    String path,
    T Function(Map<String, dynamic>?) parse, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
    Duration timeout = const Duration(seconds: 15),
    bool requireCurrentSession = true,
  }) async {
    final generation = _sessionGeneration;
    if (token != null && requireCurrentSession && token != _sessionToken) {
      throw AuthException('로그인이 필요합니다.');
    }
    final uri = Uri.parse('$apiBase$path');
    final headers = {
      if (method == 'POST') 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    http.Response response;
    try {
      response = await secureHttpRequest(
        uri,
        method: method,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
        timeout: timeout,
        client: _clientFactory?.call(),
      );
    } on FormatException {
      throw AuthException('서버 응답을 안전하게 처리하지 못했습니다.');
    } catch (_) {
      throw ServerConnectionException();
    }
    if (token != null &&
        requireCurrentSession &&
        (generation != _sessionGeneration || token != _sessionToken)) {
      throw AuthException('계정이 변경되었습니다. 다시 시도해 주세요.');
    }
    if (response.statusCode >= 500) throw ServerConnectionException();
    if (response.statusCode == 401 && path == '/api/auth/me') {
      return parse(null);
    }
    if (response.statusCode == 204) return parse(null);
    Map<String, dynamic>? decoded;
    try {
      decoded = response.body.isEmpty
          ? null
          : decodeBoundedJson(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>;
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        decoded?['error'] is String
            ? (decoded!['error'] as String).substring(
                0,
                (decoded['error'] as String).length.clamp(0, 1024),
              )
            : '서버 요청을 처리하지 못했습니다.',
      );
    }
    if (decoded == null) throw AuthException('서버 응답 형식이 올바르지 않습니다.');
    try {
      return parse(decoded);
    } on FormatException {
      throw AuthException('서버 응답 형식이 올바르지 않습니다.');
    } on TypeError {
      throw AuthException('서버 응답 형식이 올바르지 않습니다.');
    } on RangeError {
      throw AuthException('서버 응답 형식이 올바르지 않습니다.');
    }
  }

  Future<AuthUser> _authenticate(
    String path,
    String email,
    String password,
  ) async {
    final generation = ++_sessionGeneration;
    final result = await _request(
      path,
      (json) => (
        token: json!['token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      ),
      method: 'POST',
      body: {'email': email.trim(), 'password': password},
    );
    await _saveSession(result.token, result.user, generation);
    return result.user;
  }

  Future<AuthUser> login(String email, String password) =>
      _authenticate('/api/auth/login', email, password);

  Future<AuthUser> register(String email, String password) =>
      _authenticate('/api/auth/register', email, password);

  Future<AuthUser?> restoreSession() async {
    final generation = _sessionGeneration;
    if (_sessionToken == null &&
        _sessionReadAllowed &&
        (kIsWeb || _persistSession)) {
      try {
        await _sessionStorageQueue;
        if (generation != _sessionGeneration) return null;
        String? saved;
        if (kIsWeb) {
          browser_session.deleteLegacySession(_webSessionKey);
          saved = browser_session.readSession(_webSessionKey);
        } else {
          saved = await _sessionChannel.invokeMethod<String>('read', {
            'account': apiBase,
          });
        }
        if (generation != _sessionGeneration) return null;
        _sessionReadAllowed = false;
        if (saved != null) {
          if (saved.length > 16 << 10) {
            throw const FormatException('Invalid session');
          }
          final data =
              decodeBoundedJson(saved, maxDepth: 8) as Map<String, dynamic>;
          final token = data['token'] as String;
          if (!_validSessionToken(token)) {
            throw const FormatException('Invalid token');
          }
          final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
          _sessionToken = token;
          _sessionUser = user;
        }
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      } catch (_) {
        if (generation == _sessionGeneration) await _clearSession();
        return null;
      }
    }
    final token = _sessionToken;
    if (token == null) return null;
    try {
      final user = await _request(
        '/api/auth/me',
        (json) => json == null
            ? null
            : AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        token: token,
        timeout: const Duration(seconds: 5),
      );
      if (generation != _sessionGeneration) return null;
      if (user == null) {
        await _clearSession();
      } else {
        await _saveSession(token, user, generation);
      }
      return user;
    } on ServerConnectionException {
      // Offline access uses only the current account's previously saved local
      // cache. Server requests still require a valid bearer session.
      return generation == _sessionGeneration ? _sessionUser : null;
    } on AuthException {
      return null;
    }
  }

  Future<void> logout() async {
    final token = _sessionToken;
    // Invalidate first: a delayed login/restore/logout must not resurrect an
    // old account or clear a newer session while server revocation is pending.
    Object? failure;
    try {
      await _clearSession();
    } catch (error) {
      failure = error;
    }
    if (token != null) {
      try {
        await _request(
          '/api/auth/logout',
          (_) => null,
          method: 'POST',
          token: token,
          requireCurrentSession: false,
        );
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }

  Future<List<SocialProvider>> enabledSocialProviders() async {
    final ids = await _request(
      '/api/auth/oauth/providers',
      (json) => (json!['providers'] as List).cast<String>(),
      timeout: const Duration(seconds: 4),
    );
    return SocialProvider.values
        .where((provider) => ids.contains(provider.name))
        .toList();
  }

  Future<
    ({
      Map<String, String> holidays,
      Map<String, String> solarTerms,
      Map<String, List<String>> anniversaries,
    })
  >
  specialDays(int year) => _request('/api/holidays?year=$year', (json) {
    final holidays = <String, String>{};
    final solarTerms = <String, String>{};
    final anniversaries = <String, List<String>>{};
    for (final item in (json!['items'] as List).cast<Map<String, dynamic>>()) {
      final kind = item['kind'];
      if (kind == 'holiday' || kind == 'nationalHoliday') {
        holidays[item['date'] as String] = item['name'] as String;
      } else if (kind == 'anniversary') {
        (anniversaries[item['date'] as String] ??= []).add(
          item['name'] as String,
        );
      } else if (kind == 'solarTerm') {
        solarTerms[item['date'] as String] = item['name'] as String;
      }
    }
    return (
      holidays: holidays,
      solarTerms: solarTerms,
      anniversaries: anniversaries,
    );
  });

  String socialLoginStartURL(SocialProvider provider, {String? codeChallenge}) {
    if (codeChallenge != null && !_validSessionToken(codeChallenge)) {
      throw AuthException('로그인 인증 정보가 올바르지 않습니다.');
    }
    return Uri.parse('$apiBase/api/auth/oauth/${provider.name}/start')
        .replace(
          queryParameters: {
            'client_challenge': ?codeChallenge,
            if (kIsWeb) 'client': 'web',
            if (kIsWeb) 'return': Uri.base.origin,
          },
        )
        .toString();
  }

  /// iOS/macOS system Sign in with Apple: the server verifies the identity
  /// token against the app's bundle ID and the one-time [nonce].
  Future<AuthUser> signInWithAppleNative({
    required String identityToken,
    required String nonce,
    String? name,
  }) async {
    final generation = ++_sessionGeneration;
    final result = await _request(
      '/api/auth/oauth/apple/native',
      (json) => (
        token: json!['token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      ),
      method: 'POST',
      body: {
        'identityToken': identityToken,
        'nonce': nonce,
        if (name != null && name.isNotEmpty) 'name': name,
      },
    );
    await _saveSession(result.token, result.user, generation);
    return result.user;
  }

  Future<AuthUser> exchangeSocialCode(
    String code, {
    String? clientVerifier,
  }) async {
    if (!_validSessionToken(code) ||
        clientVerifier != null &&
            !RegExp(r'^[A-Za-z0-9._~-]{43,128}$').hasMatch(clientVerifier)) {
      throw AuthException('로그인 인증 정보가 올바르지 않습니다.');
    }
    final generation = ++_sessionGeneration;
    final result = await _request(
      '/api/auth/oauth/exchange',
      (json) => (
        token: json!['token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      ),
      method: 'POST',
      body: {'code': code, 'clientVerifier': ?clientVerifier},
    );
    await _saveSession(result.token, result.user, generation);
    return result.user;
  }

  Future<List<Map<String, dynamic>>> syncEvents(
    String userId,
    List<Map<String, dynamic>> changes,
  ) async {
    final token = _accountToken(userId);
    return _request(
      '/api/events/sync?user=${Uri.encodeQueryComponent(userId)}',
      (json) => (json!['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      method: 'POST',
      body: {'changes': changes},
      token: token,
      timeout: const Duration(seconds: 5),
    );
  }

  Future<Map<String, dynamic>> loadSettings(String userId) async {
    final token = _accountToken(userId);
    return _request(
      '/api/settings?user=${Uri.encodeQueryComponent(userId)}',
      (json) => Map<String, dynamic>.from(json!['values'] as Map),
      token: token,
      timeout: const Duration(seconds: 5),
    );
  }

  Future<void> saveSettings(String userId, Map<String, dynamic> values) async {
    final token = _accountToken(userId);
    await _request(
      '/api/settings?user=${Uri.encodeQueryComponent(userId)}',
      (_) => null,
      method: 'POST',
      body: values,
      token: token,
      timeout: const Duration(seconds: 5),
    );
  }

  Future<String> calendarImportStart(String provider) async {
    _validateImportProvider(provider);
    final token = _sessionToken;
    if (token == null) throw AuthException('로그인이 필요합니다.');
    return _request(
      '/api/calendar-import/$provider/connect',
      (json) => json!['url'] as String,
      method: 'POST',
      token: token,
    );
  }

  Future<List<ImportCalendar>> importCalendars(String provider) async {
    _validateImportProvider(provider);
    final token = _sessionToken;
    if (token == null) throw AuthException('로그인이 필요합니다.');
    return _request(
      '/api/calendar-import/$provider/calendars',
      (json) => (json!['items'] as List)
          .map(
            (item) =>
                ImportCalendar.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      token: token,
    );
  }

  Future<List<ImportedEvent>> importEvents(
    String provider,
    String calendar,
    DateTime from,
    DateTime to,
  ) async {
    _validateImportProvider(provider);
    final token = _sessionToken;
    if (token == null) throw AuthException('로그인이 필요합니다.');
    final query = Uri(
      queryParameters: {
        'calendar': calendar,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    ).query;
    return _request(
      '/api/calendar-import/$provider/events?$query',
      (json) => (json!['items'] as List)
          .map(
            (item) =>
                ImportedEvent.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      token: token,
    );
  }

  String _accountToken(String userId) {
    final token = _sessionToken;
    if (token == null || _sessionUser?.id != userId) {
      throw AuthException('로그인한 계정과 요청 계정이 다릅니다.');
    }
    return token;
  }

  void _validateImportProvider(String provider) {
    if (!const ['google', 'kakao', 'notion'].contains(provider)) {
      throw AuthException('지원하지 않는 캘린더입니다.');
    }
  }
}
