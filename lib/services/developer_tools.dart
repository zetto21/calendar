import 'package:shared_preferences/shared_preferences.dart';

class DeveloperToolsPreferences {
  static const _key = 'developer.tools.enabled.v1';
  static Future<bool> load() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;
  static Future<void> setEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_key, value);
}
