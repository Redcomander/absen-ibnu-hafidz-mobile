import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/network/api_client.dart';
import 'package:ibnu_hafidz_flutter/core/network/offline_cache_store.dart';
import 'package:ibnu_hafidz_flutter/core/network/sync_store.dart';
import 'package:ibnu_hafidz_flutter/features/auth/auth_controller.dart';
import 'package:ibnu_hafidz_flutter/features/settings/app_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = SyncStore.instance;
  late AuthController auth;
  late AppSettingsController sync;
  var network = <ConnectivityResult>[ConnectivityResult.none];
  final account = SyncStore.account(1);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = await store.database;
    for (final table in ['queue', 'settings', 'meta', 'leases']) {
      await db.delete(table);
    }
    network = [ConnectivityResult.none];
    auth = AuthController()
      ..user = {'id': 1}
      ..token = 'account-one'
      ..isAuthenticated = true;
    OfflineCacheStore.scope = account;
    sync = AppSettingsController(
      background: true,
      networkCheck: () async => network,
    );
    await sync.bindAccount(auth);
  });
  tearDown(() {
    sync.dispose();
    auth.dispose();
    ApiClient.refreshAuthToken = null;
    ApiClient.queueOfflineWrite = null;
    ApiClient.canUseNetwork = null;
  });

  test('idle sync does not publish busy-state rebuilds', () async {
    network = [ConnectivityResult.wifi];
    await sync.canSyncNow();
    var notifications = 0;
    sync.addListener(() => notifications++);
    await sync.syncPendingActions();
    expect(notifications, 0);
    expect(sync.isSyncing, isFalse);
  });

  test('limited queue reads preserve FIFO and account isolation', () async {
    for (var n = 0; n < 15; n++) {
      await store.enqueue(
        account,
        '/attendance',
        {'n': n},
        'json',
        id: 'row-$n',
      );
    }
    await store.enqueue(SyncStore.account(2), '/attendance', {}, 'json');
    final all = await store.entries(account);
    final batch = await store.entries(account, limit: 12);
    expect(batch, all.take(12).toList());
    expect(await store.hasEntries(account, id: 'row-14'), isTrue);
    expect(await store.hasEntries(SyncStore.account(2), id: 'row-14'), isFalse);
    expect((await store.entries(account)).length, 15);
  });

  test('sync status excludes payloads but details remain available', () async {
    final id = await store.enqueue(account, '/attendance', {
      'materi': 'Saved lesson',
    }, 'json');
    await sync.refreshStatus();
    expect(sync.pendingSyncCount, 1);
    expect(sync.queueItems.single.containsKey('body'), isFalse);
    expect(jsonDecode((await sync.queueDetails(id))!), {
      'materi': 'Saved lesson',
    });
    await store.acknowledge(account, id);
    expect(await sync.queueDetails(id), isNull);
  });

  test(
    'offline save survives controller restart and sends current credentials',
    () async {
      final result = await sync.queueOfflineWrite(
        '/attendance',
        body: {'status': 'hadir'},
      );
      expect(result['queued'], isTrue);
      sync.dispose();
      sync = AppSettingsController(
        background: true,
        networkCheck: () async => network,
      );
      await sync.bindAccount(auth);
      expect(sync.pendingSyncCount, 1);
      auth.token = 'renewed-token';
      network = [ConnectivityResult.wifi];
      await http.runWithClient(
        sync.syncPendingActions,
        () => MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer renewed-token');
          expect(jsonDecode(request.body), {'status': 'hadir'});
          return http.Response('{"message":"saved"}', 200);
        }),
      );
      expect(await store.entries(account), isEmpty);
      expect(await store.lastSuccess(account), isNotNull);
    },
  );

  test(
    'acknowledging in-flight save preserves a newly queued submission',
    () async {
      await sync.queueOfflineWrite('/attendance', body: {'n': 1});
      network = [ConnectivityResult.wifi];
      final started = Completer<void>();
      final response = Completer<http.Response>();
      await http.runWithClient(
        () async {
          final sending = sync.syncPendingActions();
          await started.future;
          await sync.queueOfflineWrite('/attendance', body: {'n': 2});
          response.complete(http.Response('{"message":"saved"}', 200));
          await sending;
        },
        () => MockClient((_) async {
          started.complete();
          return response.future;
        }),
      );
      final rows = await store.entries(account);
      expect(rows, hasLength(1));
      expect(jsonDecode(rows.single['body'] as String), {'n': 2});
    },
  );

  test(
    'Wi-Fi preference excludes mobile and VPN and belongs to one account',
    () async {
      await sync.setSyncMode('wifi_only');
      network = [ConnectivityResult.mobile, ConnectivityResult.vpn];
      expect(await sync.canSyncNow(), isFalse);
      await sync.queueOfflineWrite('/attendance', body: {'n': 1});
      auth.user = {'id': 2};
      auth.token = 'account-two';
      await sync.bindAccount(auth);
      expect(sync.syncMode, 'any_network');
      expect(sync.pendingSyncCount, 0);
      expect(await sync.canSyncNow(), isTrue);
      expect(await store.entries(account), hasLength(1));
      auth.user = {'id': 1};
      auth.token = 'account-one';
      await sync.bindAccount(auth);
      expect(sync.syncMode, 'wifi_only');
      expect(sync.pendingSyncCount, 1);
    },
  );

  test(
    'server validation blocks the queue without deleting or overtaking data',
    () async {
      await sync.queueOfflineWrite('/attendance', body: {'n': 1});
      await sync.queueOfflineWrite('/attendance', body: {'n': 2});
      network = [ConnectivityResult.wifi];
      var calls = 0;
      await http.runWithClient(
        sync.syncPendingActions,
        () => MockClient((_) async {
          calls++;
          return http.Response('{"error":"Permission changed"}', 403);
        }),
      );
      expect(calls, 1);
      expect(sync.pendingSyncCount, 2);
      expect(sync.blockedSyncCount, 1);
      await http.runWithClient(
        sync.syncPendingActions,
        () => MockClient((_) async {
          fail(
            'A blocked submission must prevent later submissions overtaking it',
          );
        }),
      );
      await http.runWithClient(
        sync.retryBlocked,
        () => MockClient((_) async => http.Response('{}', 200)),
      );
      expect(sync.pendingSyncCount, 0);
    },
  );

  test(
    'network and server failures retain data for automatic retries',
    () async {
      await sync.queueOfflineWrite('/attendance', body: {'n': 1});
      network = [ConnectivityResult.wifi];
      for (final client in [
        MockClient((_) async => throw http.ClientException('offline')),
        MockClient((_) async => http.Response('<html>unavailable</html>', 500)),
        MockClient(
          (_) async => http.Response(
            '<html>Access denied by Imunify360 bot-protection</html>',
            403,
          ),
        ),
      ]) {
        await http.runWithClient(sync.syncPendingActions, () => client);
        final rows = await store.entries(account);
        expect(rows, hasLength(1));
        expect(rows.single['state'], 'pending');
      }
      await http.runWithClient(
        sync.syncPendingActions,
        () => MockClient((_) async => http.Response('{}', 200)),
      );
      expect(sync.pendingSyncCount, 0);
    },
  );

  test(
    'Halaqoh teacher replay preserves multipart fields and capture time',
    () async {
      await sync.queueOfflineWrite(
        '/halaqoh/teacher-attendance/4/session/Shubuh',
        body: {
          'status': 'Hadir',
          'captured_at': '2026-11-10T22:00:00Z',
          'offline_permit': 'signed',
        },
        encoding: 'multipart',
      );
      network = [ConnectivityResult.wifi];
      await http.runWithClient(
        sync.syncPendingActions,
        () => MockClient((request) async {
          expect(
            request.headers['content-type'],
            contains('multipart/form-data'),
          );
          expect(request.body, contains('name="status"'));
          expect(request.body, contains('Hadir'));
          expect(request.body, contains('2026-11-10T22:00:00Z'));
          expect(request.body, contains('signed'));
          return http.Response('{}', 200);
        }),
      );
      expect(sync.pendingSyncCount, 0);
    },
  );

  test(
    'account switch during transmission never sends remaining old rows as new user',
    () async {
      await sync.queueOfflineWrite('/attendance', body: {'n': 1});
      await sync.queueOfflineWrite('/attendance', body: {'n': 2});
      network = [ConnectivityResult.wifi];
      var calls = 0;
      await http.runWithClient(
        sync.syncPendingActions,
        () => MockClient((request) async {
          calls++;
          expect(request.headers['authorization'], 'Bearer account-one');
          auth.user = {'id': 2};
          auth.token = 'account-two';
          await sync.bindAccount(auth);
          return http.Response('{}', 200);
        }),
      );
      expect(calls, 1);
      expect(await store.entries(account), hasLength(1));
      expect(await store.entries(SyncStore.account(2)), isEmpty);
    },
  );

  test(
    'leases exclude another worker and acknowledgment cannot cross accounts',
    () async {
      final id = await store.enqueue(account, '/attendance', {}, 'json');
      final owner = await store.acquire('sync');
      expect(owner, isNotNull);
      expect(await store.acquire('sync'), isNull);
      await store.release('sync', 'other-owner');
      expect(await store.acquire('sync'), isNull);
      await store.release('sync', owner!);
      expect(await store.acquire('sync'), isNotNull);
      await store.acknowledge(SyncStore.account(2), id);
      expect(await store.entries(account), hasLength(1));
    },
  );

  test(
    'legacy recovery imports only the owner and retains the original data',
    () async {
      String oldToken(int id) =>
          'header.${base64Url.encode(utf8.encode(jsonEncode({'user_id': id})))}.signature';
      final raw = jsonEncode([
        {
          'id': 'one',
          'path': '/attendance',
          'token': oldToken(1),
          'body': {'n': 1},
        },
        {
          'id': 'two',
          'path': '/attendance',
          'token': oldToken(2),
          'body': {'n': 2},
        },
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_sync_queue', raw);
      await sync.importLegacyForCurrentUser();
      final rows = await store.entries(account);
      expect(rows, hasLength(1));
      expect(jsonDecode(rows.single['body'] as String), {'n': 1});
      expect(rows.single.containsKey('token'), isFalse);
      expect(prefs.getString('offline_sync_queue'), raw);
      await store.acknowledge(account, rows.single['id'] as String);
      await sync.importLegacyForCurrentUser();
      expect(await store.entries(account), isEmpty);
      expect(prefs.getString('offline_sync_queue'), raw);
    },
  );
}
