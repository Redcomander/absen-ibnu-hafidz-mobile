import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/network/api_client.dart';
import 'package:ibnu_hafidz_flutter/core/network/offline_cache_store.dart';
import 'package:ibnu_hafidz_flutter/core/theme/app_theme.dart';
import 'package:ibnu_hafidz_flutter/features/auth/auth_controller.dart';
import 'package:ibnu_hafidz_flutter/features/jadwal/jadwal_screen.dart';
import 'package:ibnu_hafidz_flutter/features/settings/app_settings_controller.dart';

void main() {
  testWidgets('teacher attendance offers and submits Dinas', (tester) async {
    SharedPreferences.setMockInitialValues({});
    OfflineCacheStore.scope = 'test|1';
    ApiClient.queueOfflineWrite = null;
    final auth = AuthController()
      ..token = 'test'
      ..user = {
        'id': 1,
        'roles': [
          {'name': 'admin'},
        ],
      };
    final settings = AppSettingsController(
      background: true,
      networkCheck: () async => [ConnectivityResult.wifi],
    );
    Map? sent;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: settings),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(body: JadwalScreen()),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Absensi guru'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Absensi guru'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Dinas'));
        await tester.pumpAndSettle();
        expect(find.text('Dinas Luar'), findsNothing);
        await tester.tap(find.text('Dinas').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Simpan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Simpan'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(sent?['status'], 'Dinas');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient((request) async {
        if (request.method == 'POST') {
          sent = jsonDecode(request.body) as Map;
          return http.Response('{}', 200);
        }
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'day': 'Senin',
              'start_time': '08:00',
              'end_time': '09:00',
              'assignment': {
                'teacher': {'id': 1, 'name': 'Guru'},
                'lesson': {'name': 'Fiqih'},
                'kelas': {'nama': 'VII A', 'tingkat': 'SMP'},
              },
            },
          ]),
          200,
        );
      }),
    );
    auth.dispose();
    settings.dispose();
    ApiClient.queueOfflineWrite = null;
    ApiClient.refreshAuthToken = null;
  });
}
