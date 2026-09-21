import 'dart:convert';

import 'package:calendar_app_flutter/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('calendar_app/session');
  const user = {'id': 'account-1', 'email': 'test@example.com'};
  String? stored;
  setUp(() {
    stored = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          expect(args['account'], AuthService.apiBase);
          switch (call.method) {
            case 'read':
              return stored;
            case 'write':
              stored = args['value'] as String;
              return null;
            case 'delete':
              stored = null;
              return null;
          }
          throw StateError('Unexpected method');
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final social in [false, true]) {
    test(
      'restores ${social ? 'social' : 'email'} login in a fresh process',
      () async {
        await http.runWithClient(
          () async {
            final first = AuthService.forTesting();
            if (social) {
              await first.exchangeSocialCode('code');
            } else {
              await first.login('test@example.com', 'password');
            }
            expect(stored, isNotNull);
            final restarted = AuthService.forTesting();
            expect((await restarted.restoreSession())?.id, 'account-1');
            await restarted.logout();
            expect(stored, isNull);
            expect(await AuthService.forTesting().restoreSession(), isNull);
          },
          () => MockClient((request) async {
            if (request.url.path == '/api/auth/me') {
              expect(request.headers['Authorization'], 'Bearer saved-token');
              return http.Response(jsonEncode({'user': user}), 200);
            }
            if (request.url.path.endsWith('/logout'))
              return http.Response('', 204);
            return http.Response(
              jsonEncode({'token': 'saved-token', 'user': user}),
              200,
            );
          }),
        );
      },
    );
  }

  test(
    'outage retains saved session; unauthorized response removes it',
    () async {
      stored = jsonEncode({'token': 'saved-token', 'user': user});
      await http.runWithClient(() async {
        expect(
          (await AuthService.forTesting().restoreSession())?.id,
          'account-1',
        );
        expect(stored, isNotNull);
      }, () => MockClient((_) async => http.Response('{}', 503)));
      await http.runWithClient(() async {
        expect(await AuthService.forTesting().restoreSession(), isNull);
        expect(stored, isNull);
      }, () => MockClient((_) async => http.Response('{}', 401)));
    },
  );

  test('offline logout also removes the saved session', () async {
    stored = jsonEncode({'token': 'saved-token', 'user': user});
    await http.runWithClient(() async {
      final auth = AuthService.forTesting();
      await auth.restoreSession();
      await expectLater(
        auth.logout(),
        throwsA(isA<ServerConnectionException>()),
      );
      expect(stored, isNull);
      expect(await AuthService.forTesting().restoreSession(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 503)));
  });
}
