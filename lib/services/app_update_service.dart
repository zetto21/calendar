import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';

import '../logic/security_urls.dart';
import 'auth_service.dart';
import 'secure_http.dart';

class AppUpdateInfo {
  final String version;
  final String? updateUrl;

  const AppUpdateInfo({required this.version, this.updateUrl});
}

class AppUpdateService {
  AppUpdateService._();

  static Future<AppUpdateInfo?> check() async {
    try {
      final response = await secureHttpRequest(
        Uri.parse('${AuthService.apiBase}/api/app-version'),
        timeout: const Duration(seconds: 5),
        maxResponseBytes: 64 << 10,
      );
      if (response.statusCode != 200) return null;
      final body = decodeBoundedJson(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) return null;
      final latestVersion = body['version'] as String?;
      if (latestVersion == null || latestVersion.trim().isEmpty) return null;

      final currentVersion = (await PackageInfo.fromPlatform()).version;
      if (!_versionsDiffer(latestVersion, currentVersion)) return null;
      final rawUpdateUrl = (body['updateUrl'] as String?)?.trim();
      final updateUrl = secureHttpsUri(rawUpdateUrl)?.toString();
      return AppUpdateInfo(version: latestVersion, updateUrl: updateUrl);
    } catch (_) {
      // A failed update check must never block the calendar from opening.
      return null;
    }
  }

  static bool _versionsDiffer(String latest, String current) =>
      latest.trim() != current.trim();
}
