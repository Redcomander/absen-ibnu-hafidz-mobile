import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/access/access.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import 'attendance_insights.dart';

class StudentProgressScreen extends StatefulWidget {
  const StudentProgressScreen({super.key, required this.studentId});
  final dynamic studentId;
  @override
  State<StudentProgressScreen> createState() => _StudentProgressScreenState();
}

class _StudentProgressScreenState extends State<StudentProgressScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;
  String _module = 'Semua', _historyStatus = 'Semua';
  int _days = 30, _generation = 0;
  Map<String, int> _counts = {};
  Map<String, Map<String, int>> _monthly = {};
  List<Map<String, dynamic>> _history = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _derive() {
    final counts = <String, int>{'Hadir': 0, 'Izin': 0, 'Sakit': 0, 'Alpha': 0};
    final months = <String, Map<String, int>>{};
    for (final row in listValue(_data['counts'])) {
      if (_module != 'Semua' && row['module'] != _module) continue;
      final count = int.tryParse('${row['count']}') ?? 0;
      final status = attendanceStatus(row['status']), date = '${row['date']}';
      counts.update(status, (n) => n + count, ifAbsent: () => count);
      if (date.length >= 7) {
        final month = months.putIfAbsent(
          date.substring(0, 7),
          () => {'total': 0},
        );
        month.update('total', (n) => n + count);
        month.update(status, (n) => n + count, ifAbsent: () => count);
      }
    }
    _counts = counts;
    _monthly = months;
    _history = listValue(_data['history'])
        .where(
          (r) =>
              (_module == 'Semua' || r['module'] == _module) &&
              (_historyStatus == 'Semua' ||
                  attendanceStatus(r['status']) == _historyStatus),
        )
        .toList();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>(), now = DateTime.now();
    final generation = ++_generation, owner = auth.user?['id'];
    setState(() {
      _loading = true;
      _error = null;
      _data = {};
      _derive();
    });
    try {
      final data = await ApiClient.get(
        '/students/${widget.studentId}/progress',
        token: auth.token,
        query: {
          'start_date': DateFormat(
            'yyyy-MM-dd',
          ).format(now.subtract(Duration(days: _days - 1))),
          'end_date': DateFormat('yyyy-MM-dd').format(now),
        },
      );
      if (!mounted || generation != _generation || auth.user?['id'] != owner) {
        return;
      }
      setState(() {
        _data = data;
        _derive();
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = e is ApiException && e.statusCode == 404
              ? 'Profil perkembangan memerlukan backend terbaru.'
              : errorMessage(e),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = mapValue(_data['student']),
        name = '${mapValue(_data['student'])['nama_lengkap'] ?? 'Santri'}';
    final total = _counts.values.fold<int>(0, (a, b) => a + b);
    final modules = (_data['modules'] as List? ?? []).map((m) => '$m').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Profil santri')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in [30, 90, 365])
                  ChoiceChip(
                    label: Text('$days hari'),
                    selected: _days == days,
                    onSelected: (_) {
                      setState(() => _days = days);
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              InsightCard(
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            if (student.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [AppTheme.brand, Color(0xFF286653)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.brand,
                      child: Text(
                        name.isEmpty
                            ? '?'
                            : name.characters.first.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${mapValue(student['kelas'])['nama'] ?? '-'}, ${mapValue(student['kelas'])['tingkat'] ?? '-'}',
                      style: const TextStyle(color: AppTheme.accent),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'NISN: ${student['nisn'] ?? '-'}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (_data['__from_cache'] == true)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Menampilkan salinan offline.'),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final module in ['Semua', ...modules])
                    ChoiceChip(
                      label: Text(module),
                      selected: _module == module,
                      onSelected: (_) => setState(() {
                        _module = module;
                        _derive();
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '$total catatan dalam $_days hari',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Statistik berasal dari catatan yang sudah diisi dan modul sesuai hak akses Anda.',
                style: TextStyle(color: AppTheme.muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              AttendanceChart(counts: _counts),
              const SizedBox(height: 14),
              AttendanceTrend(months: _monthly),
              const SizedBox(height: 14),
              if ((_counts['Alpha'] ?? 0) >= 3) ...[
                InsightCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.forum_outlined, color: AppTheme.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${_counts['Alpha']} catatan Alpha. Tinjau alasan dan diskusikan pendampingan; angka ini bukan kesimpulan pelanggaran.',
                          style: const TextStyle(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              InsightCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Catatan terbaru',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Maksimal 30 catatan terbaru pada periode ini.',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final status in [
                          'Semua',
                          'Hadir',
                          'Izin',
                          'Sakit',
                          'Alpha',
                        ])
                          ChoiceChip(
                            label: Text(status),
                            selected: _historyStatus == status,
                            onSelected: (_) => setState(() {
                              _historyStatus = status;
                              _derive();
                            }),
                          ),
                      ],
                    ),
                    if (_history.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('Tidak ada catatan terbaru yang sesuai.'),
                      ),
                    for (final row in _history)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 17,
                          backgroundColor:
                              (attendanceColors[attendanceStatus(
                                        row['status'],
                                      )] ??
                                      AppTheme.muted)
                                  .withValues(alpha: .1),
                          child: Icon(
                            Icons.event_available_outlined,
                            size: 18,
                            color:
                                attendanceColors[attendanceStatus(
                                  row['status'],
                                )],
                          ),
                        ),
                        title: Text(
                          '${attendanceStatus(row['status'])} • ${row['module']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${row['date']}${'${row['notes'] ?? ''}'.isEmpty ? '' : '\n${row['notes']}'}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
