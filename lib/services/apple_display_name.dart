import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Apple supplies a name only on initial authorization. Save it before the
/// server exchange so a failed exchange can be retried without losing it.
class AppleDisplayName {
  static Future<String> resolve({
    required String? userIdentifier,
    required String? familyName,
    required String? givenName,
  }) async {
    final family = familyName?.trim() ?? '';
    final given = givenName?.trim() ?? '';
    final name = RegExp(r'[가-힣]').hasMatch(family + given)
        ? '$family$given'
        : [given, family].where((part) => part.isNotEmpty).join(' ');
    if (userIdentifier == null || userIdentifier.isEmpty) return name;
    final key =
        'apple_display_name_${sha256.convert(utf8.encode(userIdentifier))}';
    try {
      final preferences = await SharedPreferences.getInstance();
      if (name.isNotEmpty) {
        await preferences.setString(key, name);
        return name;
      }
      return preferences.getString(key) ?? '';
    } catch (_) {
      // A cache failure must not prevent Apple authentication.
      return name;
    }
  }
}
