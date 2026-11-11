import 'dart:developer';

import '../../core/network/offline_cache_store.dart';
import 'attendance_repository.dart';
import 'schedule_repository.dart';

class OfflinePreparationResult {
  int schedules = 0, forms = 0, failures = 0;
}

class OfflinePreparation {
  Future<OfflinePreparationResult> prepare({
    required String date,
    required List<String> types,
    required String? token,
    required Future<bool> Function() canContinue,
    int maxForms = 8,
  }) async {
    final result = OfflinePreparationResult();
    final account = OfflineCacheStore.scope;
    final task = TimelineTask()..start('offline.prepare');
    bool sameAccount() => OfflineCacheStore.scope == account;
    final day = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Ahad',
    ][DateTime.parse(date).weekday - 1];
    var attempted = 0;
    final seen = <String>{};
    int own(Map row) {
      final assignment = row['assignment'] as Map?;
      final teacher = (assignment?['teacher'] as Map?)?['id']?.toString();
      final substitute = (row['substitute_teacher'] as Map?)?['id']?.toString();
      return teacher == account.split('|').last ||
              substitute == account.split('|').last
          ? 0
          : 1;
    }

    try {
      for (final type in types) {
        if (!sameAccount() || !await canContinue() || !sameAccount()) break;
        try {
          final schedules = await ScheduleRepository().refresh(
            type,
            date,
            token,
          );
          result.schedules++;
          final today =
              (schedules['data'] as List)
                  .whereType<Map>()
                  .where(
                    (row) =>
                        (row['day'] ?? row['hari'])
                            .toString()
                            .replaceAll("'", '')
                            .toLowerCase() ==
                        day.toLowerCase(),
                  )
                  .toList()
                ..sort((a, b) {
                  final priority = own(a).compareTo(own(b));
                  return priority == 0
                      ? '${a['start_time']}'.compareTo('${b['start_time']}')
                      : priority;
                });
          for (final row in today) {
            if (attempted >= maxForms) break;
            final id = row['id']?.toString();
            if (id == null ||
                (int.tryParse(id) ?? 0) <= 0 ||
                !seen.add('$type:$id')) {
              continue;
            }
            if (!sameAccount() || !await canContinue() || !sameAccount()) {
              return result;
            }
            attempted++;
            try {
              await AttendanceRepository().refresh(type, id, date, token);
              result.forms++;
            } catch (_) {
              result.failures++;
            }
          }
        } catch (_) {
          result.failures++;
        }
      }
      return result;
    } finally {
      task.finish(
        arguments: {
          'schedules': result.schedules,
          'forms': result.forms,
          'failures': result.failures,
        },
      );
    }
  }
}
