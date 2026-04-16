// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ibnu_hafidz_flutter/core/network/api_client.dart';
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
}
