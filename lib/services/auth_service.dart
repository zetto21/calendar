import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ImportCalendar {
  final String id, title, color;
  const ImportCalendar({
    required this.id,
    required this.title,
    required this.color,
  });
  factory ImportCalendar.fromJson(Map<String, dynamic> json) => ImportCalendar(
    id: json['id'] as String,
    title: json['title'] as String,
    color: json['color'] as String? ?? '#707078',
  );
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
  factory ImportedEvent.fromJson(Map<String, dynamic> json) => ImportedEvent(
    id: json['id'] as String,
    date: json['date'] as String,
    title: json['title'] as String,
    color: json['color'] as String? ?? '#707078',
    time: json['time'] as String?,
    duration: (json['duration'] as num).toInt(),
  );
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
    id: json['id'] as String,
    email: json['email'] as String? ?? '',
    name: json['name'] as String? ?? '',
    createdAt: json['createdAt'] as String? ?? '',
  );
}

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
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'calendar_session_token';

  /// Same `http://localhost:3001` default as calendar_app/.env.example.
  /// Override at build/run time with `--dart-define=API_BASE_URL=...` (a LAN
  /// IP) when testing on a physical device.
  static const _configuredBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3001',
  );

  String _apiBase() {
    var base = _configuredBase;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    // The Android emulator's own loopback isn't the host machine's; 10.0.2.2
    // is the special alias Android provides for reaching it.
    if (!kIsWeb && Platform.isAndroid) {
      base = base.replaceFirst(
        RegExp(r'^(https?://)(localhost|127\.0\.0\.1)(?=[:/]|$)'),
        r'$110.0.2.2',
      );
    }
    return base;
  }

  Future<T> _request<T>(
    String path,
    T Function(Map<String, dynamic>?) parse, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse('${_apiBase()}$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    http.Response response;
    try {
      response = await switch (method) {
        'POST' => http.post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        ),
        _ => http.get(uri, headers: headers),
      }.timeout(timeout);
    } catch (_) {
      throw ServerConnectionException();
    }
    if (response.statusCode >= 500) throw ServerConnectionException();
    if (response.statusCode == 401 && path == '/api/auth/me') {
      await _storage.delete(key: _tokenKey);
      return parse(null);
    }
    if (response.statusCode == 204) return parse(null);
    Map<String, dynamic>? decoded;
    try {
      decoded = response.body.isEmpty
          ? null
          : jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        (decoded?['error'] as String?) ?? '서버 요청을 처리하지 못했습니다.',
      );
    }
    return parse(decoded);
  }

  Future<AuthUser> _authenticate(
    String path,
    String email,
    String password,
  ) async {
    final result = await _request(
      path,
      (json) => (
        token: json!['token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      ),
      method: 'POST',
      body: {'email': email.trim(), 'password': password},
    );
    await _storage.write(key: _tokenKey, value: result.token);
    return result.user;
  }

  Future<AuthUser> login(String email, String password) =>
      _authenticate('/api/auth/login', email, password);

  Future<AuthUser> register(String email, String password) =>
      _authenticate('/api/auth/register', email, password);

  Future<AuthUser?> restoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) return null;
    try {
      return await _request(
        '/api/auth/me',
        (json) => json == null
            ? null
            : AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        token: token,
      );
    } catch (_) {
      // Preserve the token during a temporary network outage, but show login.
      return null;
    }
  }

  Future<void> logout() async {
    final token = await _storage.read(key: _tokenKey);
    try {
      if (token != null) {
        await _request(
          '/api/auth/logout',
          (_) => null,
          method: 'POST',
          token: token,
        );
      }
    } finally {
      await _storage.delete(key: _tokenKey);
    }
  }

  Future<List<SocialProvider>> enabledSocialProviders() async {
    final ids = await _request(
      '/api/auth/oauth/providers',
      (json) => (json!['providers'] as List).cast<String>(),
      timeout: const Duration(seconds: 4),
    );
    return ids.map((id) => SocialProvider.values.byName(id)).toList();
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

  String socialLoginStartURL(SocialProvider provider) =>
      '${_apiBase()}/api/auth/oauth/${provider.name}/start';

  Future<AuthUser> exchangeSocialCode(String code) async {
    final result = await _request(
      '/api/auth/oauth/exchange',
      (json) => (
        token: json!['token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      ),
      method: 'POST',
      body: {'code': code},
    );
    await _storage.write(key: _tokenKey, value: result.token);
    return result.user;
  }

  Future<List<Map<String, dynamic>>> syncEvents(
    String userId,
    List<Map<String, dynamic>> changes,
  ) async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) throw AuthException('로그인이 필요합니다.');
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
    final token = await _storage.read(key: _tokenKey);
    if (token == null) throw AuthException('로그인이 필요합니다.');
    return _request(
      '/api/settings?user=${Uri.encodeQueryComponent(userId)}',
      (json) => Map<String, dynamic>.from(json!['values'] as Map),
      token: token,
      timeout: const Duration(seconds: 5),
    );
  }

  Future<void> saveSettings(String userId, Map<String, dynamic> values) async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) throw AuthException('로그인이 필요합니다.');
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
    final token = await _storage.read(key: _tokenKey);
    if (token == null) throw AuthException('로그인이 필요합니다.');
    return _request(
      '/api/calendar-import/$provider/connect',
      (json) => json!['url'] as String,
      method: 'POST',
      token: token,
    );
  }

  Future<List<ImportCalendar>> importCalendars(String provider) async {
    final token = await _storage.read(key: _tokenKey);
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
    final token = await _storage.read(key: _tokenKey);
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
}
