import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OfflineCacheStore {
  static const _prefix = 'offline_api_cache_v1::';

  static String buildKey(String path, {Map<String, String>? query}) {
    final entries = (query ?? <String, String>{}).entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (entries.isEmpty) return '$_prefix$path';

    final queryString = entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');

    return '$_prefix$path?$queryString';
  }

  static Future<void> write(
    String path,
    Map<String, dynamic> payload, {
    Map<String, String>? query,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      buildKey(path, query: query),
      jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'payload': payload,
      }),
    );
  }

  static Future<Map<String, dynamic>?> read(
    String path, {
    Map<String, String>? query,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(buildKey(path, query: query));
    if (raw == null || raw.trim().isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;

    final payload = _normalizeMap(decoded['payload']);
    if (payload == null) return null;

    return {
      ...payload,
      '__from_cache': true,
      '__cache_saved_at': decoded['saved_at']?.toString(),
    };
  }

  static Map<String, dynamic>? _normalizeMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, nestedValue) => MapEntry(key.toString(), _normalize(nestedValue)),
      );
    }
    return null;
  }

  static dynamic _normalize(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, nestedValue) => MapEntry(key.toString(), _normalize(nestedValue)),
      );
    }
    if (value is List) {
      return value.map(_normalize).toList();
    }
    return value;
  }
}
