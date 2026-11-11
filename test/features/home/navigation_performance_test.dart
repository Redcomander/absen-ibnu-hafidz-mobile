import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/network/offline_cache_store.dart';
import 'package:ibnu_hafidz_flutter/core/network/sync_store.dart';
import 'package:ibnu_hafidz_flutter/core/theme/app_theme.dart';
import 'package:ibnu_hafidz_flutter/features/auth/auth_controller.dart';
import 'package:ibnu_hafidz_flutter/features/home/home_shell.dart';
import 'package:ibnu_hafidz_flutter/features/settings/app_settings_controller.dart';

void main() {
  testWidgets('tabs load lazily and returning to Jadwal does not refetch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    OfflineCacheStore.scope = SyncStore.account(1);
    final auth = AuthController()
      ..token = 'test'
      ..user = {
        'id': 1,
        'name': 'Guru',
        'roles': [
          {'name': 'admin'},
        ],
      };
    final settings = AppSettingsController(
      background: true,
      networkCheck: () async => [ConnectivityResult.wifi],
    );
    var calls = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthController>.value(value: auth),
              ChangeNotifierProvider<AppSettingsController>.value(
                value: settings,
              ),
            ],
            child: MaterialApp(theme: AppTheme.light, home: const HomeShell()),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          calls,
          0,
          reason: 'unopened Jadwal and Rekapan must not fetch at startup',
        );
        await tester.tap(find.byKey(const ValueKey('nav-Jadwal')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(calls, 1);
        final searchBeforeSync = tester.widget<TextField>(
          find.byType(TextField).first,
        );
        settings.isSyncing = true;
        await settings.setRamadhanTabEnabled(settings.isRamadhanTabEnabled);
        await tester.pump();
        expect(
          identical(
            tester.widget<TextField>(find.byType(TextField).first),
            searchBeforeSync,
          ),
          isTrue,
          reason: 'sync state changes must not rebuild the timetable',
        );
        settings.isSyncing = false;
        await tester.enterText(find.byType(TextField).first, 'fiqih');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(const ValueKey('nav-Pengaturan')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-Jadwal')));
        await tester.pumpAndSettle();
        expect(
          calls,
          1,
          reason: 'returning to the same tab should reuse its data',
        );
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'fiqih',
        );
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        calls++;
        expect(request.url.path, '/api/schedules');
        return http.Response('[]', 200);
      }),
    );
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    settings.dispose();
  });
}
