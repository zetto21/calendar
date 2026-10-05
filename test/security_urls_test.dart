import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_app_flutter/logic/security_urls.dart';

void main() {
  final code = List.filled(43, 'a').join();
  group('authentication callback destination and payload', () {
    test('accepts only the configured native route and one-time code', () {
      expect(parseSocialAuthCallback('calendar://auth?code=$code').code, code);
      expect(
        parseSocialAuthCallback('calendar://auth?error=canceled').error,
        'canceled',
      );
    });

    test('rejects another app route, authority, or ambiguous credentials', () {
      for (final raw in [
        'other://auth?code=$code',
        'calendar://evil?code=$code',
        'calendar://auth/other?code=$code',
        'calendar://auth/?code=$code',
        'calendar://user@auth?code=$code',
        'calendar://auth:80?code=$code',
        'calendar://auth?code=$code#extra',
        'calendar://auth?code=$code#',
        'calendar://auth?code=$code&code=$code',
        'calendar://auth?code=$code&error=canceled',
        'calendar://auth?token=$code',
        'calendar://auth?code=short',
        'calendar://auth?code=$code%0A',
        'calendar://auth?code=$code%E2%80%A8',
        'calendar://auth?code=${List.filled(43, '+').join()}',
        'calendar://auth?error=',
        'calendar://auth?error=bad%0Atext',
        'calendar://auth',
        '\ncalendar://auth?code=$code',
      ]) {
        expect(
          () => parseSocialAuthCallback(raw),
          throwsFormatException,
          reason: raw.split('?').first,
        );
      }
    });

    test('web accepts only its exact origin and callback path', () {
      final origin = Uri.parse('https://calendar.example.com');
      expect(
        parseSocialAuthCallback(
          'https://calendar.example.com/auth.html?code=$code',
          webOrigin: origin,
        ).code,
        code,
      );
      for (final raw in [
        'https://evil.example/auth.html?code=$code',
        'http://calendar.example.com/auth.html?code=$code',
        'https://calendar.example.com:444/auth.html?code=$code',
        'https://calendar.example.com/other.html?code=$code',
        'https://user@calendar.example.com/auth.html?code=$code',
        'calendar://auth?code=$code',
      ]) {
        expect(
          () => parseSocialAuthCallback(raw, webOrigin: origin),
          throwsFormatException,
        );
      }
    });

    test('calendar import must match the provider that was started', () {
      expect(
        parseCalendarImportCallback(
          'calendar://auth?calendar_import=google&result=success',
          provider: 'google',
        ).success,
        isTrue,
      );
      expect(
        parseCalendarImportCallback(
          'calendar://auth?calendar_import=google&error=canceled',
          provider: 'google',
        ).error,
        'canceled',
      );
      for (final raw in [
        'calendar://auth?calendar_import=notion&result=success',
        'calendar://auth?calendar_import=google&result=success&error=canceled',
        'calendar://auth?calendar_import=google&result=failure',
        'calendar://auth?calendar_import=google&result=success&result=success',
        'calendar://auth?result=success',
      ]) {
        expect(
          () => parseCalendarImportCallback(raw, provider: 'google'),
          throwsFormatException,
        );
      }
    });
  });

  group('external browser links', () {
    test('updates require an absolute HTTPS URL without credentials', () {
      expect(secureHttpsUri('https://apps.apple.com/app/example'), isNotNull);
      for (final raw in [
        null,
        '',
        'javascript:alert(1)',
        'data:text/html,hello',
        'file:///tmp/example',
        'intent://example',
        'http://example.com',
        '//example.com',
        'https:///example',
        'https://user:password@example.com',
        'https://example.com/\nother',
      ]) {
        expect(secureHttpsUri(raw), isNull);
      }
    });

    test('insecure auth URL exceptions are explicit and loopback-only', () {
      expect(secureBrowserAuthUri('http://localhost:3001/start'), isNull);
      expect(
        secureBrowserAuthUri(
          'http://localhost:3001/start',
          allowInsecureLoopback: true,
        ),
        isNotNull,
      );
      expect(secureBrowserAuthUri('http://10.0.2.2:3001/start'), isNull);
      expect(
        secureBrowserAuthUri(
          'http://10.0.2.2:3001/start',
          allowInsecureLoopback: true,
        ),
        isNotNull,
      );
      for (final raw in [
        'http://api.example.com/start',
        'http://localhost.evil.example/start',
        'http://user:password@localhost/start',
        'javascript:alert(1)',
      ]) {
        expect(secureBrowserAuthUri(raw, allowInsecureLoopback: true), isNull);
      }
    });
  });
}
