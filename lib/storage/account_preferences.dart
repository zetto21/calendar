import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';

/// Local cache and durable upload queue, isolated by signed-in account.
class AccountPreferences {
  AccountPreferences({
    Future<Map<String, dynamic>> Function(String)? loadRemote,
    Future<void> Function(String, Map<String, dynamic>)? saveRemote,
  }) : _loadRemote = loadRemote ?? AuthService.instance.loadSettings,
       _saveRemote = saveRemote ?? AuthService.instance.saveSettings;

  final Future<Map<String, dynamic>> Function(String) _loadRemote;
  final Future<void> Function(String, Map<String, dynamic>) _saveRemote;
  static final instance = AccountPreferences();
  static const keys = [
    'calendar.personal.lists.v1',
    'calendar.display.holidays',
    'calendar.display.lunar',
    'calendar.display.solarTerms',
    'calendar.display.anniversaries',
    'calendar.import.sources.v1',
    'calendar.import.visibility.v1',
    'calendar.import.excluded-events.v1',
  ];
  final syncSucceeded = ValueNotifier<bool?>(null);
  String? _user;
  Future<void> _queue = Future.value();
  String _cacheKey(String? user) =>
      'calendar.account-settings.${user ?? "guest"}';
  Map<String, dynamic> _decode(String? raw) =>
      raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);

  Future<void> selectAccount(String? user) async {
    await _queue;
    _user = user;
    syncSucceeded.value = null;
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = _cacheKey(user);
    // Claim the old device-only settings once; never copy another account's cache.
    if (prefs.getString(cacheKey) == null &&
        prefs.getString('calendar.settings.legacy-owner') == null) {
      final legacy = <String, dynamic>{
        for (final key in keys)
          if (prefs.containsKey(key)) key: prefs.get(key),
      };
      await prefs.setString(cacheKey, jsonEncode(legacy));
      if (user != null) {
        await prefs.setString('calendar.settings.legacy-owner', user);
      }
    }
  }

  Future<Object?> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(_user));
    if (raw == null && _user == null) return prefs.get(key);
    return _decode(raw)[key];
  }

  Future<void> set(String key, Object value) {
    final user = _user;
    var changed = false;
    final operation = _queue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _cacheKey(user);
      final values = _decode(prefs.getString(cacheKey));
      if (values[key] == value) return;
      changed = true;
      values[key] = value;
      if (user != null) {
        final pending = _decode(prefs.getString('$cacheKey.pending'))
          ..[key] = value;
        if (!await prefs.setString('$cacheKey.pending', jsonEncode(pending))) {
          throw StateError('설정 변경을 저장하지 못했습니다.');
        }
      }
      if (!await prefs.setString(cacheKey, jsonEncode(values))) {
        throw StateError('설정을 저장하지 못했습니다.');
      }
    });
    _queue = operation.catchError((Object _) {});
    return operation.then((_) async {
      if (changed || syncSucceeded.value == false) await sync();
    });
  }

  /// Failed requests retain the queue. Retry at startup, on edits, and resume.
  Future<bool> sync() {
    final user = _user;
    if (user == null) return Future.value(true);
    final operation = _queue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = _cacheKey(user);
        final remote = await _loadRemote(user);
        final local = _decode(prefs.getString(cacheKey));
        final pending = _decode(prefs.getString('$cacheKey.pending'));
        // Migrate existing settings only into missing server keys.
        final upload = <String, dynamic>{
          for (final entry in local.entries)
            if (!remote.containsKey(entry.key)) entry.key: entry.value,
          ...pending,
        };
        if (upload.isNotEmpty) {
          await _saveRemote(user, upload);
        }
        if (!await prefs.setString(
          cacheKey,
          jsonEncode({...remote, ...upload}),
        )) {
          return false;
        }
        await prefs.remove('$cacheKey.pending');
        return true;
      } catch (_) {
        return false;
      }
    });
    _queue = operation.then((success) {
      syncSucceeded.value = success;
    });
    return operation;
  }
}
