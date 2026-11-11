import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/network/offline_cache_store.dart';
import 'package:ibnu_hafidz_flutter/core/network/sync_store.dart';
import 'package:ibnu_hafidz_flutter/core/theme/app_theme.dart';
import 'package:ibnu_hafidz_flutter/core/theme/attendance_widgets.dart';
import 'package:ibnu_hafidz_flutter/features/auth/auth_controller.dart';
import 'package:ibnu_hafidz_flutter/features/halaqoh/request_review_card.dart';
import 'package:ibnu_hafidz_flutter/features/jadwal/jadwal_screen.dart';
import 'package:ibnu_hafidz_flutter/features/jadwal/schedule_target.dart';
import 'package:ibnu_hafidz_flutter/features/settings/app_settings_controller.dart';

void main() {
  test('roster changes follow add, replace and removal server semantics', () {
    final request = <String, dynamic>{
      'previous_student_ids': [1, 2],
      'student_ids': [2, 3],
    };
    var change = halaqohRosterChange({...request, 'request_type': 'create'});
    expect(change.added, {'3'});
    expect(change.removed, isEmpty);
    change = halaqohRosterChange({...request, 'request_type': 'update'});
    expect(change.added, {'3'});
    expect(change.removed, {'1'});
    change = halaqohRosterChange({
      ...request,
      'request_type': 'delete_single',
      'student_ids': [2],
    });
    expect(change.after, {'1'});
    change = halaqohRosterChange({...request, 'request_type': 'delete_all'});
    expect(change.after, isEmpty);
    expect(change.removed, {'1', '2'});
  });

  test('month names are Indonesian and schedule IDs retain their module', () {
    expect(indonesianMonthYear(DateTime(2026, 11)), 'November/2026');
    expect(indonesianMonthYear(DateTime(2027, 1)), 'Januari/2027');
    expect(
      ScheduleTarget.fromDashboard({'id': '42', 'module': 'Diniyyah'})?.type,
      'diniyyah',
    );
    expect(
      ScheduleTarget.fromDashboard({'id': 42, 'module': 'Formal'})?.id,
      42,
    );
    expect(ScheduleTarget.fromDashboard({'id': null}), isNull);
  });

  testWidgets(
    'review and attendance choices fit narrow screens with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    HalaqohRequestCard(
                      request: {
                        'id': 1,
                        'teacher_id': 8,
                        'status': 'pending',
                        'request_type': 'update',
                        'teacher': {'name': 'Ustadz dengan nama yang panjang'},
                        'previous_student_ids': [1],
                        'student_ids': [2],
                        'student_details': [
                          {'id': 2, 'nama_lengkap': 'Santri baru'},
                        ],
                        'previous_student_details': [
                          {'id': 1, 'nama_lengkap': 'Santri sebelumnya'},
                        ],
                      },
                      busy: false,
                      onReview: (_) {},
                    ),
                    AttendanceStatusPicker(
                      value: 'Hadir',
                      teacher: true,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ditambahkan (1)'), findsOneWidget);
      expect(find.text('Dikeluarkan dari halaqoh (1)'), findsOneWidget);
      expect(find.text('Dinas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard selection opens the exact cached Diniyyah card first',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        await SyncStore.instance.database;
      });
      OfflineCacheStore.scope = SyncStore.account(13);
      final today = DateTime.now().toIso8601String().split('T').first;
      await tester.runAsync(
        () => OfflineCacheStore.write(
          '/schedules',
          {
            'data': List.generate(
              100,
              (i) => {
                'id': i + 1,
                'day': 'Senin',
                'start_time': '08:00',
                'end_time': '09:00',
                'assignment': {
                  'diniyyah_lesson': {
                    'name': i == 98 ? 'Nahwu tujuan' : 'Pelajaran $i',
                  },
                  'kelas': {'nama': 'VII', 'tingkat': 'A'},
                },
              },
            ),
          },
          query: {'type': 'diniyyah', 'date': today},
        ),
      );
      final auth = AuthController()
        ..token = 'test'
        ..user = {'id': 13, 'roles': []};
      final settings = AppSettingsController(
        background: true,
        networkCheck: () async => [ConnectivityResult.none],
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: JadwalScreen(
                target: ScheduleTarget(id: 99, type: 'diniyyah'),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nahwu tujuan'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Nahwu tujuan')).dy, lessThan(500));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      settings.dispose();
    },
  );
}
