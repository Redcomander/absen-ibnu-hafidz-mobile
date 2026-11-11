import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/network/offline_cache_store.dart';
import 'package:ibnu_hafidz_flutter/core/theme/app_theme.dart';
import 'package:ibnu_hafidz_flutter/features/auth/auth_controller.dart';
import 'package:ibnu_hafidz_flutter/features/halaqoh/halaqoh_reports_screen.dart';

void main() {
  testWidgets('Halaqoh reports use web schemas and isolate picker failures', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    OfflineCacheStore.scope = 'test|1';
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthController()
      ..token = 'test'
      ..user = {'id': 1};
    final paths = <String>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: auth,
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(body: HalaqohReportsScreen()),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Hadir: 12'), findsOneWidget);
        expect(
          paths.where(
            (p) => p.contains('/history/') || p.endsWith('/assignments'),
          ),
          isEmpty,
        );
        await tester.tap(find.text('Guru').first);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Dinas: 2'), findsOneWidget);
        for (var i = 0; i < 5; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -500));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(
          paths.where((p) => p.endsWith('/statistics/teachers')),
          hasLength(1),
        );
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('teacher-options')) {
          return http.Response('{"error":"not allowed"}', 403);
        }
        expect(
          request.url.queryParameters,
          containsPair('start_date', isNotEmpty),
        );
        if (request.url.path.endsWith('/students')) {
          return http.Response(
            jsonEncode({
              'chartData': [
                {'name': 'Hadir', 'value': 12},
                {'name': 'Izin', 'value': 1},
              ],
              'izinStudents': ['Ali'],
              'sakitStudents': [],
              'alpaStudents': [],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'stats': {'Hadir': 3, 'Dinas': 2},
            'sessionStats': {
              'Shubuh': {'Hadir': 3, 'Dinas': 2},
            },
            'substitutionCount': 1,
            'teachers': [
              {'id': 1, 'name': 'Ustadz', 'hadir': 3, 'dinas': 2},
            ],
            'absence_history': [
              {
                'date': '2026-11-11',
                'teacher': 'Ustadz',
                'session': 'Shubuh',
                'status': 'Dinas Luar',
                'notes': 'Kegiatan sekolah',
              },
            ],
            'history': [
              {
                'tanggal': '2026-11-11',
                'sesi': 'Shubuh',
                'guru_asli': 'Ustadz',
                'status': 'Izin',
                'pengganti': 'Guru Badal',
                'reason': 'Izin',
              },
            ],
          }),
          200,
        );
      }),
    );
    auth.dispose();
  });
}
