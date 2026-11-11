import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/network/api_client.dart';
import 'package:ibnu_hafidz_flutter/core/network/offline_cache_store.dart';
import 'package:ibnu_hafidz_flutter/core/network/sync_store.dart';
import 'package:ibnu_hafidz_flutter/features/jadwal/schedule_repository.dart';

void main() {
  final repo = ScheduleRepository();
  final lesson = {
    'id': 4,
    'day': 'Senin',
    'has_attendance': true,
    'attendance_counts': {'hadir': 20},
    'assignment': {
      'teacher': {'id': 1}
    }
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OfflineCacheStore.scope = SyncStore.account(1);
    await (await SyncStore.instance.database).delete('meta');
    ApiClient.refreshAuthToken = null;
  });

  test(
      'unfiltered weekly schedule survives date changes without copying attendance',
      () async {
    await http.runWithClient(
        () => repo.refresh('formal', '2026-11-09', 'token'),
        () => MockClient((request) async {
              expect(request.url.queryParameters,
                  {'type': 'formal', 'date': '2026-11-09'});
              return http.Response(jsonEncode([lesson]), 200);
            }));
    final today = await repo.cached('formal', '2026-11-10');
    expect(today!['data'], hasLength(1));
    expect(today['data'][0]['has_attendance'], isFalse);
    expect(today['data'][0]['attendance_counts'], isEmpty);
    expect(today['__schedule_date'], '2026-11-09');
  });

  test(
      'server failures and malformed refresh never replace the saved timetable',
      () async {
    await http.runWithClient(
        () => repo.refresh('formal', '2026-11-09', 'token'),
        () =>
            MockClient((_) async => http.Response(jsonEncode([lesson]), 200)));
    for (final response in [
      http.Response('unavailable', 503),
      http.Response('{"unexpected":true}', 200)
    ]) {
      await http.runWithClient(() async {
        await expectLater(repo.refresh('formal', '2026-11-10', 'token'),
            throwsA(isA<ApiException>()));
      }, () => MockClient((_) async => response));
      expect(
          (await repo.cached('formal', '2026-11-11'))!['data'], hasLength(1));
    }
  });

  test('schedule snapshots remain separate by account and module', () async {
    await http.runWithClient(
        () => repo.refresh('formal', '2026-11-09', 'token'),
        () =>
            MockClient((_) async => http.Response(jsonEncode([lesson]), 200)));
    expect(await repo.cached('diniyyah', '2026-11-10'), isNull);
    OfflineCacheStore.scope = SyncStore.account(2);
    expect(await repo.cached('formal', '2026-11-10'), isNull);
  });

  test(
      'older unfiltered caches remain available after upgrading and changing date',
      () async {
    await OfflineCacheStore.write('/schedules', {
      'data': [lesson]
    }, query: {
      'type': 'formal',
      'date': '2026-11-09'
    });
    await OfflineCacheStore.write('/schedules', {'data': []},
        query: {'type': 'formal', 'date': '2026-11-10', 'search': 'no match'});
    expect((await repo.cached('formal', '2026-11-11'))!['data'], hasLength(1));
  });

  test(
      'date fallback excludes assignments granted only as a previous substitute',
      () async {
    final temporary = {
      ...lesson,
      'assignment': {
        'teacher': {'id': 9}
      },
      'substitute_teacher': {'id': 1},
      'substitute_date': '2026-11-09'
    };
    await http.runWithClient(
        () => repo.refresh('formal', '2026-11-09', 'token'),
        () => MockClient(
            (_) async => http.Response(jsonEncode([temporary]), 200)));
    expect((await repo.cached('formal', '2026-11-10'))!['data'], isEmpty);
  });
}
