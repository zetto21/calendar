import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'auth_service.dart';

class AppUpdateInfo {
  final String version;
  final String? updateUrl;

  const AppUpdateInfo({required this.version, this.updateUrl});
}

class AppUpdateService {
  AppUpdateService._();

  static Future<AppUpdateInfo?> check() async {
    try {
      final response = await http
          .get(Uri.parse('${AuthService.apiBase}/api/app-version'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      final latestVersion = body['version'] as String?;
      if (latestVersion == null || latestVersion.trim().isEmpty) return null;

      final currentVersion = (await PackageInfo.fromPlatform()).version;
      if (!_versionsDiffer(latestVersion, currentVersion)) return null;
      final rawUpdateUrl = (body['updateUrl'] as String?)?.trim();
      final updateUrl = rawUpdateUrl?.isEmpty == true ? null : rawUpdateUrl;
      return AppUpdateInfo(version: latestVersion, updateUrl: updateUrl);
    } catch (_) {
      // A failed update check must never block the calendar from opening.
      return null;
    }
  }

  static bool _versionsDiffer(String latest, String current) =>
      latest.trim() != current.trim();
}
