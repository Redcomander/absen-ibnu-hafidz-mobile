// Disposable emulator build only; never connects to production.
import 'package:flutter/material.dart';
import 'package:ibnu_schedule_alerts/ibnu_schedule_alerts.dart';
import 'package:ibnu_hafidz_flutter/core/config/app_config.dart';
import 'package:ibnu_hafidz_flutter/core/notifications/schedule_alerts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.baseUrl != 'http://10.0.2.2:18089') {
    throw StateError('Local emulator test only');
  }
  const account = 'http://10.0.2.2:18089|901';
  final now = campusNow();
  String time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';
  Map<String, Object?> row(int id, int endSeconds) => {
    'key': 'smoke-$id',
    'date': campusDate(now),
    'time': time(now.subtract(const Duration(minutes: 5))),
    'endTime': time(now.add(Duration(seconds: endSeconds))),
    'class': 'VII A SMP',
    'lesson': 'EXPIRY TEST $id',
    'repeatWeekly': false,
    'substitute': false,
  };
  await ScheduleAlertBridge.call<Object?>('bind', {
    'account': account,
    'enabled': true,
  });
  await ScheduleAlertBridge.call<Object?>('replace', {
    'account': account,
    'lessons': [row(1, -10), row(2, 20), row(3, 40)],
  });
  runApp(const MaterialApp(
    home: Scaffold(body: Center(child: Text('LOCAL EXPIRY TEST'))),
  ));
}
