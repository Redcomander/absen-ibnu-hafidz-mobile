import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/access/access.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../jadwal/schedule_target.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({
    super.key,
    required this.onOpenSchedule,
    this.onOpenScheduleCard,
  });
  final VoidCallback onOpenSchedule;
  final ValueChanged<ScheduleTarget>? onOpenScheduleCard;
  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  DateTime _period = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic> _data = {};
  bool _loading = false, _cached = false, _ramadhan = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    if (!hasAccess(auth.user, 'dashboard.view')) return;
    final generation = ++_generation, owner = auth.user?['id'];
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        ApiClient.get(
          '/dashboard/stats',
          token: auth.token,
          query: {'month': '${_period.month}', 'year': '${_period.year}'},
        ),
        ApiClient.get(
          '/feature-flags/ramadhan',
          token: auth.token,
          useOfflineCache: false,
        ).catchError((_) => <String, dynamic>{}),
      ]);
      final data = responses[0];
      if (!mounted || generation != _generation || auth.user?['id'] != owner) {
        return;
      }
      setState(() {
        _data = data;
        _ramadhan = responses[1]['is_enabled'] == true;
        _cached = data['__from_cache'] == true;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = errorMessage(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!hasAccess(context.watch<AuthController>().user, 'dashboard.view')) {
      return const SizedBox.shrink();
    }
    final teacher = mapValue(_data['teacher']);
    final recap = mapValue(teacher['teacher_recap']);
    final schedules = [
      ...listValue(
        teacher['personal_schedule'],
      ).map((s) => {...s, 'module': 'Formal'}),
      ...listValue(
        teacher['personal_diniyyah_schedule'],
      ).map((s) => {...s, 'module': 'Diniyyah'}),
    ]..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'));
    final visibleSchedules = schedules
        .where(
          (s) =>
              _ramadhan ||
              !RegExp(
                r'ramadhan|ramadan|romadhon|romadon',
                caseSensitive: false,
              ).hasMatch(jsonEncode(s)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ringkasan saya',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Muat ulang dashboard',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        DropdownButtonFormField<DateTime>(
          initialValue: _period,
          decoration: const InputDecoration(labelText: 'Periode'),
          items: List.generate(12, (i) {
            final date = DateTime(
              DateTime.now().year,
              DateTime.now().month - i,
            );
            return DropdownMenuItem(
              value: date,
              child: Text(indonesianMonthYear(date)),
            );
          }),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _period = v;
                _data = {};
              });
              _load();
            }
          },
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_cached)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Salinan offline • tarik/muat ulang saat online.'),
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
        if (recap.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            color: AppTheme.brand,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'KEHADIRAN SAYA',
                    style: TextStyle(color: AppTheme.accent),
                  ),
                  Text(
                    '${recap['percentage'] ?? 0}%',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${recap['hadir'] ?? 0} hadir dari ${recap['total'] ?? 0} catatan',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in {
            'formal_stats': 'Formal',
            'diniyyah_stats': 'Diniyyah',
            'halaqoh_stats': 'Halaqoh',
          }.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  title: Text(entry.value),
                  subtitle: Text(
                    'Hadir ${mapValue(teacher[entry.key])['hadir'] ?? 0} • Izin ${mapValue(teacher[entry.key])['izin'] ?? 0} • Sakit ${mapValue(teacher[entry.key])['sakit'] ?? 0} • Alpha ${mapValue(teacher[entry.key])['alpha'] ?? 0}',
                  ),
                  trailing: Text(
                    '${mapValue(teacher[entry.key])['percentage'] ?? 0}%',
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Jadwal hari ini',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (!_loading && _error == null && visibleSchedules.isEmpty)
          const Text('Tidak ada jadwal Formal/Diniyyah hari ini.'),
        for (final s in visibleSchedules)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                isThreeLine: true,
                leading: const Icon(Icons.school_outlined),
                title: Text(
                  '${mapValue(mapValue(s['assignment'])['lesson'])['name'] ?? mapValue(mapValue(s['assignment'])['diniyyah_lesson'])['name'] ?? 'Pelajaran'}',
                ),
                subtitle: Text(
                  '${s['module']} • ${mapValue(mapValue(s['assignment'])['kelas'])['nama'] ?? '-'}, ${mapValue(mapValue(s['assignment'])['kelas'])['tingkat'] ?? '-'}\n${s['start_time'] ?? '-'} – ${s['end_time'] ?? '-'}',
                ),
                onTap: () {
                  final target = ScheduleTarget.fromDashboard(s);
                  if (target != null && widget.onOpenScheduleCard != null) {
                    widget.onOpenScheduleCard!(target);
                  } else {
                    widget.onOpenSchedule();
                  }
                },
              ),
            ),
          ),
        if (listValue(teacher['substitute_records']).isNotEmpty)
          ExpansionTile(
            title: const Text('Riwayat tugas pengganti'),
            children: [
              for (final s in listValue(teacher['substitute_records']))
                ListTile(
                  title: Text('${s['lesson'] ?? 'Tugas pengganti'}'),
                  subtitle: Text(
                    '${s['date'] ?? '-'} • ${s['original_teacher'] ?? '-'}',
                  ),
                ),
            ],
          ),
        const SizedBox(height: 18),
      ],
    );
  }
}
