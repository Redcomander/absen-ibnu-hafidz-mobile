import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/settings/app_settings_controller.dart';
import 'sync_store.dart';
import '../notifications/schedule_alerts.dart';
import '../../features/jadwal/schedule_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void syncDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final account = input?['account']?.toString();
    if (account == null ||
        await SyncStore.instance.getMeta('active_account') != account) {
      return true;
    }
    final auth = AuthController(backgroundAccount: account);
    final controller = AppSettingsController(background: true);
    try {
      controller.syncMode = await SyncStore.instance.mode(account);
      if (!await controller.canSyncNow()) return false;
      await auth.init();
      if (!auth.isAuthenticated ||
          auth.user?['id'] == null ||
          SyncStore.account(auth.user!['id']) != account) {
        return true;
      }
      await controller.bindAccount(auth, persistActive: false);
      await controller.syncPendingActions();
      final rows = await SyncStore.instance.entries(
        account,
        limit: 1,
        includeBody: false,
      );
      if (rows.isEmpty &&
          await SyncStore.instance.getMeta('active_account') == account) {
        final alerts = ScheduleAlerts.instance;
        final ramadhan =
            (await SharedPreferences.getInstance()).getBool(
              'feature_ramadhan_tab_enabled',
            ) ??
            true;
        await alerts.bind(account, ramadhan: ramadhan, foreground: false);
        final date = campusDate(campusNow());
        for (final type in ['formal', 'diniyyah', if (ramadhan) 'ramadhan']) {
          if (!await controller.canSyncNow() ||
              await SyncStore.instance.getMeta('active_account') != account) {
            break;
          }
          try {
            await ScheduleRepository().refresh(type, date, auth.token);
          } catch (_) {
            /* Keep cached reminders on timeout. */
          }
        }
        await alerts.prepareMidnightSubstitutes(
          token: auth.token,
          canContinue: () async =>
              await controller.canSyncNow() &&
              await SyncStore.instance.getMeta('active_account') == account,
        );
        await alerts.publish();
      }
      return rows.isEmpty || rows.first['state'] == 'blocked';
    } catch (_) {
      return false;
    } finally {
      controller.dispose();
      auth.dispose();
    }
  });
}

class BackgroundSync {
  static bool get supported => !kIsWeb && Platform.isAndroid;
  static bool _initialized = false;
  static Future<void> schedule(
    String account,
    String mode, {
    bool replace = false,
  }) async {
    if (!supported) return;
    if (!_initialized) {
      await Workmanager().initialize(syncDispatcher);
      _initialized = true;
    }
    final constraints = Constraints(
      networkType: mode == 'wifi_only'
          ? NetworkType.unmetered
          : NetworkType.connected,
    );
    await Workmanager().registerOneOffTask(
      'ibnu-sync-$account',
      'attendance-sync',
      inputData: {'account': account},
      constraints: constraints,
      existingWorkPolicy: replace
          ? ExistingWorkPolicy.replace
          : ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
    await Workmanager().registerPeriodicTask(
      'ibnu-periodic-$account',
      'attendance-sync',
      inputData: {'account': account},
      constraints: constraints,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  static Future<void> cancel(String account) async {
    if (!supported) return;
    await Workmanager().cancelByUniqueName('ibnu-sync-$account');
    await Workmanager().cancelByUniqueName('ibnu-periodic-$account');
  }
}
