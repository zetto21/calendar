import 'dart:convert';

import 'package:calendar_app_flutter/services/auth_service.dart';
import 'package:calendar_app_flutter/storage/account_preferences.dart';
import 'package:calendar_app_flutter/storage/imported_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'whole Talk calendar persists when empty and includes future events',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AccountPreferences.instance.selectAccount(null);
      final imports = ImportedEvents();
      const calendars = [
        ImportCalendar(
          id: 'talk',
          title: '가족',
          color: '#E8A100',
          category: 'subscription',
        ),
      ];
      var empty = true;
      await http.runWithClient(
        () async {
          await AuthService.instance.login('test@example.com', 'password');
          await imports.saveEventSelection('kakao', ['kakao|talk|one'], []);
          await imports.refresh(
            'kakao',
            calendars,
            DateTime(2026, 9),
            DateTime(2026, 10),
          );
          expect(imports.sources['kakao']!.single.title, '가족');
          expect(imports.events, isEmpty);
          final restarted = ImportedEvents();
          await restarted.load();
          expect(restarted.sources['kakao']!.single.id, 'talk');
          expect(restarted.sources['kakao']!.single.category, 'subscription');
          empty = false;
          await restarted.refresh(
            'kakao',
            restarted.sources['kakao']!,
            DateTime(2026, 10),
            DateTime(2026, 11),
          );
          expect(restarted.events['2026-10-05']!.single.title, '가족 모임');
          await restarted.setVisible('kakao', 'talk', false);
          expect(restarted.events['2026-10-05'], isEmpty);
          await AuthService.instance.logout();
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return http.Response(
              jsonEncode({
                'token': 'test-token',
                'user': {'id': 'test', 'email': 'test@example.com'},
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/logout'))
            return http.Response('', 204);
          return http.Response(
            jsonEncode({
              'items': empty
                  ? []
                  : [
                      {
                        'id': 'one',
                        'date': '2026-10-05',
                        'title': '가족 모임',
                        'color': '#E8A100',
                        'duration': 60,
                      },
                    ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    },
  );
}
