import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

class AppConfig {
  // Shared public host for phone test builds and release builds.
  static const String _productionBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: 'https://ibnuhafidz.ponpes.id',
  );

  // LAN fallback used for physical devices on same WiFi.
  static const String _lanBaseUrl = String.fromEnvironment(
    'LAN_BASE_URL',
    defaultValue: _productionBaseUrl,
  );

  // Auto-switch target backend host by runtime platform.
  static String get baseUrl {
    if (kReleaseMode) {
      return _productionBaseUrl;
    }

    if (kIsWeb) {
      return _productionBaseUrl;
    }

    if (Platform.isAndroid) {
      // Local emulator access is opt-in through ANDROID_DEBUG_BASE_URL.
      return const String.fromEnvironment(
        'ANDROID_DEBUG_BASE_URL',
        defaultValue: _productionBaseUrl,
      );
    }

    if (Platform.isIOS) {
      return _lanBaseUrl;
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _productionBaseUrl;
    }

    return _productionBaseUrl;
  }

  static const String apiPrefix = '/api';
}
