import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/secure_http.dart';

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
  int _accountGeneration = 0;
  int get accountGeneration => _accountGeneration;
  Future<void> _queue = Future.value();
  String _cacheKey(String? user) => user == null
      ? 'calendar.account-settings.guest'
      : 'calendar.account-settings.user.${base64Url.encode(utf8.encode(user))}';
  Map<String, dynamic> _decode(String? raw) {
    if (raw == null) return {};
    if (utf8.encode(raw).length > 256 * 1024) {
      throw const FormatException('설정 데이터가 너무 큽니다.');
    }
    return Map<String, dynamic>.from(
      decodeBoundedJson(raw, maxDepth: 32) as Map,
    );
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  bool _validText(dynamic value, int max) =>
      value is String &&
      value.trim().isNotEmpty &&
      value.length <= max &&
      !value.contains('\u0000');

  bool _validCalendars(dynamic value, int max, int idMax) {
    if (value is! List || value.length > max) return false;
    final ids = <String>{};
    for (final item in value) {
      if (item is! Map ||
          !_validText(item['id'], idMax) ||
          !_validText(item['title'], 4096) ||
          !ids.add(item['id'] as String) ||
          item['color'] is! String ||
          !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(item['color'] as String) ||
          (item['category'] != null &&
              (item['category'] is! String ||
                  (item['category'] as String).length > 64)) ||
          (item['nameUnavailable'] != null &&
              item['nameUnavailable'] is! bool)) {
        return false;
      }
    }
    return true;
  }

  bool _validSetting(String key, dynamic value) {
    if (key.startsWith('calendar.display.') ||
        key == 'onboarding.completed.v1') {
      return value is bool;
    }
    if (value is! String || value.length > 256 * 1024) return false;
    try {
      final decoded = decodeBoundedJson(value, maxDepth: 32);
      if (key == 'calendar.personal.lists.v1') {
        return _validCalendars(decoded, 200, 256);
      }
      if (key == 'calendar.import.sources.v1') {
        if (decoded is! Map || decoded.length > 32) return false;
        var count = 0;
        for (final entry in decoded.entries) {
          if (!_validText(entry.key, 64) ||
              !_validCalendars(entry.value, 1000, 500)) {
            return false;
          }
          count += (entry.value as List).length;
        }
        return count <= 1000;
      }
      if (key == 'calendar.import.visibility.v1') {
        return decoded is Map &&
            decoded.length <= 1000 &&
            decoded.entries.every(
              (entry) => _validText(entry.key, 1024) && entry.value is bool,
            );
      }
      if (key == 'calendar.import.excluded-events.v1') {
        return decoded is List &&
            decoded.length <= 10000 &&
            decoded.every((item) => _validText(item, 2048));
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  void _validateRemote(Map<String, dynamic> values) {
    if (values.length > keys.length ||
        utf8.encode(jsonEncode(values)).length > 256 * 1024 ||
        values.entries.any(
          (entry) =>
              !keys.contains(entry.key) ||
              !_validSetting(entry.key, entry.value),
        )) {
      throw const FormatException('서버 설정 데이터가 올바르지 않습니다.');
    }
  }

  Future<void> selectAccount(String? user) {
    final generation = ++_accountGeneration;
    return _serial(() async {
      if (generation != _accountGeneration) return;
      _user = user;
      syncSucceeded.value = null;
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _cacheKey(user);
      if (prefs.getString(cacheKey) == null &&
          user != null &&
          user != 'guest') {
        final previous = prefs.getString('calendar.account-settings.$user');
        if (previous != null) await prefs.setString(cacheKey, previous);
        final pending = prefs.getString(
          'calendar.account-settings.$user.pending',
        );
        if (pending != null) {
          await prefs.setString('$cacheKey.pending', pending);
        }
      }
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
    });
  }

  Future<Object?> get(String key) async {
    final generation = _accountGeneration;
    await _queue;
    if (generation != _accountGeneration) throw AuthException('계정이 변경되었습니다.');
    final user = _user;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _accountGeneration) throw AuthException('계정이 변경되었습니다.');
    final raw = prefs.getString(_cacheKey(user));
    final value = raw == null && user == null
        ? prefs.get(key)
        : _decode(raw)[key];
    return value != null && _validSetting(key, value) ? value : null;
  }

  Future<void> set(String key, Object value) {
    final generation = _accountGeneration;
    if ((!keys.contains(key) && key != 'onboarding.completed.v1') ||
        !_validSetting(key, value)) {
      return Future.error(const FormatException('설정 데이터가 올바르지 않습니다.'));
    }
    var changed = false;
    final operation = _serial(() async {
      if (generation != _accountGeneration) throw AuthException('계정이 변경되었습니다.');
      final user = _user;
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _cacheKey(user);
      final values = _decode(prefs.getString(cacheKey));
      if (values[key] == value) return;
      changed = true;
      values[key] = value;
      if (user != null && keys.contains(key)) {
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
    return operation.then((_) async {
      if (generation == _accountGeneration &&
          (changed || syncSucceeded.value == false)) {
        await sync();
      }
    });
  }

  /// Failed requests retain the queue. Retry at startup, on edits, and resume.
  Future<bool> sync() {
    final generation = _accountGeneration;
    return _serial(() async {
      if (generation != _accountGeneration) return false;
      final user = _user;
      if (user == null) return true;
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = _cacheKey(user);
        final remote = await _loadRemote(user);
        if (generation != _accountGeneration) return false;
        _validateRemote(remote);
        final local = _decode(prefs.getString(cacheKey));
        final pending = _decode(prefs.getString('$cacheKey.pending'));
        // Migrate existing settings only into missing server keys.
        final upload = <String, dynamic>{
          for (final entry in local.entries)
            if (keys.contains(entry.key) &&
                _validSetting(entry.key, entry.value) &&
                !remote.containsKey(entry.key))
              entry.key: entry.value,
          for (final entry in pending.entries)
            if (keys.contains(entry.key) &&
                _validSetting(entry.key, entry.value))
              entry.key: entry.value,
        };
        if (upload.isNotEmpty) {
          await _saveRemote(user, upload);
          if (generation != _accountGeneration) return false;
        }
        if (!await prefs.setString(
          cacheKey,
          jsonEncode({
            for (final entry in local.entries)
              if (!keys.contains(entry.key)) entry.key: entry.value,
            ...remote,
            ...upload,
          }),
        )) {
          return false;
        }
        await prefs.remove('$cacheKey.pending');
        if (generation == _accountGeneration) syncSucceeded.value = true;
        return true;
      } catch (_) {
        if (generation == _accountGeneration) syncSucceeded.value = false;
        return false;
      }
    });
  }
}
