import 'dart:convert';

import 'package:calendar_app_flutter/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthService.instance;
  final user = {'id': 'test-user', 'email': 'test@example.com'};

  setUp(() async {
    await http.runWithClient(
      auth.logout,
      () => MockClient((_) async => http.Response('', 204)),
    );
  });

  test(
    'OAuth session works without native storage and is cleared on logout',
    () async {
      var meRequests = 0;
      await http.runWithClient(
        () async {
          expect(await auth.restoreSession(), isNull);
          expect((await auth.exchangeSocialCode('test-code')).id, 'test-user');
          expect((await auth.restoreSession())?.id, 'test-user');
          await auth.logout();
          expect(await auth.restoreSession(), isNull);
          expect(meRequests, 1);
        },
        () => MockClient((request) async {
          switch (request.url.path) {
            case '/api/auth/oauth/exchange':
              return http.Response(
                jsonEncode({'token': 'test-session', 'user': user}),
                200,
              );
            case '/api/auth/me':
              meRequests++;
              expect(request.headers['Authorization'], 'Bearer test-session');
              return http.Response(jsonEncode({'user': user}), 200);
            case '/api/auth/logout':
              expect(request.headers['Authorization'], 'Bearer test-session');
              return http.Response('', 204);
            default:
              fail('Unexpected request');
          }
        }),
      );
    },
  );

  test('Rejected sessions are cleared from memory', () async {
    var meRequests = 0;
    await http.runWithClient(
      () async {
        await auth.login('test@example.com', 'test-password');
        expect(await auth.restoreSession(), isNull);
        expect(await auth.restoreSession(), isNull);
        expect(meRequests, 1);
      },
      () => MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({'token': 'test-session', 'user': user}),
            200,
          );
        }
        meRequests++;
        return http.Response('{}', 401);
      }),
    );
  });

  test(
    'Logout clears the session even when the server is unavailable',
    () async {
      await http.runWithClient(
        () async {
          await auth.exchangeSocialCode('test-code');
          await expectLater(
            auth.logout(),
            throwsA(isA<ServerConnectionException>()),
          );
          expect(await auth.restoreSession(), isNull);
        },
        () => MockClient(
          (request) async => request.url.path.endsWith('/exchange')
              ? http.Response(
                  jsonEncode({'token': 'test-session', 'user': user}),
                  200,
                )
              : http.Response('{}', 503),
        ),
      );
    },
  );
}
