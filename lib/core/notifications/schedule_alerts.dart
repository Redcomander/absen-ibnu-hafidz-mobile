import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ibnu_schedule_alerts/ibnu_schedule_alerts.dart';

import '../network/json_codec.dart';
import '../network/sync_store.dart';
import '../../features/jadwal/schedule_repository.dart';

DateTime campusNow([DateTime? now]) =>
    (now ?? DateTime.now()).toUtc().add(const Duration(hours: 7));
String campusDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String? _finishTime(Map row) {
  for (final key in ['end_time', 'jam_selesai', 'endTime', 'jamSelesai']) {
    final value = row[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null' && value != '-') {
      return value;
    }
  }
  return null;
}

String _classLabel(Map kelas) {
  final name =
      [
            kelas['nama'] ?? kelas['name'] ?? 'Kelas',
            kelas['sub_kelas'] ?? kelas['subkelas'],
          ]
          .where((v) => v != null && v.toString().trim().isNotEmpty)
          .map((v) => v.toString().trim())
          .join(' ');
  final level = kelas['tingkat']?.toString().trim() ?? '';
  return level.isEmpty ? name : '$name, $level';
}

class ScheduleSnapshot {
  const ScheduleSnapshot(this.date, this.rows);
  final String date;
  final List<dynamic> rows;
}

/// Pure planning: only owned assignments and date-valid substitutions are kept.
List<Map<String, Object?>> planScheduleAlerts(
  String account,
  Map<String, ScheduleSnapshot> snapshots, {
  DateTime? now,
}) {
  final user = account.split('|').last;
  final today = campusNow(now);
  final plan = <String, Map<String, Object?>>{};
  const days = ['senin', 'selasa', 'rabu', 'kamis', 'jumat', 'sabtu', 'ahad'];
  for (final entry in snapshots.entries) {
    for (final row in entry.value.rows.whereType<Map>()) {
      if (row['deleted_at'] != null) continue;
      final id = row['id']?.toString();
      if ((int.tryParse(id ?? '') ?? 0) <= 0) continue;
      final assignment = row['assignment'] as Map? ?? {};
      final teacher =
          (assignment['teacher'] as Map?)?['id'] ?? assignment['user_id'];
      final substitute =
          (row['substitute_teacher'] as Map?)?['id'] ??
          row['substitute_teacher_id'];
      final substituteDate = row['substitute_date']
          ?.toString()
          .split('T')
          .first;
      var day = (row['day'] ?? row['hari'] ?? '')
          .toString()
          .toLowerCase()
          .replaceAll(RegExp('[^a-z]'), '');
      if (day == 'minggu') day = 'ahad';
      final parts = (row['start_time'] ?? row['jam_mulai'] ?? '')
          .toString()
          .split(':');
      if (parts.length < 2 || parts.length > 3) continue;
      final hour = int.tryParse(parts[0]), minute = int.tryParse(parts[1]);
      final second = parts.length == 3 ? int.tryParse(parts[2]) : 0;
      if (hour == null ||
          minute == null ||
          second == null ||
          hour < 0 ||
          hour > 23 ||
          minute < 0 ||
          minute > 59 ||
          second < 0 ||
          second > 59) {
        continue;
      }
      final time =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
      final rawEnd = _finishTime(row);
      String? endTime;
      if (rawEnd != null && rawEnd.toString().isNotEmpty) {
        final end = rawEnd.toString().split(':');
        final h = int.tryParse(end.first);
        final m = end.length > 1 ? int.tryParse(end[1]) : null;
        final sec = end.length == 3 ? int.tryParse(end[2]) : 0;
        if (end.length < 2 ||
            end.length > 3 ||
            h == null ||
            m == null ||
            sec == null ||
            h < 0 ||
            h > 23 ||
            m < 0 ||
            m > 59 ||
            sec < 0 ||
            sec > 59) {
          continue;
        }
        endTime =
            '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
        if (endTime == time) continue;
      }
      for (var offset = 0; offset < 7; offset++) {
        final date = DateTime.utc(today.year, today.month, today.day + offset);
        if (days[date.weekday - 1] != day) continue;
        final dateKey = campusDate(date);
        final own = teacher?.toString() == user;
        final replacement =
            substitute?.toString() == user &&
            ((substituteDate == null || substituteDate.isEmpty)
                ? entry.value.date == dateKey
                : substituteDate == dateKey);
        if (!own && !replacement) continue;
        final lesson =
            assignment['lesson'] as Map? ??
            assignment['diniyyah_lesson'] as Map? ??
            {};
        final kelas = assignment['kelas'] as Map? ?? {};
        final key = '${entry.key}:$id:$dateKey';
        plan[key] = {
          'key': key,
          'date': dateKey,
          'time': time,
          'endTime': endTime,
          'lesson': (lesson['name'] ?? lesson['nama'] ?? 'Pelajaran')
              .toString(),
          'class': _classLabel(kelas),
          'substitute': !own && replacement,
          'repeatWeekly': own,
        };
      }
    }
  }
  return plan.values.toList()..sort(
    (a, b) => '${a['date']} ${a['time']} ${a['key']}'.compareTo(
      '${b['date']} ${b['time']} ${b['key']}',
    ),
  );
}

// Retain only notification fields for the current user, avoiding repeated
// processing or storage of an administrator's complete timetable and rosters.
List<Map<String, Object?>> _personalRows(String account, List<dynamic> rows) {
  final user = account.split('|').last;
  return rows
      .whereType<Map>()
      .where((row) {
        final assignment = row['assignment'] as Map? ?? {};
        final teacher =
            (assignment['teacher'] as Map?)?['id'] ?? assignment['user_id'];
        final substitute =
            (row['substitute_teacher'] as Map?)?['id'] ??
            row['substitute_teacher_id'];
        return row['deleted_at'] == null &&
            (teacher?.toString() == user || substitute?.toString() == user);
      })
      .map((row) {
        final assignment = row['assignment'] as Map? ?? {};
        final lesson =
            assignment['lesson'] as Map? ??
            assignment['diniyyah_lesson'] as Map? ??
            {};
        final kelas = assignment['kelas'] as Map? ?? {};
        return <String, Object?>{
          'id': row['id'],
          'day': row['day'] ?? row['hari'],
          'start_time': row['start_time'] ?? row['jam_mulai'],
          'end_time': _finishTime(row),
          'substitute_teacher_id':
              (row['substitute_teacher'] as Map?)?['id'] ??
              row['substitute_teacher_id'],
          'substitute_date': row['substitute_date'],
          'assignment': {
            'user_id':
                (assignment['teacher'] as Map?)?['id'] ?? assignment['user_id'],
            'lesson': {'name': lesson['name'] ?? lesson['nama']},
            'kelas': {
              'nama': kelas['nama'] ?? kelas['name'],
              'sub_kelas': kelas['sub_kelas'] ?? kelas['subkelas'],
              'tingkat': kelas['tingkat'],
            },
          },
        };
      })
      .toList();
}

class ScheduleAlerts {
  static final instance = ScheduleAlerts();
  static final openSchedule = ValueNotifier<int>(0);
  final Map<String, ScheduleSnapshot> _snapshots = {};
  final Set<String> _dirty = {};
  String? _account, _lastPlan;
  bool enabled = true, includeRamadhan = true;
  bool supported = false, allowed = false, exact = false;
  bool _foreground = true;
  VoidCallback? onStatus;
  Timer? _debounce;
  Future<void> _writes = Future.value();
  int _generation = 0;

  Future<bool> _native(String method, [Object? args]) async {
    try {
      await ScheduleAlertBridge.call<Object?>(method, args);
      return true;
    } on MissingPluginException {
      /* Android-only bridge, including widget tests. */
    } on PlatformException {
      /* Notifications must never interrupt attendance saves. */
    }
    return false;
  }

  Future<void> bind(
    String? account, {
    bool ramadhan = true,
    bool foreground = true,
  }) async {
    final generation = ++_generation;
    _debounce?.cancel();
    _account = account;
    includeRamadhan = ramadhan;
    _foreground = foreground;
    _snapshots.clear();
    _dirty.clear();
    _lastPlan = null;
    final nextEnabled =
        account == null ||
        await SyncStore.instance.getMeta('alerts_enabled::$account') != 'false';
    if (generation != _generation) return;
    enabled = nextEnabled;
    if (foreground) {
      await _native('bind', {'account': account, 'enabled': enabled});
      ScheduleAlertBridge.channel.setMethodCallHandler((call) async {
        if (call.method == 'openSchedule') openSchedule.value++;
      });
      try {
        if (await ScheduleAlertBridge.call<bool>('consumeOpen') == true) {
          openSchedule.value++;
        }
      } on MissingPluginException {
        /* Non-Android. */
      }
    }
    if (account == null || generation != _generation) return;
    ScheduleRepository.onSnapshot = accept;
    for (final type in [
      'formal',
      'diniyyah',
      if (includeRamadhan) 'ramadhan',
    ]) {
      final raw =
          await SyncStore.instance.getMeta(
            'alerts_schedule::$account::$type',
          ) ??
          await SyncStore.instance.getMeta('schedule::$account::$type');
      if (generation != _generation) return;
      if (raw != null) {
        try {
          final snapshot = await BackgroundJson.decode(raw) as Map;
          final rows = (snapshot['payload'] as Map?)?['data'];
          if (generation != _generation) return;
          if (rows is List) {
            final recovered = await _recoverNotificationRows(
              account,
              type,
              rows,
            );
            if (generation != _generation) return;
            _snapshots[type] = ScheduleSnapshot(
              snapshot['date'].toString(),
              recovered,
            );
            if (rows.whereType<Map>().any((r) => _finishTime(r) == null)) {
              _dirty.add(type);
            }
          }
        } catch (_) {
          /* Keep existing offline storage untouched. */
        }
      }
    }
    if (generation != _generation) return;
    await publish();
    if (foreground) await refreshPermissions();
  }

  Future<List<Map<String, Object?>>> _recoverNotificationRows(
    String account,
    String type,
    List rows,
  ) async {
    final personal = _personalRows(account, rows);
    if (personal.every((r) => _finishTime(r) != null)) return personal;
    final raw = await SyncStore.instance.getMeta('schedule::$account::$type');
    if (raw == null) return personal;
    try {
      final snapshot = await BackgroundJson.decode(raw) as Map;
      final full = _personalRows(
        account,
        (snapshot['payload'] as Map)['data'] as List,
      );
      final byId = {for (final row in full) row['id'].toString(): row};
      return personal.map((row) {
        final source = byId[row['id'].toString()];
        if (_finishTime(row) != null || source == null) return row;
        return <String, Object?>{
          ...row,
          'end_time': _finishTime(source),
          'assignment': {
            ...row['assignment'] as Map,
            'kelas': (source['assignment'] as Map)['kelas'],
          },
        };
      }).toList();
    } catch (_) {
      return personal;
    }
  }

  void accept(
    String account,
    String type,
    String date,
    Map<String, dynamic> payload,
  ) {
    if (_account != account ||
        (type == 'ramadhan' && !includeRamadhan) ||
        payload['data'] is! List) {
      return;
    }
    final now = campusNow();
    final today = campusDate(now);
    final tomorrow = campusDate(DateTime.utc(now.year, now.month, now.day + 1));
    if (date != today && date != tomorrow) return;
    final personal = _personalRows(account, payload['data'] as List);
    final user = account.split('|').last;
    bool owned(Map row) =>
        (row['assignment'] as Map?)?['user_id']?.toString() == user;
    bool onTomorrow(Map row) =>
        row['substitute_date']?.toString().split('T').first == tomorrow;
    final existing = _snapshots[type];
    final List<dynamic> rows;
    if (date == tomorrow) {
      rows = [
        ...?existing?.rows.whereType<Map>().where(
          (row) => owned(row) || !onTomorrow(row),
        ),
        ...personal.where((row) => !owned(row) && onTomorrow(row)),
      ];
    } else {
      rows = [
        ...personal,
        ...?existing?.rows.whereType<Map>().where(
          (row) => !owned(row) && onTomorrow(row),
        ),
      ];
    }
    _snapshots[type] = ScheduleSnapshot(
      date == today ? today : (existing?.date ?? today),
      rows,
    );
    _dirty.add(type);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      await publish();
      if (_foreground) await refreshPermissions();
    });
  }

  /// Only the midnight boundary needs another date query. Other hours reuse the
  /// already downloaded weekly schedules, with no extra timetable requests.
  Future<void> prepareMidnightSubstitutes({
    required String? token,
    required Future<bool> Function() canContinue,
  }) async {
    final now = campusNow();
    final account = _account;
    if (account == null || !enabled || now.hour != 23) return;
    final date = campusDate(DateTime.utc(now.year, now.month, now.day + 1));
    for (final type in [
      'formal',
      'diniyyah',
      if (includeRamadhan) 'ramadhan',
    ]) {
      if (_account != account || !await canContinue()) break;
      try {
        await ScheduleRepository().refreshUpcoming(type, date, token);
      } catch (_) {
        /* Existing reminders remain scheduled. */
      }
    }
    _debounce?.cancel();
    await publish();
  }

  Future<void> publish() {
    final account = _account;
    if (account == null || !enabled) return Future.value();
    final plan = planScheduleAlerts(account, _snapshots);
    final encoded = jsonEncode(plan);
    final changed = encoded != _lastPlan;
    if (!changed && _dirty.isEmpty) return _writes;
    final dirty = {for (final type in _dirty) type: _snapshots[type]!};
    _dirty.clear();
    _lastPlan = encoded;
    final generation = _generation;
    _writes = _writes
        .then((_) async {
          if (generation != _generation) return;
          for (final entry in dirty.entries) {
            await SyncStore.instance.setMeta(
              'alerts_schedule::$account::${entry.key}',
              jsonEncode({
                'date': entry.value.date,
                'payload': {'data': entry.value.rows},
              }),
            );
          }
          if (generation != _generation) return;
          if (changed &&
              !await _native('replace', {
                'account': account,
                'lessons': plan,
              })) {
            if (_lastPlan == encoded) _lastPlan = null;
          }
        })
        .catchError((Object _) {
          _lastPlan = null;
        });
    return _writes;
  }

  Future<void> refreshPermissions({bool restore = false}) async {
    final previous = (supported, allowed, exact);
    try {
      final status = await ScheduleAlertBridge.call<Map>('status') ?? {};
      supported = status['supported'] == true;
      allowed = status['allowed'] == true;
      exact = status['exact'] == true;
      if (enabled &&
          _snapshots.isNotEmpty &&
          planScheduleAlerts(_account ?? '', _snapshots).isNotEmpty &&
          !allowed) {
        await _native('permission', {'automatic': true});
        final next = await ScheduleAlertBridge.call<Map>('status') ?? {};
        allowed = next['allowed'] == true;
      }
      if (allowed && (restore || previous != (supported, allowed, exact))) {
        await _native('restore');
      }
    } on MissingPluginException {
      supported = false;
    } on PlatformException {
      /* OS settings remain available on the next resume. */
    }
    if (previous != (supported, allowed, exact)) onStatus?.call();
  }

  Future<void> setEnabled(bool value) async {
    final account = _account;
    if (account == null) return;
    await SyncStore.instance.setMeta('alerts_enabled::$account', '$value');
    if (_account != account) return;
    enabled = value;
    await _native('bind', {'account': account, 'enabled': value});
    _lastPlan = null;
    if (value) {
      await publish();
      await refreshPermissions();
    }
  }

  Future<void> settings({bool exactAlarm = false}) async {
    await _native(exactAlarm ? 'exactSettings' : 'notificationSettings');
  }

  Future<void> configureRamadhan(bool value) async {
    includeRamadhan = value;
    if (!value) _snapshots.remove('ramadhan');
    _lastPlan = null;
    await publish();
  }

  Future<void> resume() async {
    // Date changes refresh the 7-day window even when the phone stays offline.
    await publish();
    await refreshPermissions(restore: true);
  }
}
