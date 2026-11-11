import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/network/api_client.dart';
import 'package:ibnu_hafidz_flutter/core/network/offline_cache_store.dart';
import 'package:ibnu_hafidz_flutter/core/network/sync_store.dart';
import 'package:ibnu_hafidz_flutter/features/jadwal/attendance_repository.dart';
import 'package:ibnu_hafidz_flutter/features/jadwal/offline_preparation.dart';
import 'package:ibnu_hafidz_flutter/features/jadwal/schedule_repository.dart';

void main() {
  final attendance = AttendanceRepository();
  const query = {'type': 'formal', 'jadwal_id': '1', 'date': '2026-11-10'};
  final original = {
    'students': [
      {
        'student_id': 5,
        'student_name': 'Santri',
        'status': 'hadir',
        'catatan': ''
      }
    ],
    'materi': 'Lama'
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OfflineCacheStore.scope = SyncStore.account(1);
    final db = await SyncStore.instance.database;
    await db.delete('queue');
    await db.delete('meta');
    ApiClient.refreshAuthToken = null;
  });

  test(
      'preparation prioritizes own lessons, downloads only today and honors a form budget',
      () async {
    final requested = <String>[];
    await http.runWithClient(() async {
      final result = await OfflinePreparation().prepare(
          date: '2026-11-10',
          types: ['formal'],
          token: 'test',
          canContinue: () async => true,
          maxForms: 1);
      expect(result.forms, 1);
      expect(result.schedules, 1);
      expect(requested, ['1']);
      expect(
          (await attendance.cached('formal', '1', '2026-11-10'))!['students'],
          hasLength(1));
    },
        () => MockClient((request) async {
              if (request.url.path.endsWith('/schedules')) {
                return http.Response(
                    jsonEncode([
                      {
                        'id': 9,
                        'day': 'Selasa',
                        'start_time': '07:00',
                        'assignment': {
                          'teacher': {'id': 8}
                        }
                      },
                      {
                        'id': 1,
                        'day': 'Selasa',
                        'start_time': '08:00',
                        'assignment': {
                          'teacher': {'id': 1}
                        }
                      },
                      {'id': 2, 'day': 'Senin'},
                    ]),
                    200);
              }
              requested.add(request.url.queryParameters['jadwal_id']!);
              return http.Response(jsonEncode(original), 200);
            }));
  });

  test(
      'preparation stops when network policy or pending submissions take priority',
      () async {
    var allowed = true, requests = 0;
    await http.runWithClient(() async {
      final result = await OfflinePreparation().prepare(
          date: '2026-11-10',
          types: ['formal', 'diniyyah'],
          token: 'test',
          canContinue: () async => allowed);
      expect(result.forms, 1);
      expect(requests, 1);
    },
        () => MockClient((request) async {
              if (request.url.path.endsWith('/schedules')) {
                return http.Response(
                    jsonEncode([
                      {'id': 1, 'day': 'Selasa'},
                      {'id': 2, 'day': 'Selasa'}
                    ]),
                    200);
              }
              requests++;
              allowed = false;
              return http.Response(jsonEncode(original), 200);
            }));
  });

  test('reopening a saved form overlays pending changes without deleting them',
      () async {
    await OfflineCacheStore.write('/attendance', original, query: query);
    await SyncStore.instance.enqueue(
        OfflineCacheStore.scope,
        '/attendance',
        {
          'jadwal_id': 1,
          'type': 'formal',
          'date': '2026-11-10',
          'materi': 'Materi offline',
          'records': [
            {'student_id': 5, 'status': 'izin', 'catatan': 'Offline'}
          ]
        },
        'json');
    final data = await attendance.cached('formal', '1', '2026-11-10');
    expect(data!['materi'], 'Materi offline');
    expect(data['students'][0]['status'], 'izin');
    expect(data['__has_pending_changes'], isTrue);
    expect(await SyncStore.instance.entries(OfflineCacheStore.scope),
        hasLength(1));
    OfflineCacheStore.scope = SyncStore.account(2);
    expect(await attendance.cached('formal', '1', '2026-11-10'), isNull);
  });

  test('invalid and denied responses preserve the saved roster', () async {
    await OfflineCacheStore.write('/attendance', original, query: query);
    for (final response in [
      http.Response('{}', 200),
      http.Response('{"error":"denied"}', 403)
    ]) {
      await http.runWithClient(() async {
        await expectLater(
            attendance.refresh('formal', '1', '2026-11-10', 'test'),
            throwsA(isA<ApiException>()));
      }, () => MockClient((_) async => response));
      expect(
          (await attendance.cached('formal', '1', '2026-11-10'))!['students'],
          hasLength(1));
    }
  });

  test(
      'concurrent timetable and form readers share a single request per resource',
      () async {
    for (final resource in ['schedule', 'attendance']) {
      var calls = 0;
      final response = Completer<http.Response>();
      final started = Completer<void>();
      await http.runWithClient(() async {
        Future<Map<String, dynamic>> read() => resource == 'schedule'
            ? ScheduleRepository().refresh('formal', '2026-11-10', 'test')
            : attendance.refresh('formal', '1', '2026-11-10', 'test');
        final first = read();
        final second = read();
        await started.future;
        expect(calls, 1);
        response.complete(http.Response(
            jsonEncode(resource == 'schedule' ? [] : original), 200));
        await Future.wait([first, second]);
      },
          () => MockClient((_) {
                calls++;
                started.complete();
                return response.future;
              }));
    }
  });
}
