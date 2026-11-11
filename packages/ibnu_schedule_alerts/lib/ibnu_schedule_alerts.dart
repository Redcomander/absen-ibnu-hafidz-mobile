import 'package:flutter/services.dart';

class ScheduleAlertBridge {
  static const channel = MethodChannel('ibnu_hafidz/schedule_alerts');
  static Future<T?> call<T>(String method, [Object? arguments]) =>
      channel.invokeMethod<T>(method, arguments);
}
