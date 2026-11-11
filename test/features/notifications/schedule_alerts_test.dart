import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibnu_hafidz_flutter/core/notifications/schedule_alerts.dart';
import 'package:ibnu_hafidz_flutter/core/network/sync_store.dart';
import 'package:ibnu_schedule_alerts/ibnu_schedule_alerts.dart';

Map<String, Object?> lesson(
  int id, {
  int teacher = 1,
  int? substitute,
  String? date,
  String day = 'Selasa',
  String time = '08:00:00',
}) => {
  'id': id,
  'day': day,
  'start_time': time,
  'assignment': {
    'teacher': {'id': teacher},
    'lesson': {'name': 'Fiqih'},
    'kelas': {'nama': 'VII A'},
  },
  if (substitute != null) 'substitute_teacher': {'id': substitute},
  'substitute_date': ?date,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 10, 0);
  List<Map<String, Object?>> plan(
    List rows, {
    String account = 'api|1',
    String snapshot = '2026-11-10',
  }) => planScheduleAlerts(account, {
    'formal': ScheduleSnapshot(snapshot, rows),
  }, now: now);

  test('only assigned teacher and valid substitute receive reminders', () {
    final result = plan([
      lesson(1),
      lesson(2, teacher: 2),
      lesson(3, teacher: 2, substitute: 1, date: '2026-11-10T00:00:00Z'),
      lesson(4, teacher: 2, substitute: 1, date: '2026-11-03'),
    ]);
    expect(result.map((r) => r['key']), [
      'formal:1:2026-11-10',
      'formal:3:2026-11-10',
    ]);
    expect(result.last['substitute'], true);
    expect(result.first['repeatWeekly'], true);
    expect(result.last['repeatWeekly'], false);
  });
  test(
    'class and sub-class precede level and include normalized finish time',
    () {
      final row = lesson(1);
      row['end_time'] = '09:30';
      (row['assignment'] as Map)['kelas'] = {
        'nama': 'VII',
        'sub_kelas': 'A',
        'tingkat': 'SMP',
      };
      final planned = plan([row]).single;
      expect(planned['class'], 'VII A, SMP');
      expect(planned['time'], '08:00:00');
      expect(planned['endTime'], '09:30:00');
      row['end_time'] = '99:00';
      expect(plan([row]), isEmpty);
    },
  );

  test('undated substitutions only apply to the downloaded date', () {
    expect(
      plan([lesson(1, teacher: 2, substitute: 1)], snapshot: '2026-11-03'),
      isEmpty,
    );
    expect(plan([lesson(1, teacher: 2, substitute: 1)]).length, 1);
  });
  test('today follows Jakarta midnight regardless of phone timezone', () {
    final result = planScheduleAlerts('api|1', {
      'formal': ScheduleSnapshot('2026-11-10', [lesson(1, time: '00:15')]),
    }, now: DateTime.utc(2026, 11, 9, 17, 1));
    expect(result.single['date'], '2026-11-10');
    expect(result.single['time'], '00:15:00');
  });
  test(
    'weekly originals survive old cache while expired substitutes do not repeat',
    () {
      final result = plan([
        lesson(1, day: 'Kamis'),
        lesson(2, teacher: 2, substitute: 1, date: '2026-11-05', day: 'Kamis'),
      ], snapshot: '2026-11-03');
      expect(result.single['date'], '2026-11-12');
    },
  );
  test('invalid times and deleted assignments never produce alarms', () {
    expect(
      plan([
        lesson(1, time: '24:00'),
        lesson(2, time: '08:70'),
        lesson(3, time: 'wrong'),
        {...lesson(4), 'deleted_at': '2026-11-10'},
      ]),
      isEmpty,
    );
  });
  test(
    'duplicate rows deduplicate while module identities remain distinct',
    () {
      final result = planScheduleAlerts('api|1', {
        'formal': ScheduleSnapshot('2026-11-10', [lesson(1), lesson(1)]),
        'diniyyah': ScheduleSnapshot('2026-11-10', [lesson(1)]),
      }, now: now);
      expect(result.length, 2);
      expect(result.map((r) => r['key']).toSet().length, 2);
    },
  );
  test('Jumat and Minggu aliases match Indonesian timetable days', () {
    final result = plan([lesson(1, day: "Jum'at"), lesson(2, day: 'Minggu')]);
    expect(result.map((r) => r['date']), ['2026-11-13', '2026-11-15']);
  });

  group('native bridge synchronization', () {
    final calls = <MethodCall>[];
    late ScheduleAlerts alerts;
    setUp(() async {
      final db = await SyncStore.instance.database;
      await db.delete('meta');
      calls.clear();
      alerts = ScheduleAlerts();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ScheduleAlertBridge.channel, (call) async {
            calls.add(call);
            if (call.method == 'status') {
              return {'supported': true, 'allowed': true, 'exact': true};
            }
            if (call.method == 'consumeOpen') return false;
            return true;
          });
    });
    tearDown(() async {
      await alerts.bind(null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ScheduleAlertBridge.channel, null);
    });
    test(
      'tomorrow substitutions merge without replacing today and survive restart',
      () async {
        await alerts.bind('api|1');
        final now = campusNow();
        final today = campusDate(now);
        final tomorrowTime = DateTime.utc(now.year, now.month, now.day + 1);
        final tomorrow = campusDate(tomorrowTime);
        const days = [
          'Senin',
          'Selasa',
          'Rabu',
          'Kamis',
          'Jumat',
          'Sabtu',
          'Ahad',
        ];
        alerts.accept('api|1', 'formal', today, {
          'data': [lesson(1, day: days[now.weekday - 1])],
        });
        await alerts.publish();
        alerts.accept('api|1', 'formal', tomorrow, {
          'data': [
            lesson(
              2,
              teacher: 2,
              substitute: 1,
              date: tomorrow,
              day: days[tomorrowTime.weekday - 1],
              time: '00:15',
            ),
          ],
        });
        await alerts.publish();
        final sent =
            calls.where((c) => c.method == 'replace').last.arguments as Map;
        expect((sent['lessons'] as List).length, 2);
        calls.clear();
        await alerts.bind('api|1');
        final restored =
            calls.where((c) => c.method == 'replace').last.arguments as Map;
        expect((restored['lessons'] as List).length, 2);
        alerts.accept('api|1', 'formal', tomorrow, {'data': []});
        await alerts.publish();
        final removed =
            calls.where((c) => c.method == 'replace').last.arguments as Map;
        expect((removed['lessons'] as List).length, 1);
      },
    );

    test(
      'finish time and full class survive compact cache and app restart',
      () async {
        final now = campusNow();
        const days = [
          'Senin',
          'Selasa',
          'Rabu',
          'Kamis',
          'Jumat',
          'Sabtu',
          'Ahad',
        ];
        final row = lesson(1, day: days[now.weekday - 1]);
        row['end_time'] = '09:30';
        (row['assignment'] as Map)['kelas'] = {
          'nama': 'VII A',
          'tingkat': 'SMP',
        };
        await alerts.bind('api|1');
        alerts.accept('api|1', 'formal', campusDate(now), {
          'data': [row],
        });
        await alerts.publish();
        await alerts.bind('api|1');
        final restored =
            calls.where((c) => c.method == 'replace').last.arguments as Map;
        final rows = restored['lessons'] as List;
        expect((rows.single as Map)['endTime'], '09:30:00');
        expect((rows.single as Map)['class'], 'VII A, SMP');
      },
    );

    test(
      'old compact alerts recover finish and level from full offline timetable',
      () async {
        final now = campusNow();
        const days = [
          'Senin',
          'Selasa',
          'Rabu',
          'Kamis',
          'Jumat',
          'Sabtu',
          'Ahad',
        ];
        final old = lesson(1, day: days[now.weekday - 1]);
        final fresh = lesson(1, day: days[now.weekday - 1]);
        fresh['end_time'] = '';
        fresh['jam_selesai'] = '09:45';
        (fresh['assignment'] as Map)['kelas'] = {
          'nama': 'VII A',
          'tingkat': 'SMP',
        };
        await SyncStore.instance.setMeta(
          'alerts_schedule::api|1::formal',
          jsonEncode({
            'date': campusDate(now),
            'payload': {
              'data': [old],
            },
          }),
        );
        await SyncStore.instance.setMeta(
          'schedule::api|1::formal',
          jsonEncode({
            'date': campusDate(now),
            'payload': {
              'data': [fresh, lesson(2)],
            },
          }),
        );
        await alerts.bind('api|1');
        final sent =
            calls.where((c) => c.method == 'replace').last.arguments as Map;
        final rows = sent['lessons'] as List;
        expect(rows, hasLength(1));
        expect((rows.single as Map)['endTime'], '09:45:00');
        expect((rows.single as Map)['class'], 'VII A, SMP');
        final saved =
            jsonDecode(
                  (await SyncStore.instance.getMeta(
                    'alerts_schedule::api|1::formal',
                  ))!,
                )
                as Map;
        expect((saved['payload']['data'] as List).single['end_time'], '09:45');
      },
    );

    test('unchanged snapshots do not send repeated native plans', () async {
      await alerts.bind('api|1');
      calls.clear();
      final date = campusDate(campusNow());
      final days = [
        'Senin',
        'Selasa',
        'Rabu',
        'Kamis',
        'Jumat',
        'Sabtu',
        'Ahad',
      ];
      final row = lesson(1, day: days[campusNow().weekday - 1]);
      alerts.accept('api|1', 'formal', date, {
        'data': [row],
      });
      await alerts.publish();
      await alerts.publish();
      expect(calls.where((c) => c.method == 'replace').length, 1);
    });
    test('account switch and per-user disable cancel prior plans', () async {
      await alerts.bind('api|1');
      await alerts.setEnabled(false);
      await alerts.bind('api|2');
      expect(alerts.enabled, true);
      await alerts.bind('api|1');
      expect(alerts.enabled, false);
      expect(calls.where((c) => c.method == 'bind').last.arguments, {
        'account': 'api|1',
        'enabled': false,
      });
    });
    test(
      'fresh empty schedule clears removed assignments and ignores other accounts',
      () async {
        final date = campusDate(campusNow());
        await SyncStore.instance.setMeta(
          'schedule::api|1::formal',
          jsonEncode({
            'date': date,
            'payload': {
              'data': [lesson(1)],
            },
          }),
        );
        await alerts.bind('api|1');
        calls.clear();
        alerts.accept('api|2', 'formal', date, {
          'data': [lesson(2)],
        });
        await alerts.publish();
        expect(calls.where((c) => c.method == 'replace'), isEmpty);
        alerts.accept('api|1', 'formal', date, {'data': []});
        await alerts.publish();
        expect(
          (calls.singleWhere((c) => c.method == 'replace').arguments
              as Map)['lessons'],
          isEmpty,
        );
      },
    );
  });
}
