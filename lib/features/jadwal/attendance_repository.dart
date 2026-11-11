import 'dart:developer';

import '../../core/network/api_client.dart';
import '../../core/network/json_codec.dart';
import '../../core/network/offline_cache_store.dart';
import '../../core/network/sync_store.dart';

class AttendanceRepository {
  static final Map<String, Future<Map<String, dynamic>>> _refreshing = {};
  Map<String, String> _query(String type, String id, String date) => {
    'type': type,
    'jadwal_id': id,
    'date': date,
  };

  Future<Map<String, dynamic>?> cached(
    String type,
    String id,
    String date,
  ) async {
    final account = OfflineCacheStore.scope;
    final data = await OfflineCacheStore.read(
      '/attendance',
      query: _query(type, id, date),
      account: account,
    );
    if (data?['students'] is! List) return null;
    return _pending(data!, account, type, id, date);
  }

  Future<Map<String, dynamic>> refresh(
    String type,
    String id,
    String date,
    String? token,
  ) {
    final account = OfflineCacheStore.scope;
    final key = '$account::$type::$id::$date';
    return _refreshing.putIfAbsent(
      key,
      () => _refresh(account, type, id, date, token).whenComplete(() {
        _refreshing.remove(key);
      }),
    );
  }

  Future<Map<String, dynamic>> _refresh(
    String account,
    String type,
    String id,
    String date,
    String? token,
  ) async {
    final task = TimelineTask()
      ..start('attendance.refresh', arguments: {'type': type});
    try {
      final query = _query(type, id, date);
      final data = await ApiClient.get(
        '/attendance',
        token: token,
        query: query,
        useOfflineCache: false,
      ).timeout(const Duration(seconds: 8));
      if (OfflineCacheStore.scope != account) {
        throw ApiException(409, 'Akun telah berubah. Buka kembali formulir.');
      }
      if (data['students'] is! List) {
        throw ApiException(
          502,
          'Data santri tidak valid. Data tersimpan dipertahankan.',
        );
      }
      await OfflineCacheStore.write(
        '/attendance',
        data,
        query: query,
        account: account,
      );
      return await _pending(data, account, type, id, date);
    } finally {
      task.finish();
    }
  }

  Future<Map<String, dynamic>> _pending(
    Map<String, dynamic> data,
    String account,
    String type,
    String id,
    String date,
  ) async {
    final rows = await SyncStore.instance.entries(account, path: '/attendance');
    if (OfflineCacheStore.scope != account) {
      throw ApiException(409, 'Akun telah berubah. Buka kembali formulir.');
    }
    final result = {...data};
    final students = (data['students'] as List)
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    final byStudent = {
      for (final student in students) student['student_id'].toString(): student,
    };
    for (final row in rows.where((r) => r['path'] == '/attendance')) {
      try {
        final body = await BackgroundJson.decode(row['body'] as String) as Map;
        if (body['type'] != type ||
            body['jadwal_id'].toString() != id ||
            body['date'] != date) {
          continue;
        }
        final records = (body['records'] as List).whereType<Map>();
        for (final record in records) {
          final student = byStudent[record['student_id'].toString()];
          if (student != null) {
            student['status'] = record['status'];
            student['catatan'] = record['catatan'] ?? '';
          }
        }
        result['materi'] = body['materi'] ?? result['materi'];
        result['rangkuman'] = body['rangkuman'] ?? result['rangkuman'];
        result['__has_pending_changes'] = true;
      } catch (_) {
        /* Invalid queue rows remain available in sync settings. */
      }
    }
    return {...result, 'students': students};
  }
}
