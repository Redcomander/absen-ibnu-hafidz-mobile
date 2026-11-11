import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ibnu_hafidz_flutter/core/network/offline_cache_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('builds stable cache keys regardless of query order', () {
    final first = OfflineCacheStore.buildKey(
      '/schedules',
      query: {'type': 'formal', 'date': '2026-04-16'},
    );
    final second = OfflineCacheStore.buildKey(
      '/schedules',
      query: {'date': '2026-04-16', 'type': 'formal'},
    );

    expect(first, second);
  });

  test('stores and restores cached API payloads', () async {
    const path = '/attendance/statistics';
    final payload = {
      'data': {'hadir': 12, 'izin': 3},
      'message': 'ok',
    };

    await OfflineCacheStore.write(path, payload, query: {'type': 'formal'});
    final restored = await OfflineCacheStore.read(
      path,
      query: {'type': 'formal'},
    );

    expect(restored, isNotNull);
    expect(restored!['data']['hadir'], 12);
    expect(restored['message'], 'ok');
  });

  test(
    'large cached roster round-trips through background serialization',
    () async {
      final students = List.generate(
        1500,
        (id) => {'id': id, 'name': 'Santri $id', 'status': 'hadir'},
      );
      await OfflineCacheStore.write('/attendance/large', {
        'students': students,
      }, account: 'large|1');
      final restored = await OfflineCacheStore.read(
        '/attendance/large',
        account: 'large|1',
      );
      expect(restored!['students'], students);
      expect(
        await OfflineCacheStore.read('/attendance/large', account: 'large|2'),
        isNull,
      );
    },
  );

  test('cached forms cannot be read under another account', () async {
    const path = '/halaqoh/attendance/4';
    await OfflineCacheStore.write(path, {
      'students': [1],
    }, account: 'host|1');
    expect(await OfflineCacheStore.read(path, account: 'host|2'), isNull);
    expect(
      await OfflineCacheStore.read(path, account: 'another-host|1'),
      isNull,
    );
    expect(
      (await OfflineCacheStore.read(path, account: 'host|1'))!['students'],
      [1],
    );
  });
}
