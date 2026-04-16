// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ibnu_hafidz_flutter/core/network/api_client.dart';
import 'package:ibnu_hafidz_flutter/features/auth/auth_controller.dart';
import 'package:ibnu_hafidz_flutter/features/home/home_shell.dart';
import 'package:ibnu_hafidz_flutter/features/settings/app_settings_controller.dart';
import 'package:ibnu_hafidz_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('extracts download filename from response headers', () {
    expect(
      ApiClient.extractFilenameFromDisposition(
        'attachment; filename=rekap_guru_formal.pdf',
      ),
      'rekap_guru_formal.pdf',
    );
    expect(
      ApiClient.extractFilenameFromDisposition(
        'attachment; filename="Rekapan_Halaqoh_Guru_2026-04-01_2026-04-15.pdf"',
      ),
      'Rekapan_Halaqoh_Guru_2026-04-01_2026-04-15.pdf',
    );
    expect(ApiClient.extractFilenameFromDisposition(null), isNull);
  });

  testWidgets('shows login screen when no session is saved',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const IbnuHafidzApp());
    await tester.pumpAndSettle();

    expect(find.text('Selamat Datang'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
  });

  testWidgets('hides stats tab when user lacks stats permissions',
      (WidgetTester tester) async {
    final auth = AuthController()
      ..isLoading = false
      ..isAuthenticated = true
      ..user = {
        'name': 'Guru',
        'roles': [
          {'name': 'teacher', 'permissions': []}
        ],
      };

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<AppSettingsController>(
            create: (_) => AppSettingsController(),
          ),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stats'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('shows stats tab when user has stats permission',
      (WidgetTester tester) async {
    final auth = AuthController()
      ..isLoading = false
      ..isAuthenticated = true
      ..user = {
        'name': 'Admin',
        'roles': [
          {
            'name': 'teacher',
            'permissions': [
              {'name': 'absensi.view'}
            ]
          }
        ],
      };

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<AppSettingsController>(
            create: (_) => AppSettingsController(),
          ),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stats'), findsOneWidget);
  });
}
