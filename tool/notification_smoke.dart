// Isolated Android-only notification harness. Never contacts production.
import 'package:flutter/material.dart';
import 'package:ibnu_schedule_alerts/ibnu_schedule_alerts.dart';
import 'package:ibnu_hafidz_flutter/core/config/app_config.dart';
import 'package:ibnu_hafidz_flutter/core/notifications/schedule_alerts.dart';

const account = 'http://10.0.2.2:18089|901';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.baseUrl != 'http://10.0.2.2:18089') {
    throw StateError('Isolated notification smoke only.');
  }
  await ScheduleAlerts.instance.bind(account);
  await seed();
  runApp(const MaterialApp(home: Smoke()));
}

Future<void> seed() async {
  final now = campusNow();
  final start = now.add(const Duration(minutes: 31));
  const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Ahad'];
  Map<String, Object?> row(int id, DateTime at) => {
    'id': id,
    'day': days[at.weekday - 1],
    'start_time':
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:${at.second.toString().padLeft(2, '0')}',
    'assignment': {
      'teacher': {'id': 901},
      'lesson': {'name': 'SMOKE Lesson $id'},
      'kelas': {'nama': 'TEST ONLY'},
    },
  };
  ScheduleAlerts.instance.accept(account, 'formal', campusDate(now), {
    'data': [
      row(901, start),
      row(902, DateTime.utc(now.year, now.month, now.day, 8)),
    ],
  });
  await ScheduleAlerts.instance.publish();
}

class Smoke extends StatelessWidget {
  const Smoke({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LOCAL ALERT SMOKE')),
    body: ListView(
      children: [
        TextButton(onPressed: seed, child: const Text('Seed schedules')),
        TextButton(
          onPressed: () async {
            await ScheduleAlerts.instance.setEnabled(false);
          },
          child: const Text('Disable alerts'),
        ),
        TextButton(
          onPressed: () async {
            await ScheduleAlerts.instance.bind(null);
          },
          child: const Text('Logout'),
        ),
        TextButton(
          onPressed: () async {
            await ScheduleAlertBridge.call<Object?>('restore');
          },
          child: const Text('Restore alarms'),
        ),
      ],
    ),
  );
}
