import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/network/offline_cache_store.dart';
import 'package:ibnu_hafidz_flutter/core/network/sync_store.dart';
import 'package:ibnu_hafidz_flutter/features/auth/auth_controller.dart';
import 'package:ibnu_hafidz_flutter/features/home/user_dashboard.dart';
import 'package:ibnu_hafidz_flutter/features/halaqoh/review_screen.dart';
import 'package:ibnu_hafidz_flutter/features/settings/user_preferences.dart';
import 'package:ibnu_hafidz_flutter/features/settings/app_lock_gate.dart';
import 'package:ibnu_hafidz_flutter/features/settings/storage_screen.dart';
import 'package:ibnu_hafidz_flutter/features/stats/saved_report_filters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'cache cleanup preserves queue, schedules, forms, other accounts and fresh reports',
    () async {
      final account = SyncStore.account(71), other = SyncStore.account(72);
      OfflineCacheStore.scope = account;
      final action = await SyncStore.instance.enqueue(account, '/attendance', {
        'records': [
          {'student_id': 5, 'status': 'hadir'},
        ],
      }, 'json');
      final prefs = await SharedPreferences.getInstance();
      final old = jsonEncode({
        'saved_at': '2020-01-01',
        'payload': {'value': 'retained'},
      });
      for (final path in [
        '/schedules',
        '/attendance',
        '/halaqoh/attendance/3',
      ]) {
        await prefs.setString(
          OfflineCacheStore.buildKey(path, account: account),
          old,
        );
      }
      final report = OfflineCacheStore.buildKey(
        '/attendance/history',
        account: account,
      );
      await prefs.setString(report, old);
      final otherReport = OfflineCacheStore.buildKey(
        '/attendance/history',
        account: other,
      );
      await prefs.setString(otherReport, old);
      await OfflineCacheStore.write('/attendance/statistics', {
        'hadir': 3,
      }, account: account);
      final removed = await CacheManagement.clearReports(
        account,
        before: DateTime(2025),
      );
      expect(removed, 1);
      expect(prefs.containsKey(report), false);
      expect(prefs.containsKey(otherReport), true);
      for (final path in [
        '/schedules',
        '/attendance',
        '/halaqoh/attendance/3',
      ]) {
        expect(
          prefs.containsKey(OfflineCacheStore.buildKey(path, account: account)),
          true,
        );
      }
      expect(
        await OfflineCacheStore.read(
          '/attendance/statistics',
          account: account,
        ),
        isNotNull,
      );
      expect(
        await SyncStore.instance.body(account, action),
        contains('student_id'),
      );
    },
  );
  test(
    'account display settings and lock survive restart without crossing accounts',
    () async {
      var success = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            UserPreferences.device,
            (call) async => success,
          );
      final prefs = UserPreferences()..bind(81);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.ready, true);
      expect(await prefs.setLock(true), false);
      expect(prefs.lockEnabled, false);
      await prefs.setScale(1.4);
      await prefs.setContrast(true);
      success = true;
      expect(await prefs.setLock(true), true);
      prefs.lock();
      expect(prefs.locked, true);
      success = false;
      await prefs.unlock();
      expect(prefs.locked, true);
      success = true;
      await prefs.unlock();
      expect(prefs.locked, false);
      prefs.bind(82);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.textScale, 1);
      expect(prefs.lockEnabled, false);
      expect(prefs.highContrast, false);
      prefs.bind(81);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.textScale, 1.4);
      expect(prefs.highContrast, true);
      expect(prefs.locked, true);
      prefs.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(UserPreferences.device, null);
    },
  );
  testWidgets(
    'dashboard uses web monthly stats and displays both personal timetable modules',
    (tester) async {
      final auth = AuthController()
        ..token = 'test'
        ..user = {
          'id': 91,
          'roles': [
            {
              'name': 'teacher',
              'permissions': [
                {'name': 'dashboard.view'},
              ],
            },
          ],
        };
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: auth,
              child: MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: UserDashboard(onOpenSchedule: () {}),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pumpAndSettle();
          expect(find.text('80%'), findsOneWidget);
          expect(find.text('Fiqih'), findsOneWidget);
          expect(find.text('Nahwu'), findsOneWidget);
          expect(find.text('Ramadhan test'), findsNothing);
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/feature-flags/ramadhan')) {
            return http.Response('{"is_enabled":false}', 200);
          }
          expect(request.url.path, '/api/dashboard/stats');
          expect(
            request.url.queryParameters.keys,
            containsAll(['month', 'year']),
          );
          return http.Response(
            jsonEncode({
              'teacher': {
                'teacher_recap': {'percentage': 80, 'hadir': 8, 'total': 10},
                'personal_schedule': [
                  {
                    'start_time': '07:00',
                    'assignment': {
                      'lesson': {'name': 'Fiqih'},
                    },
                  },
                  {
                    'start_time': '06:00',
                    'type': 'ramadhan',
                    'assignment': {
                      'lesson': {'name': 'Ramadhan test'},
                    },
                  },
                ],
                'personal_diniyyah_schedule': [
                  {
                    'start_time': '08:00',
                    'assignment': {
                      'diniyyah_lesson': {'name': 'Nahwu'},
                    },
                  },
                ],
              },
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
  testWidgets('teacher cannot load administrator review requests', (
    tester,
  ) async {
    final auth = AuthController()
      ..user = {
        'id': 1,
        'roles': [
          {'name': 'teacher'},
        ],
      };
    var calls = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: auth,
            child: const MaterialApp(home: HalaqohReviewScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Hanya admin yang dapat meninjau pengajuan.'),
          findsOneWidget,
        );
        expect(calls, 0);
      },
      () => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets(
    'approval explicitly confirms transfers and rejection requires a reason',
    (tester) async {
      final auth = AuthController()
        ..token = 'reviewer'
        ..user = {
          'id': 7,
          'roles': [
            {'name': 'admin'},
          ],
        };
      var approved = false, posts = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: auth,
              child: const MaterialApp(home: HalaqohReviewScreen()),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Tolak').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Tolak').last);
          await tester.pumpAndSettle();
          expect(find.text('Wajib diisi'), findsOneWidget);
          expect(posts, 0);
          await tester.tap(find.text('Batal'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Setujui').first);
          await tester.pumpAndSettle();
          expect(
            find.textContaining('1 santri akan dipindahkan'),
            findsOneWidget,
          );
          expect(posts, 0);
          await tester.tap(find.text('Setujui').last);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pumpAndSettle();
          expect(posts, 1);
          expect(approved, true);
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            expect(jsonDecode(request.body), {'confirm_transfers': true});
            expect(
              request.url.path,
              '/api/halaqoh/assignment-change-requests/1/approve',
            );
            approved = true;
            return http.Response('{}', 200);
          }
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 1,
                  'teacher_id': 7,
                  'teacher': {'name': 'Guru'},
                  'status': approved ? 'approved' : 'pending',
                  'student_ids': [2],
                  'student_owner_snapshot': {'2': 9},
                  'student_details': [
                    {'id': 2, 'nama_lengkap': 'Santri'},
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
  testWidgets(
    'application lock covers pushed routes and preserves their state',
    (tester) async {
      final prefs = UserPreferences()..lockEnabled = true;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: prefs,
          child: MaterialApp(
            builder: (context, child) => AppLockGate(child: child!),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const Scaffold(body: Text('Private student page')),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Private student page'), findsOneWidget);
      prefs.lock();
      await tester.pumpAndSettle();
      expect(find.text('Private student page'), findsNothing);
      expect(find.text('Aplikasi terkunci'), findsOneWidget);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(UserPreferences.device, (_) async => true);
      await prefs.unlock();
      await tester.pumpAndSettle();
      expect(find.text('Private student page'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      prefs.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(UserPreferences.device, null);
    },
  );
  testWidgets('saved filter restores complete filter values after recreation', (
    tester,
  ) async {
    OfflineCacheStore.scope = SyncStore.account(99);
    Map<String, dynamic>? applied;
    Widget page() => MaterialApp(
      home: Scaffold(
        body: SavedReportFilters(
          report: 'test',
          capture: () => {
            'teacher': '7',
            'kelas': '3',
            'start': '2026-11-01',
            'search': 'Ahmad',
          },
          apply: (v) => applied = v,
        ),
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan filter saat ini'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Laporan bulanan');
    await tester.tap(find.text('Simpan').last);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laporan bulanan'));
    expect(applied, {
      'teacher': '7',
      'kelas': '3',
      'start': '2026-11-01',
      'search': 'Ahmad',
    });
  });
}
