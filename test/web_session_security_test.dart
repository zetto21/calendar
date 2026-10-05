@TestOn('browser')
library;

import 'dart:convert';

import 'package:calendar_app_flutter/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web/web.dart' as web;

const _token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _user = {
  'id': 'a',
  'email': 'a@example.com',
  'name': 'A',
  'createdAt': '',
};

http.Response _response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = 'calendar.session.${AuthService.apiBase}';
  setUp(() {
    web.window.sessionStorage.removeItem(key);
    web.window.localStorage.removeItem(key);
    web.window.localStorage.removeItem('flutter.$key');
  });
  tearDown(() {
    web.window.sessionStorage.removeItem(key);
    web.window.localStorage.removeItem(key);
    web.window.localStorage.removeItem('flutter.$key');
  });

  test(
    'legacy persistent bearer tokens are removed without restoring them',
    () async {
      final saved = jsonEncode({'token': _token, 'user': _user});
      web.window.localStorage.setItem('flutter.$key', saved);
      web.window.localStorage.setItem(key, saved);
      var calls = 0;
      final service = AuthService.forTesting(
        clientFactory: () => MockClient((_) async {
          calls++;
          return _response({'user': _user});
        }),
      );
      expect(await service.restoreSession(), isNull);
      expect(calls, 0);
      expect(web.window.localStorage.getItem('flutter.$key'), isNull);
      expect(web.window.localStorage.getItem(key), isNull);
    },
  );

  test('login persists only in tab storage and supports a reload', () async {
    http.Client client() => MockClient(
      (request) async => _response(
        request.url.path.endsWith('/login')
            ? {'token': _token, 'user': _user}
            : {'user': _user},
      ),
    );
    final service = AuthService.forTesting(clientFactory: client);
    await service.login('a@example.com', 'Calendar1!');
    expect(web.window.sessionStorage.getItem(key), contains(_token));
    expect(web.window.localStorage.getItem(key), isNull);
    expect(web.window.localStorage.getItem('flutter.$key'), isNull);
    expect(
      (await AuthService.forTesting(
        clientFactory: client,
      ).restoreSession())?.id,
      'a',
    );
    web.window.sessionStorage.removeItem(key);
    expect(
      await AuthService.forTesting(clientFactory: client).restoreSession(),
      isNull,
    );
  });

  test(
    'logout removes tab credentials even when server revocation fails',
    () async {
      final service = AuthService.forTesting(
        clientFactory: () => MockClient(
          (request) async => request.url.path.endsWith('/login')
              ? _response({'token': _token, 'user': _user})
              : _response({'error': 'offline'}, 503),
        ),
      );
      await service.login('a@example.com', 'Calendar1!');
      await expectLater(
        service.logout(),
        throwsA(isA<ServerConnectionException>()),
      );
      expect(web.window.sessionStorage.getItem(key), isNull);
      expect(await service.restoreSession(), isNull);
    },
  );
}
