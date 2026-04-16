import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';

class AppSettingsController extends ChangeNotifier {
  static const _ramadhanTabKey = 'feature_ramadhan_tab_enabled';
  static const _syncModeKey = 'sync_mode';
  static const _offlineQueueKey = 'offline_sync_queue';

  bool isLoading = true;
  bool isRamadhanTabEnabled = true;
  bool isSyncing = false;
  String syncMode = 'any_network';
  int pendingSyncCount = 0;
  List<ConnectivityResult> _connectivityResults = const [ConnectivityResult.none];
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  AppSettingsController() {
    ApiClient.canUseNetwork = canSyncNow;
    ApiClient.queueOfflineWrite = queueOfflineWrite;
  }

  bool get isOnline =>
      _connectivityResults.isNotEmpty &&
      _connectivityResults.any((r) => r != ConnectivityResult.none);

  bool get isWifiLike =>
      _connectivityResults.contains(ConnectivityResult.wifi) ||
      _connectivityResults.contains(ConnectivityResult.ethernet) ||
      _connectivityResults.contains(ConnectivityResult.vpn);

  String get connectionLabel {
    if (!isOnline) return 'Offline';
    if (isWifiLike) return 'Wi-Fi';
    if (_connectivityResults.contains(ConnectivityResult.mobile)) {
      return 'Data seluler';
    }
    return 'Online';
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isRamadhanTabEnabled = prefs.getBool(_ramadhanTabKey) ?? true;
    syncMode = prefs.getString(_syncModeKey) ?? 'any_network';
    pendingSyncCount = _readQueue(prefs).length;
    _connectivityResults = await Connectivity().checkConnectivity();

    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      _connectivityResults = results;
      notifyListeners();
      if (_shouldSyncOnCurrentNetwork()) {
        syncPendingActions();
      }
    });

    isLoading = false;
    notifyListeners();
    Future.microtask(syncPendingActions);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> setRamadhanTabEnabled(bool value) async {
    isRamadhanTabEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ramadhanTabKey, value);
    notifyListeners();
  }

  Future<void> setSyncMode(String value) async {
    syncMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncModeKey, value);
    notifyListeners();

    if (_shouldSyncOnCurrentNetwork()) {
      await syncPendingActions();
    }
  }

  Future<bool> canSyncNow() async {
    _connectivityResults = await Connectivity().checkConnectivity();
    return _shouldSyncOnCurrentNetwork();
  }

  Future<Map<String, dynamic>> queueOfflineWrite(
    String path, {
    String? token,
    Object? body,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _readQueue(prefs);

    queue.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'path': path,
      'token': token,
      'body': body,
      'created_at': DateTime.now().toIso8601String(),
    });

    await _writeQueue(prefs, queue);
    pendingSyncCount = queue.length;
    notifyListeners();

    return {
      'queued': true,
      'message': 'Disimpan offline. Akan disinkronkan otomatis saat koneksi sesuai pengaturan tersedia.',
    };
  }

  Future<void> syncPendingActions() async {
    if (isSyncing) return;

    final allowed = await canSyncNow();
    if (!allowed) {
      notifyListeners();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final queue = _readQueue(prefs);
    if (queue.isEmpty) {
      pendingSyncCount = 0;
      notifyListeners();
      return;
    }

    isSyncing = true;
    notifyListeners();

    final remaining = <Map<String, dynamic>>[];
    for (final action in queue) {
      try {
        await ApiClient.post(
          action['path']?.toString() ?? '',
          token: action['token']?.toString(),
          body: action['body'],
          queueOnOffline: false,
        );
      } catch (_) {
        remaining.add(action);
      }
    }

    await _writeQueue(prefs, remaining);
    pendingSyncCount = remaining.length;
    isSyncing = false;
    notifyListeners();
  }

  bool _shouldSyncOnCurrentNetwork() {
    if (!isOnline) return false;
    if (syncMode == 'any_network') return true;
    return isWifiLike;
  }

  List<Map<String, dynamic>> _readQueue(SharedPreferences prefs) {
    final raw = prefs.getString(_offlineQueueKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];

    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _writeQueue(
    SharedPreferences prefs,
    List<Map<String, dynamic>> queue,
  ) async {
    await prefs.setString(_offlineQueueKey, jsonEncode(queue));
  }
}
