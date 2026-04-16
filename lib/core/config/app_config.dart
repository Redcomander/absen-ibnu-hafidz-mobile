import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

class AppConfig {
  // Public production host for Play Store/release builds.
  static const String _productionBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: 'https://beta.ibnuhafidz.ponpes.id',
  );

  // LAN fallback used for physical devices on same WiFi.
  static const String _lanBaseUrl = String.fromEnvironment(
    'LAN_BASE_URL',
    defaultValue: 'http://192.168.0.34:8080',
  );

  // Auto-switch target backend host by runtime platform.
  static String get baseUrl {
    if (kReleaseMode) {
      return _productionBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:8080';
    }

    if (Platform.isAndroid) {
      // Android emulator maps host machine localhost to 10.0.2.2.
      return const String.fromEnvironment(
        'ANDROID_DEBUG_BASE_URL',
        defaultValue: 'http://10.0.2.2:8080',
      );
    }

    if (Platform.isIOS) {
      return _lanBaseUrl;
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return 'http://127.0.0.1:8080';
    }

    return _productionBaseUrl;
  }

  static const String apiPrefix = '/api';
}
