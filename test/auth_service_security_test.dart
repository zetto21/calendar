import 'dart:async';
import 'dart:convert';

import 'package:calendar_app_flutter/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _tokenA = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _tokenB = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

Map<String, dynamic> _user(String id) => {
  'id': id,
  'email': '$id@example.com',
  'name': id,
  'createdAt': '2026-10-04T00:00:00Z',
};
http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response _login(String id, String token) =>
    _json({'token': token, 'user': _user(id)});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'invalid token and malformed auth data cannot create a session',
    () async {
      for (final token in ['', 'Bearer token', 'token\nheader', 'a' * 44]) {
        final service = AuthService.forTesting(
          clientFactory: () => MockClient((_) async => _login('a', token)),
        );
        await expectLater(
          service.login('a@example.com', 'Calendar1!'),
          throwsA(isA<AuthException>()),
        );
        expect(await service.restoreSession(), isNull);
      }
      final service = AuthService.forTesting(
        clientFactory: () => MockClient(
          (_) async => _json({
            'token': _tokenA,
            'user': {'id': null},
          }),
        ),
      );
      await expectLater(
        service.login('a@example.com', 'Calendar1!'),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test(
    'the most recent login wins even if an older response arrives later',
    () async {
      final firstResponse = Completer<http.Response>();
      final secondResponse = Completer<http.Response>();
      var logins = 0;
      final service = AuthService.forTesting(
        clientFactory: () => MockClient((request) {
          if (request.url.path.endsWith('/login')) {
            return ++logins == 1 ? firstResponse.future : secondResponse.future;
          }
          expect(request.headers['Authorization'], 'Bearer $_tokenB');
          return Future.value(_json({'user': _user('b')}));
        }),
      );
      final first = service.login('a@example.com', 'Calendar1!');
      final rejected = expectLater(first, throwsA(isA<AuthException>()));
      await Future<void>.delayed(Duration.zero);
      final second = service.login('b@example.com', 'Calendar1!');
      await Future<void>.delayed(Duration.zero);
      secondResponse.complete(_login('b', _tokenB));
      expect((await second).id, 'b');
      firstResponse.complete(_login('a', _tokenA));
      await rejected;
      expect((await service.restoreSession())?.id, 'b');
    },
  );

  test(
    'logout invalidates a pending login before it can restore credentials',
    () async {
      final response = Completer<http.Response>();
      final service = AuthService.forTesting(
        clientFactory: () => MockClient((_) => response.future),
      );
      final login = service.login('a@example.com', 'Calendar1!');
      final rejected = expectLater(login, throwsA(isA<AuthException>()));
      await service.logout();
      response.complete(_login('a', _tokenA));
      await rejected;
      expect(await service.restoreSession(), isNull);
    },
  );

  test('a delayed logout never clears a newer login', () async {
    final logoutResponse = Completer<http.Response>();
    var logins = 0;
    final service = AuthService.forTesting(
      clientFactory: () => MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return ++logins == 1 ? _login('a', _tokenA) : _login('b', _tokenB);
        }
        if (request.url.path.endsWith('/logout')) return logoutResponse.future;
        return _json({'user': _user('b')});
      }),
    );
    await service.login('a@example.com', 'Calendar1!');
    final logout = service.logout();
    await Future<void>.delayed(Duration.zero);
    await service.login('b@example.com', 'Calendar1!');
    logoutResponse.complete(http.Response('', 204));
    await logout;
    expect((await service.restoreSession())?.id, 'b');
  });

  test(
    'stale authenticated response is rejected after an account change',
    () async {
      final settings = Completer<http.Response>();
      var logins = 0;
      var settingsRequests = 0;
      final service = AuthService.forTesting(
        clientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return ++logins == 1 ? _login('a', _tokenA) : _login('b', _tokenB);
          }
          settingsRequests++;
          return settings.future;
        }),
      );
      await service.login('a@example.com', 'Calendar1!');
      final old = service.loadSettings('a');
      final rejected = expectLater(old, throwsA(isA<AuthException>()));
      await service.login('b@example.com', 'Calendar1!');
      settings.complete(
        _json({
          'values': {'old-account-secret': true},
        }),
      );
      await rejected;
      await expectLater(
        service.loadSettings('a'),
        throwsA(isA<AuthException>()),
      );
      expect(settingsRequests, 1);
    },
  );

  test(
    'corrupted and expired Keychain sessions are deleted without reuse',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      const channel = MethodChannel('calendar_app/session');
      var reads = 0;
      var deletes = 0;
      String? saved;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'read') {
              reads++;
              return saved;
            }
            if (call.method == 'delete') deletes++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      for (final value in [
        jsonEncode({'token': 'not-a-token', 'user': _user('a')}),
        jsonEncode({'token': _tokenA, 'user': _user('a')}),
      ]) {
        saved = value;
        final service = AuthService.forTesting(
          clientFactory: () =>
              MockClient((_) async => _json({'error': 'expired'}, 401)),
        );
        expect(await service.restoreSession(), isNull);
        expect(await service.restoreSession(), isNull);
      }
      expect(reads, 2);
      expect(deletes, 2);
    },
  );

  test(
    'logout still revokes the server session when Keychain deletion fails',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      const channel = MethodChannel('calendar_app/session');
      var revocations = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'delete') {
              throw PlatformException(code: 'keychain-unavailable');
            }
            if (call.method == 'read') fail('A logged-out session was reread');
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = AuthService.forTesting(
        clientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/login')) return _login('a', _tokenA);
          expect(request.url.path, '/api/auth/logout');
          expect(request.headers['Authorization'], 'Bearer $_tokenA');
          revocations++;
          return http.Response('', 204);
        }),
      );
      await service.login('a@example.com', 'Calendar1!');
      await expectLater(service.logout(), throwsA(isA<PlatformException>()));
      expect(revocations, 1);
      expect(await service.restoreSession(), isNull);
    },
  );

  test(
    'client PKCE is sent with code and only supported imports are requested',
    () async {
      final service = AuthService.forTesting(
        clientFactory: () => MockClient((request) async {
          expect(jsonDecode(request.body), {
            'code': _tokenA,
            'clientVerifier': _tokenB,
          });
          return _login('a', _tokenA);
        }),
      );
      final start = Uri.parse(
        service.socialLoginStartURL(
          SocialProvider.google,
          codeChallenge: _tokenA,
        ),
      );
      expect(start.queryParameters['client_challenge'], _tokenA);
      await service.exchangeSocialCode(_tokenA, clientVerifier: _tokenB);
      await expectLater(
        service.calendarImportStart('../auth/logout'),
        throwsA(isA<AuthException>()),
      );
    },
  );
}
