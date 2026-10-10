import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calendar_app_flutter/services/apple_display_name.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'first authorization name survives a retry without Apple name',
    () async {
      expect(
        await AppleDisplayName.resolve(
          userIdentifier: 'apple-a',
          familyName: ' 홍 ',
          givenName: ' 길동 ',
        ),
        '홍길동',
      );
      expect(
        await AppleDisplayName.resolve(
          userIdentifier: 'apple-a',
          familyName: null,
          givenName: null,
        ),
        '홍길동',
      );
      expect(
        await AppleDisplayName.resolve(
          userIdentifier: 'apple-b',
          familyName: null,
          givenName: null,
        ),
        '',
      );
    },
  );

  test('Latin names preserve given name then family name', () async {
    expect(
      await AppleDisplayName.resolve(
        userIdentifier: 'apple-a',
        familyName: ' Smith ',
        givenName: ' John ',
      ),
      'John Smith',
    );
  });
}
