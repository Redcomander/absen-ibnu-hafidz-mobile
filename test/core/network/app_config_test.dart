import 'package:flutter_test/flutter_test.dart';
import 'package:ibnu_hafidz_flutter/core/config/app_config.dart';

void main() {
  test('uses working public host unless explicitly overridden', () {
    const expected = String.fromEnvironment('APP_BASE_URL',
        defaultValue: 'https://ibnuhafidz.ponpes.id');
    expect(AppConfig.baseUrl, expected);
    expect('${AppConfig.baseUrl}${AppConfig.apiPrefix}/schedules',
        '$expected/api/schedules');
  });
}
