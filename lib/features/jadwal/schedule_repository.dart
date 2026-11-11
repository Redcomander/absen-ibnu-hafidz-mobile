import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/json_codec.dart';
import '../../core/network/offline_cache_store.dart';
import '../../core/network/sync_store.dart';

/// Keep an unfiltered weekly schedule independently of date/search cache keys.
class ScheduleRepository {
  static void Function(
    String account,
    String type,
    String date,
    Map<String, dynamic> payload,
  )?
  onSnapshot;
  static final Map<String, Future<Map<String, dynamic>>> _refreshing = {};
  String _key(String account, String type) => 'schedule::$account::$type';

  Future<Map<String, dynamic>?> cached(String type, String date) async {
    final account = OfflineCacheStore.scope;
    final exact = await OfflineCacheStore.read(
      '/schedules',
      query: {'type': type, 'date': date},
      account: account,
    );
    if (OfflineCacheStore.scope != account) return null;
    if (exact?['data'] is List) return exact;
    final raw = await SyncStore.instance.getMeta(_key(account, type));
    Map? snapshot;
    try {
      if (raw != null) {
        final decoded = await BackgroundJson.decode(raw) as Map;
        if ((decoded['payload'] as Map?)?['data'] is List) snapshot = decoded;
      }
    } catch (_) {
      /* Keep corrupted bytes for recovery and try an older cache. */
    }
    snapshot ??= await _existingSnapshot(account, type);
    if (OfflineCacheStore.scope != account || snapshot == null) return null;
    final payload = Map<String, dynamic>.from(snapshot['payload'] as Map);
    if (snapshot['date'] != date) {
      // Recurring lessons remain useful, but yesterday's attendance is not today's.
      payload['data'] = (payload['data'] as List? ?? [])
          .whereType<Map>()
          .where((row) {
            final assignment = row['assignment'] as Map?;
            final original = (assignment?['teacher'] as Map?)?['id']
                ?.toString();
            final substitute = (row['substitute_teacher'] as Map?)?['id']
                ?.toString();
            final owner = account.split('|').last;
            return substitute != owner || original == owner;
          })
          .map(
            (row) => {
              ...row,
              'attendance_counts': <String, dynamic>{},
              'has_attendance': false,
              'has_attendance_today': false,
              'has_teacher_attendance': false,
              'has_teacher_attendance_today': false,
              'materi_today': '',
            },
          )
          .toList();
    }
    return {
      ...payload,
      '__from_cache': true,
      '__cache_saved_at': snapshot['saved_at'],
      '__schedule_date': snapshot['date'],
    };
  }

  Future<Map?> _existingSnapshot(String account, String type) async {
    // Reuse unfiltered schedules saved by earlier app versions; never delete them.
    final prefs = await SharedPreferences.getInstance();
    final prefix = OfflineCacheStore.buildKey('/schedules', account: account);
    Map? latest;
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith('$prefix?'),
    )) {
      final query = Uri.parse(
        key.substring(key.indexOf('/schedules')),
      ).queryParameters;
      if (query['type'] != type ||
          query.keys.any((k) => !['type', 'date'].contains(k))) {
        continue;
      }
      try {
        final data = await BackgroundJson.decode(prefs.getString(key)!) as Map;
        if ((data['payload'] as Map?)?['data'] is! List) continue;
        if (latest == null ||
            data['saved_at'].toString().compareTo(
                  latest['saved_at'].toString(),
                ) >
                0) {
          latest = {...data, 'date': query['date']};
        }
      } catch (_) {
        /* Leave malformed old cache untouched. */
      }
    }
    return latest;
  }

  Future<Map<String, dynamic>> refresh(
    String type,
    String date,
    String? token,
  ) {
    final key = '${OfflineCacheStore.scope}::$type::$date';
    return _refreshing.putIfAbsent(
      key,
      () => _refresh(type, date, token).whenComplete(() {
        _refreshing.remove(key);
      }),
    );
  }

  Future<void> refreshUpcoming(String type, String date, String? token) async {
    final account = OfflineCacheStore.scope;
    final response = await ApiClient.get(
      '/schedules',
      token: token,
      query: {'type': type, 'date': date},
      useOfflineCache: false,
    ).timeout(const Duration(seconds: 8));
    if (OfflineCacheStore.scope == account && response['data'] is List) {
      onSnapshot?.call(account, type, date, response);
    }
  }

  Future<Map<String, dynamic>> _refresh(
    String type,
    String date,
    String? token,
  ) async {
    final account = OfflineCacheStore.scope;
    final response = await ApiClient.get(
      '/schedules',
      token: token,
      query: {'type': type, 'date': date},
    ).timeout(const Duration(seconds: 8));
    if (OfflineCacheStore.scope != account) {
      throw ApiException(409, 'Akun telah berubah. Muat ulang jadwal.');
    }
    if (response['__from_cache'] != true) {
      if (response['data'] is! List) {
        throw ApiException(502, 'Respons jadwal tidak valid.');
      }
      await SyncStore.instance.setMeta(
        _key(account, type),
        await BackgroundJson.encode({
          'date': date,
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'payload': response,
        }),
      );
    }
    if (response['__from_cache'] != true) {
      onSnapshot?.call(account, type, date, response);
    }
    return response;
  }
}
