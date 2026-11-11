import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/network/api_client.dart';
import 'package:ibnu_hafidz_flutter/features/auth/auth_controller.dart';
import 'package:ibnu_hafidz_flutter/features/halaqoh/membership_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    ApiClient.refreshAuthToken = null;
    ApiClient.queueOfflineWrite = null;
  });

  test('membership requests are restricted to the original teacher', () {
    expect(canRequestHalaqohMembership({'id': 7}, 7), isTrue);
    expect(canRequestHalaqohMembership({'id': 8}, 7), isFalse);
    expect(canRequestHalaqohMembership(null, 7), isFalse);
    expect(
      canRequestHalaqohMembership({
        'id': 7,
        'roles': [
          {'name': 'admin'},
        ],
      }, 7),
      isFalse,
    );
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pumpAndSettle();
  }

  for (final pending in [false, true]) {
    testWidgets(
      pending
          ? 'pending request locks roster and displays admin feedback'
          : 'add and remove sends one approval request retaining the helper',
      (tester) async {
        final auth = AuthController()
          ..token = 'test-token'
          ..user = {'id': 7};
        final writes = <Map<String, dynamic>>[];
        var sent = false;
        var optionCalls = 0;
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              ChangeNotifierProvider.value(
                value: auth,
                child: const MaterialApp(
                  home: HalaqohMembershipScreen(teacherId: 7),
                ),
              ),
            );
            await settle(tester);
            if (pending) {
              expect(find.byType(TextField), findsNothing);
              expect(
                find.text(
                  'Tunggu tanggapan admin sebelum membuat pengajuan berikutnya.',
                ),
                findsOneWidget,
              );
              await tester.tap(find.text('Riwayat pengajuan'));
              await tester.pumpAndSettle();
              expect(find.textContaining('Perlu ditinjau'), findsOneWidget);
            } else {
              await tester.tap(
                find.byTooltip('Keluarkan dari pengajuan').first,
              );
              await tester.pumpAndSettle();
              await tester.ensureVisible(find.byType(TextField));
              await tester.enterText(find.byType(TextField), 'Sa');
              await tester.pump(const Duration(milliseconds: 450));
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 500)),
              );
              await settle(tester);
              expect(optionCalls, 1);
              await tester.ensureVisible(find.text('Santri Baru'));
              await tester.tap(find.text('Santri Baru'));
              await tester.pumpAndSettle();
              final submit = find.text('Ajukan perubahan (+1 / -1)');
              await tester.ensureVisible(submit);
              await tester.tap(submit);
              await tester.pumpAndSettle();
              expect(find.text('Kirim pengajuan perubahan?'), findsOneWidget);
              await tester.tap(find.text('Kirim'));
              await settle(tester);
              expect(writes, hasLength(1));
              expect(writes.single['user_id'], 7);
              expect(writes.single['student_ids'], [12, 13]);
              expect(writes.single['helper_teacher_id'], 9);
              expect(find.byType(TextField), findsNothing);
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
          () => MockClient((request) async {
            if (request.method == 'PUT') {
              expect(request.url.path, '/api/halaqoh/assignments/7');
              writes.add(jsonDecode(request.body) as Map<String, dynamic>);
              sent = true;
              return http.Response('{"request_id":21}', 202);
            }
            if (request.url.path.endsWith('assignment-change-requests')) {
              return http.Response(
                jsonEncode({
                  'data': pending || sent
                      ? [
                          {
                            'id': 21,
                            'teacher_id': 7,
                            'status': 'pending',
                            'reason': 'Perlu ditinjau',
                          },
                        ]
                      : [],
                }),
                200,
              );
            }
            if (request.url.path.endsWith('student-options')) {
              optionCalls++;
              expect(request.url.queryParameters['search'], 'Sa');
              expect(request.url.queryParameters['per_page'], '20');
              return http.Response(
                '{"data":[{"id":13,"nama_lengkap":"Santri Baru"}]}',
                200,
              );
            }
            expect(request.url.path, '/api/halaqoh/assignments');
            return http.Response(
              jsonEncode({
                'groups': [
                  {
                    'teacher_id': 7,
                    'assignments': [
                      {
                        'student_id': 11,
                        'helper_teacher_id': 9,
                        'student': {'nama_lengkap': 'Santri Awal'},
                      },
                      {
                        'student_id': 12,
                        'helper_teacher_id': 9,
                        'student': {'nama_lengkap': 'Santri Tetap'},
                      },
                    ],
                  },
                ],
              }),
              200,
            );
          }),
        );
        auth.dispose();
      },
    );
  }

  testWidgets('failed online roster never enables a stale membership write', (
    tester,
  ) async {
    final auth = AuthController()
      ..token = 'test-token'
      ..user = {'id': 7};
    var writes = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: auth,
            child: const MaterialApp(
              home: HalaqohMembershipScreen(teacherId: 7),
            ),
          ),
        );
        await settle(tester);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Coba muat ulang'), findsOneWidget);
        expect(writes, 0);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient((request) async {
        if (request.method != 'GET') writes++;
        throw http.ClientException('offline');
      }),
    );
    auth.dispose();
  });
  testWidgets(
    'server roster changes stop an old draft from replacing new members',
    (tester) async {
      final auth = AuthController()
        ..token = 'test-token'
        ..user = {'id': 7};
      var rosterReads = 0, writes = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: auth,
              child: const MaterialApp(
                home: HalaqohMembershipScreen(teacherId: 7),
              ),
            ),
          );
          await settle(tester);
          await tester.tap(find.byTooltip('Keluarkan dari pengajuan'));
          await tester.pumpAndSettle();
          final submit = find.text('Ajukan perubahan (+0 / -1)');
          await tester.ensureVisible(submit);
          await tester.tap(submit);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Kirim'));
          await settle(tester);
          expect(writes, 0);
          expect(rosterReads, 2);
          expect(
            find.textContaining('telah berubah di server'),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (request.method != 'GET') {
            writes++;
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('assignment-change-requests')) {
            return http.Response('{"data":[]}', 200);
          }
          rosterReads++;
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'teacher_id': 7,
                  'assignments': [
                    {
                      'student_id': 11,
                      'student': {'nama_lengkap': 'Santri Awal'},
                    },
                    if (rosterReads > 1)
                      {
                        'student_id': 12,
                        'student': {'nama_lengkap': 'Baru disetujui admin'},
                      },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      auth.dispose();
    },
  );
}
