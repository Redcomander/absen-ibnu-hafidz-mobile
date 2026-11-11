import 'dart:async';
import 'dart:convert';

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
import 'package:ibnu_hafidz_flutter/features/jadwal/jadwal_screen.dart';
import 'package:ibnu_hafidz_flutter/features/settings/app_settings_controller.dart';

void main() {
  setUpAll(() async {
    await SyncStore.instance.database;
  });
  testWidgets('large timetables build only visible lesson cards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    OfflineCacheStore.scope = SyncStore.account(1);
    final today = DateTime.now().toIso8601String().split('T').first;
    final rows = List.generate(
      1000,
      (id) => {
        'id': id + 1,
        'day': 'Senin',
        'start_time': '08:00',
        'end_time': '09:00',
        'assignment': {
          'lesson': {'name': 'Lesson $id'},
          'teacher': {'id': 1},
          'kelas': {'nama': 'VII A'},
        },
      },
    );
    await tester.runAsync(
      () => OfflineCacheStore.write(
        '/schedules',
        {'data': rows},
        query: {'type': 'formal', 'date': today},
      ),
    );
    final auth = AuthController()
      ..token = 'test'
      ..user = {'id': 1, 'roles': []};
    final settings = AppSettingsController(
      background: true,
      networkCheck: () async => [ConnectivityResult.none],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<AppSettingsController>.value(value: settings),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: JadwalScreen()),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    final built = find
        .textContaining(RegExp(r'^Lesson [0-9]+$'))
        .evaluate()
        .length;
    expect(
      built,
      lessThan(20),
      reason: '1000 data rows must not create 1000 card subtrees',
    );
    expect(find.text('Lesson 999'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    settings.dispose();
  });

  testWidgets(
    'saved schedules stay visible while the network request hangs and search works locally',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      OfflineCacheStore.scope = SyncStore.account(1);
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final today = DateTime.now().toIso8601String().split('T').first;
      final rows = [
        {
          'id': 1,
          'day': 'Senin',
          'start_time': '08:00',
          'end_time': '09:00',
          'assignment': {
            'lesson': {'name': 'Fiqih Offline'},
            'teacher': {'id': 1, 'name': 'Guru'},
            'kelas': {'nama': 'VII A', 'gender': 'banin'},
          },
        },
      ];
      await tester.runAsync(
        () => OfflineCacheStore.write(
          '/schedules',
          {'data': rows},
          query: {'type': 'formal', 'date': today},
        ),
      );
      final response = Completer<http.Response>();
      var calls = 0;
      final auth = AuthController()
        ..token = 'test'
        ..user = {'id': 1, 'roles': []};
      final settings = AppSettingsController(
        background: true,
        networkCheck: () async => [ConnectivityResult.wifi],
      );
      try {
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
                child: MaterialApp(
                  theme: AppTheme.light,
                  home: const Scaffold(body: JadwalScreen()),
                ),
              ),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)),
            );
            await tester.pump();
            expect(find.text('Fiqih Offline'), findsOneWidget);
            expect(find.byType(LinearProgressIndicator), findsOneWidget);
            expect(calls, 1);
            await tester.enterText(find.byType(TextField).first, 'tidak cocok');
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.text('Fiqih Offline'), findsNothing);
            expect(
              calls,
              1,
              reason: 'search must not need another network request',
            );
            await tester.enterText(find.byType(TextField).first, 'fiqih');
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.text('Fiqih Offline'), findsOneWidget);
            expect(calls, 1);
            response.complete(http.Response(jsonEncode(rows), 200));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
          () => MockClient((_) async {
            calls++;
            return response.future;
          }),
        );
      } finally {
        if (!response.isCompleted) response.complete(http.Response('[]', 200));
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        settings.dispose();
      }
    },
  );

  testWidgets(
    'cached roster opens immediately and a late response preserves typed edits',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      OfflineCacheStore.scope = SyncStore.account(1);
      tester.view.physicalSize = const Size(400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final date = DateTime.now().toIso8601String().split('T').first;
      final roster = {
        'students': [
          {
            'student_id': 5,
            'student_name': 'Santri Percobaan',
            'status': 'hadir',
          },
        ],
        'materi': 'Materi tersimpan',
      };
      final schedules = [
        {
          'id': 1,
          'day': 'Senin',
          'start_time': '08:00',
          'end_time': '09:00',
          'assignment': {
            'lesson': {'name': 'Fiqih'},
            'teacher': {'id': 1},
            'kelas': {'nama': 'VII'},
          },
        },
      ];
      await tester.runAsync(
        () => OfflineCacheStore.write(
          '/schedules',
          {'data': schedules},
          query: {'type': 'formal', 'date': date},
        ),
      );
      await tester.runAsync(
        () => OfflineCacheStore.write(
          '/attendance',
          roster,
          query: {'type': 'formal', 'jadwal_id': '1', 'date': date},
        ),
      );
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
      final response = Completer<http.Response>();
      try {
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
                child: MaterialApp(
                  theme: AppTheme.light,
                  home: const Scaffold(body: JadwalScreen()),
                ),
              ),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump(const Duration(milliseconds: 100));
            await tester.ensureVisible(find.text('Absensi santri'));
            await tester.tap(find.text('Absensi santri'));
            await tester.pump();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump(const Duration(milliseconds: 400));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump();
            expect(find.text('Santri Percobaan'), findsOneWidget);
            final material = find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText ==
                      'Materi jurnal mengajar (wajib)',
            );
            await tester.enterText(material, 'Materi sedang diketik');
            response.complete(
              http.Response(
                jsonEncode({...roster, 'materi': 'Respons lama server'}),
                200,
              ),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pumpAndSettle();
            expect(
              tester.widget<TextField>(material).controller!.text,
              'Materi sedang diketik',
            );
            expect(tester.takeException(), isNull);
          },
          () => MockClient((request) async {
            if (request.url.path.endsWith('/attendance')) {
              return response.future;
            }
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'day': 'Senin',
                  'start_time': '08:00',
                  'end_time': '09:00',
                  'assignment': {
                    'lesson': {'name': 'Fiqih'},
                    'teacher': {'id': 1},
                    'kelas': {'nama': 'VII'},
                  },
                },
              ]),
              200,
            );
          }),
        );
      } finally {
        if (!response.isCompleted) {
          response.complete(http.Response(jsonEncode(roster), 200));
        }
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        settings.dispose();
      }
    },
  );
}
