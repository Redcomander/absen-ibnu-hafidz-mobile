import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/network/offline_cache_store.dart';
import 'package:ibnu_hafidz_flutter/core/network/sync_store.dart';
import 'package:ibnu_hafidz_flutter/core/theme/app_theme.dart';
import 'package:ibnu_hafidz_flutter/features/auth/auth_controller.dart';
import 'package:ibnu_hafidz_flutter/features/settings/app_settings_controller.dart';
import 'package:ibnu_hafidz_flutter/features/stats/stats_screen.dart';

void main() {
  testWidgets('offline reports fit a narrow screen with large text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    OfflineCacheStore.scope = SyncStore.account(1);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final query = {
      'type': 'formal',
      'start_date':
          DateTime(now.year, now.month, 1).toIso8601String().split('T').first,
      'end_date': now.toIso8601String().split('T').first
    };
    await tester.runAsync(() async {
      await OfflineCacheStore.write(
          '/attendance/statistics',
          {
            'student_counts': {'hadir': 18, 'alpa': 2}
          },
          query: query);
      await OfflineCacheStore.write(
          '/attendance/teacher-statistics',
          {
            'teacher_counts': {'Hadir': 1}
          },
          query: query);
      await OfflineCacheStore.write(
          '/attendance/history', {'data': [], 'total': 0},
          query: {...query, 'page': '1', 'per_page': '50'});
    });
    final auth = AuthController()
      ..user = {
        'id': 1,
        'roles': [
          {'name': 'admin'}
        ]
      };
    final settings = AppSettingsController(
        background: true, networkCheck: () async => [ConnectivityResult.none]);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<AppSettingsController>.value(value: settings),
        ],
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: const Scaffold(body: StatsScreen()))));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
    expect(find.text('Rekapan Kehadiran'), findsOneWidget);
    for (var index = 0; index < 5; index++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    settings.dispose();
  });
}
