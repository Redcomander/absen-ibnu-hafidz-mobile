import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/notifications/schedule_alerts.dart';
import '../../core/network/json_codec.dart';
import '../../core/network/background_sync.dart';
import '../../core/network/sync_store.dart';
import '../auth/auth_controller.dart';
import '../jadwal/offline_preparation.dart';

class AppSettingsController extends ChangeNotifier with WidgetsBindingObserver {
  AppSettingsController({this.background = false, this.networkCheck}) {
    if (!background) {
      ScheduleAlerts.instance.onStatus = _notify;
      ApiClient.canUseNetwork = canSyncNow;
      ApiClient.queueOfflineWrite = queueOfflineWrite;
    }
  }
  final bool background;
  final Future<List<ConnectivityResult>> Function()? networkCheck;
  final store = SyncStore.instance;
  bool isLoading = true, isRamadhanTabEnabled = true, isSyncing = false;
  String syncMode = 'any_network';
  int pendingSyncCount = 0, blockedSyncCount = 0, legacyCount = 0;
  String? lastSyncError, lastSuccess;
  List<Map<String, Object?>> queueItems = [];
  List<ConnectivityResult> _connectivityResults = const [
    ConnectivityResult.none,
  ];
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _retryTimer;
  AuthController? _auth;
  String? _account;
  bool _disposed = false;
  bool _alertsBound = false;
  ScheduleAlerts get scheduleAlerts => ScheduleAlerts.instance;
  Future<void> setScheduleAlerts(bool value) async {
    await scheduleAlerts.setEnabled(value);
    _notify();
  }

  int _generation = 0;
  bool _warmingSchedules = false;
  DateTime? _lastScheduleWarmup;
  String? lastOfflinePreparation;
  int preparedAttendanceForms = 0;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get isOnline =>
      _connectivityResults.any((r) => r != ConnectivityResult.none);
  // A VPN can use metered mobile data, so it is never treated as Wi-Fi by itself.
  bool get isWifiLike =>
      _connectivityResults.contains(ConnectivityResult.wifi) ||
      _connectivityResults.contains(ConnectivityResult.ethernet);
  String get connectionLabel => !isOnline
      ? 'Offline'
      : isWifiLike
      ? 'Wi-Fi'
      : _connectivityResults.contains(ConnectivityResult.mobile)
      ? 'Data seluler'
      : 'Online';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isRamadhanTabEnabled =
        prefs.getBool('feature_ramadhan_tab_enabled') ?? true;
    _connectivityResults =
        await (networkCheck?.call() ?? Connectivity().checkConnectivity());
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      _connectivityResults = results;
      _notify();
      unawaited(syncPendingActions());
    });
    _retryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(syncPendingActions()),
    );
    if (!background) {
      await scheduleAlerts.configureRamadhan(isRamadhanTabEnabled);
    }
    isLoading = false;
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!background) unawaited(scheduleAlerts.resume());
      unawaited(refreshStatus());
      unawaited(syncPendingActions());
    }
  }

  Future<void> bindAccount(
    AuthController auth, {
    bool persistActive = true,
  }) async {
    _auth = auth;
    final next = auth.isAuthenticated && auth.user?['id'] != null
        ? SyncStore.account(auth.user!['id'])
        : null;
    if (_account == next) {
      if (!background && !_alertsBound && !auth.isLoading) {
        _alertsBound = true;
        unawaited(scheduleAlerts.bind(next, ramadhan: isRamadhanTabEnabled));
      }
      return;
    }
    final generation = ++_generation;
    final old = _account;
    _account = next;
    _lastScheduleWarmup = null;
    lastOfflinePreparation = null;
    preparedAttendanceForms = 0;
    queueItems = [];
    pendingSyncCount = 0;
    blockedSyncCount = 0;
    lastSyncError = null;
    lastSuccess = null;
    if (!background) {
      _alertsBound = true;
      unawaited(scheduleAlerts.bind(next, ramadhan: isRamadhanTabEnabled));
    }
    if (persistActive) await store.setMeta('active_account', next ?? '');
    if (old != null && !background) await BackgroundSync.cancel(old);
    if (next == null || generation != _generation) {
      _notify();
      return;
    }
    final mode = await store.mode(next);
    if (generation != _generation) return;
    syncMode = mode;
    await refreshStatus();
    if (!background && auth.rememberMe) {
      try {
        await BackgroundSync.schedule(next, mode);
      } catch (_) {
        lastSyncError =
            'Penjadwalan latar belakang belum tersedia. Sinkronisasi dalam aplikasi tetap aktif.';
      }
    }
    _notify();
    if (!background) unawaited(syncPendingActions());
  }

  Future<void> refreshStatus({bool notify = true}) async {
    final account = _account;
    if (account == null) return;
    final rows = await store.entries(account, includeBody: false);
    final success = await store.lastSuccess(account);
    final ready = await store.getMeta(
      'offline_ready::$account::${DateTime.now().toIso8601String().split('T').first}',
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('offline_sync_queue');
    if (_account != account || _disposed) return;
    final oldStatus = (
      pendingSyncCount,
      blockedSyncCount,
      lastSuccess,
      preparedAttendanceForms,
      lastOfflinePreparation,
      legacyCount,
    );
    final rowsChanged =
        rows.length != queueItems.length ||
        List.generate(
          rows.length,
          (i) => i,
        ).any((i) => !mapEquals(rows[i], queueItems[i]));
    queueItems = rows;
    pendingSyncCount = rows.length;
    blockedSyncCount = rows.where((r) => r['state'] == 'blocked').length;
    lastSuccess = success;
    preparedAttendanceForms = 0;
    lastOfflinePreparation = null;
    if (ready != null) {
      try {
        final data = jsonDecode(ready) as Map;
        preparedAttendanceForms = (data['forms'] as num).toInt();
        lastOfflinePreparation = data['at']?.toString();
      } catch (_) {
        /* Leave malformed preparation metadata untouched. */
      }
    }
    legacyCount = 0;
    if (raw != null) {
      try {
        legacyCount = (jsonDecode(raw) as List).length;
      } catch (_) {
        legacyCount = 1;
      }
    }
    final status = (
      pendingSyncCount,
      blockedSyncCount,
      lastSuccess,
      preparedAttendanceForms,
      lastOfflinePreparation,
      legacyCount,
    );
    if (notify && (rowsChanged || status != oldStatus)) _notify();
  }

  Future<void> setRamadhanTabEnabled(bool value) async {
    isRamadhanTabEnabled = value;
    if (!background) await scheduleAlerts.configureRamadhan(value);
    await (await SharedPreferences.getInstance()).setBool(
      'feature_ramadhan_tab_enabled',
      value,
    );
    _notify();
  }

  Future<void> setSyncMode(String value) async {
    final account = _account;
    if (account == null) return;
    await store.setMode(account, value);
    if (_account != account) return;
    syncMode = value;
    if (_auth?.rememberMe == true) {
      await BackgroundSync.schedule(account, value, replace: true);
    }
    _notify();
    await syncPendingActions();
  }

  Future<bool> canSyncNow() async {
    final previous = (isOnline, isWifiLike, connectionLabel);
    _connectivityResults =
        await (networkCheck?.call() ?? Connectivity().checkConnectivity());
    if (previous != (isOnline, isWifiLike, connectionLabel)) _notify();
    return isOnline && (syncMode == 'any_network' || isWifiLike);
  }

  Future<Map<String, dynamic>> queueOfflineWrite(
    String path, {
    String? token,
    Object? body,
    String encoding = 'json',
  }) async {
    final account = _account;
    if (account == null || _auth?.isAuthenticated != true) {
      throw ApiException(
        401,
        'Masuk kembali sebelum menyimpan absensi offline.',
      );
    }
    if (token != null && token != _auth?.token) {
      throw ApiException(409, 'Sesi telah berubah. Buka kembali formulir.');
    }
    final id = await store.enqueue(account, path, body, encoding);
    await refreshStatus();
    if (!background && _auth?.rememberMe == true) {
      try {
        await BackgroundSync.schedule(account, syncMode);
      } catch (_) {
        /* Durable queue remains available to foreground retries. */
      }
    }
    if (await canSyncNow()) await syncPendingActions();
    final queued = await store.hasEntries(account, id: id);
    return {
      'queued': queued,
      'queue_id': id,
      'message': queued
          ? 'Tersimpan di perangkat. Menunggu konfirmasi server; lihat Pengaturan Sinkronisasi untuk status.'
          : 'Absensi berhasil dikonfirmasi server.',
    };
  }

  Future<String?> queueDetails(String id) async {
    final account = _account;
    if (account == null) return null;
    final body = await store.body(account, id);
    return _account == account ? body : null;
  }

  Future<void> retryBlocked() async {
    if (_account == null) return;
    await store.retry(_account!);
    await syncPendingActions();
  }

  Future<void> syncPendingActions() async {
    final account = _account;
    if (isSyncing || account == null || _auth?.isAuthenticated != true) return;
    isSyncing = true;
    var announced = false;
    String? lease;
    try {
      if (!await canSyncNow()) return;
      if (await store.getMeta('active_account') != account) return;
      if (_auth?.isOfflineSession == true) {
        if (!await _auth!.reconnect()) return;
        if (_account != account) return;
      }
      if (!await store.hasEntries(account)) return;
      announced = true;
      _notify();
      lease = await store.acquire('sync');
      if (lease == null) return;
      final rows = await store.entries(account, limit: 12);
      for (final action in rows) {
        if (_account != account ||
            await store.getMeta('active_account') != account ||
            !await canSyncNow()) {
          break;
        }
        // Preserve ordering: a newer edit must not overtake an unresolved older edit.
        if (action['state'] == 'blocked') break;
        await store.renew('sync', lease);
        try {
          final body = await BackgroundJson.decode(action['body'] as String);
          final path = action['path'] as String;
          if (_account != account ||
              _auth?.user?['id'] == null ||
              SyncStore.account(_auth!.user!['id']) != account) {
            break;
          }
          final currentToken = _auth!.token;
          if (currentToken == null) {
            throw ApiException(
              401,
              'Sesi berakhir. Masuk kembali untuk menyinkronkan.',
            );
          }
          if (action['encoding'] == 'multipart') {
            await ApiClient.postMultipart(
              path,
              token: currentToken,
              fields: Map<String, dynamic>.from(
                body as Map,
              ).map((key, value) => MapEntry(key, value?.toString() ?? '')),
              queueOnOffline: false,
            );
          } else {
            await ApiClient.post(
              path,
              token: currentToken,
              body: body,
              queueOnOffline: false,
            );
          }
          await store.acknowledge(account, action['id'] as String);
          lastSyncError = null;
          await Future<void>.delayed(Duration.zero);
        } catch (error) {
          final blocked =
              error is ApiException &&
              !error.isServerProtection &&
              [400, 403, 404, 409, 422].contains(error.statusCode);
          final message = error is ApiException
              ? error.message
              : 'Koneksi server terputus; data tetap dalam antrean.';
          await store.fail(
            account,
            action['id'] as String,
            message,
            blocked: blocked,
          );
          lastSyncError = message;
          break;
        }
      }
    } catch (error) {
      lastSyncError = error is ApiException
          ? error.message
          : 'Sinkronisasi belum selesai. Data tetap tersimpan.';
    } finally {
      if (lease != null) await store.release('sync', lease);
      isSyncing = false;
      await refreshStatus(notify: !announced);
      if (announced) _notify();
      if (!background && _account == account && pendingSyncCount == 0) {
        unawaited(_warmSchedules(account));
      }
    }
  }

  Future<void> _warmSchedules(String account) async {
    if (_warmingSchedules ||
        (_lastScheduleWarmup != null &&
            DateTime.now().difference(_lastScheduleWarmup!) <
                const Duration(minutes: 10))) {
      return;
    }
    _warmingSchedules = true;
    _lastScheduleWarmup = DateTime.now();
    try {
      if (_disposed || _account != account || !await canSyncNow()) {
        _lastScheduleWarmup = null;
        return;
      }
      final date = DateTime.now().toIso8601String().split('T').first;
      final result = await OfflinePreparation().prepare(
        date: date,
        types: ['formal', 'diniyyah', if (isRamadhanTabEnabled) 'ramadhan'],
        token: _auth?.token,
        canContinue: () async {
          if (_disposed || _account != account || !await canSyncNow()) {
            return false;
          }
          return _account == account && !await store.hasEntries(account);
        },
      );
      if (_disposed || _account != account) return;
      await scheduleAlerts.prepareMidnightSubstitutes(
        token: _auth?.token,
        canContinue: () async =>
            !_disposed &&
            _account == account &&
            await canSyncNow() &&
            !await store.hasEntries(account),
      );
      if (_disposed || _account != account) return;
      if (result.schedules == 0) {
        _lastScheduleWarmup = DateTime.now().subtract(
          const Duration(minutes: 9),
        );
        return;
      }
      preparedAttendanceForms = result.forms;
      lastOfflinePreparation = DateTime.now().toLocal().toIso8601String();
      await store.setMeta(
        'offline_ready::$account::$date',
        jsonEncode({'forms': result.forms, 'at': lastOfflinePreparation}),
      );
      if (result.failures > 0) {
        _lastScheduleWarmup = DateTime.now().subtract(
          const Duration(minutes: 9),
        );
      }
      _notify();
    } catch (_) {
      _lastScheduleWarmup = DateTime.now().subtract(const Duration(minutes: 9));
    } finally {
      _warmingSchedules = false;
    }
  }

  // Legacy rows are never silently assigned to the next person using this device.
  Future<void> importLegacyForCurrentUser() async {
    final account = _account;
    if (account == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('offline_sync_queue');
    if (raw == null) return;
    final rows = jsonDecode(raw) as List;
    for (final item in rows.whereType<Map>()) {
      if (_account != account) return;
      try {
        final parts = (item['token'] as String).split('.');
        final claims =
            jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
                )
                as Map;
        if (claims['user_id'].toString() != _auth?.user?['id'].toString()) {
          continue;
        }
        final id = 'legacy-${item['id']}';
        if (await store.getMeta(id) != null) continue;
        if (_account != account) return;
        final path = item['path'].toString();
        await store.enqueue(
          account,
          path,
          item['body'],
          path.startsWith('/halaqoh/teacher-attendance/')
              ? 'multipart'
              : 'json',
          id: id,
        );
        await store.setMeta(id, 'imported');
      } catch (_) {
        /* Preserve malformed/unowned legacy rows in their original storage. */
      }
    }
    await refreshStatus();
    await syncPendingActions();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!background && scheduleAlerts.onStatus == _notify) {
      scheduleAlerts.onStatus = null;
    }
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (!background && ApiClient.queueOfflineWrite == queueOfflineWrite) {
      ApiClient.queueOfflineWrite = null;
      ApiClient.canUseNetwork = null;
    }
    super.dispose();
  }
}
