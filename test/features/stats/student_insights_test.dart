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
import 'package:ibnu_hafidz_flutter/features/students/attendance_insights.dart';
import 'package:ibnu_hafidz_flutter/features/students/student_rankings.dart';
import 'package:ibnu_hafidz_flutter/features/students/student_progress_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineCacheStore.scope = 'insights-test';
  });
  test(
    'frequency counts group by identity and keep same-name students separate',
    () {
      final rows = groupStudentOccurrences([
        {'student_id': 1, 'name': 'Ali'},
        {'student_id': 2, 'name': 'Ali'},
        {'student_id': 1, 'name': 'Ali'},
        {'student_id': 3, 'name': 'Hasan', 'count': 5},
      ]);
      expect(rows.map((r) => r.count), [5, 2, 1]);
      expect(rows[1].id, 1);
      expect(rows[2].id, 2);
      expect(attendanceStatus('alpa'), 'Alpha');
      expect(attendanceStatus('tidak_hadir'), 'Alpha');
    },
  );

  testWidgets('each status searches independently and retains full totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                StudentStatusCard(
                  status: 'Sakit',
                  records: const [
                    {'student_id': 1, 'name': 'Ali'},
                    {'student_id': 1, 'name': 'Ali'},
                    {'student_id': 2, 'name': 'Hasan'},
                  ],
                ),
                StudentStatusCard(
                  status: 'Izin',
                  records: const [
                    {'student_id': 2, 'name': 'Hasan'},
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('2 santri • 3 catatan pada periode terpilih'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('search-Sakit')), 'Ali');
    await tester.pumpAndSettle();
    expect(find.text('2×'), findsOneWidget);
    expect(
      find.text('2 santri • 3 catatan pada periode terpilih'),
      findsOneWidget,
    );
    expect(
      find.text('Hasan'),
      findsOneWidget,
      reason: 'the Izin list remains unchanged',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'interactive charts handle zero counts and large text on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  AttendanceChart(
                    counts: {'Hadir': 8, 'Izin': 2, 'Sakit': 0, 'Alpha': 0},
                  ),
                  SizedBox(height: 12),
                  AttendanceTrend(
                    months: {
                      '2026-10': {'Hadir': 0, 'total': 0},
                      '2026-11': {'Hadir': 8, 'total': 10},
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Izin 2'));
      await tester.pumpAndSettle();
      expect(find.text('20.0%'), findsOneWidget);
      await tester.ensureVisible(find.text('10'));
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      expect(find.text('2026-10 • 0 hadir / 0 catatan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('server rankings request each status and use complete totals', (
    tester,
  ) async {
    final auth = AuthController()
      ..token = 'test'
      ..user = {'id': 1};
    final statuses = <String>{};
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: auth,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: StudentRankings(
                    module: 'Formal',
                    days: 30,
                    onStudent: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(statuses, {'alpha', 'izin', 'sakit'});
        expect(
          find.text('25 santri • 100 catatan dalam periode ini'),
          findsNWidgets(3),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient((request) async {
        final status = request.url.queryParameters['status']!;
        statuses.add(status);
        expect(request.url.queryParameters['threshold'], '1');
        return http.Response(
          jsonEncode({
            'data': [
              {'student_id': 2, 'name': 'Ali', 'count': 8},
            ],
            'status': status,
            'threshold': 1,
            'total_students': 25,
            'total_records': 100,
            'has_more': true,
          }),
          200,
        );
      }),
    );
    auth.dispose();
  });

  testWidgets(
    'profile module filtering recalculates counts without another request',
    (tester) async {
      final auth = AuthController()
        ..token = 'test'
        ..user = {'id': 1};
      int requests = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: auth,
              child: MaterialApp(
                theme: AppTheme.light,
                home: const StudentProgressScreen(studentId: 1),
              ),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Formal').first);
          await tester.tap(find.text('Formal').first);
          await tester.pumpAndSettle();
          expect(find.text('2 catatan dalam 30 hari'), findsOneWidget);
          expect(requests, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'student': {
                'id': 1,
                'nama_lengkap': 'Ali',
                'kelas': {'nama': 'A', 'tingkat': 'VII'},
              },
              'modules': ['Formal', 'Halaqoh'],
              'counts': [
                {
                  'date': '2026-11-01',
                  'module': 'Formal',
                  'status': 'hadir',
                  'count': 2,
                },
                {
                  'date': '2026-11-01',
                  'module': 'Halaqoh',
                  'status': 'alpa',
                  'count': 3,
                },
              ],
              'history': [],
            }),
            200,
          );
        }),
      );
      auth.dispose();
    },
  );
}
