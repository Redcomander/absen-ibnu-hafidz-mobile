import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ibnu_hafidz_flutter/features/settings/app_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('uses any network sync by default', () {
    final controller = AppSettingsController();

    expect(controller.syncMode, 'any_network');
  });
}
