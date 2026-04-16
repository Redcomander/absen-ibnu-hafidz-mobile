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
    final restored =
        await OfflineCacheStore.read(path, query: {'type': 'formal'});

    expect(restored, isNotNull);
    expect(restored!['data']['hadir'], 12);
    expect(restored['message'], 'ok');
  });
}
