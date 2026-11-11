// Android-only smoke harness. Build with a separate application ID and a local
// mock API; it deliberately refuses to run against a real server.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/config/app_config.dart';
import 'package:ibnu_hafidz_flutter/core/network/background_sync.dart';
import 'package:ibnu_hafidz_flutter/core/network/sync_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.baseUrl != 'http://10.0.2.2:18089') {
    throw StateError('Smoke test requires its isolated local mock API.');
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('remember_me', true);
  await prefs.setString('auth_token', 'smoke-token');
  await prefs.setString('cached_user', jsonEncode({'id': 901}));
  final store = SyncStore.instance;
  final account = SyncStore.account(901);
  await store.setMeta('active_account', account);
  await store.setMode(account, 'any_network');
  await store.enqueue(account, '/attendance', {'smoke': 'json'}, 'json',
      id: 'smoke-json');
  await store.enqueue(account, '/halaqoh/teacher-attendance/4/session/Shubuh',
      {'status': 'Hadir', 'smoke': 'multipart'}, 'multipart',
      id: 'smoke-multipart');
  await BackgroundSync.schedule(account, 'any_network');
  runApp(const MaterialApp(
      home: Scaffold(
          body: Center(
              child: Text(
                  'SYNC SMOKE QUEUED — background the app and reconnect')))));
}
