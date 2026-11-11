import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/access/access.dart';
import '../../core/network/api_client.dart';
import '../auth/auth_controller.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});
  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  int _page = 1, _generation = 0;
  bool _loading = false, _more = false, _signals = false;
  String _module = 'Formal';
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = true}) async {
    final auth = context.read<AuthController>();
    if (!hasAccess(auth.user, 'students.view')) return;
    final generation = ++_generation, owner = auth.user?['id'];
    if (reset) _page = 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _rows = [];
    });
    try {
      final data = await ApiClient.get(
        _signals ? '/students/attendance-signals' : '/students',
        token: auth.token,
        useOfflineCache: false,
        query: {
          'search': _search.text.trim(),
          'page': '$_page',
          'per_page': '20',
          if (_signals) 'module': _module,
        },
      );
      if (!mounted || generation != _generation || auth.user?['id'] != owner) {
        return;
      }
      final rows = listValue(data['data']);
      setState(() {
        _rows = reset ? rows : [..._rows, ...rows];
        _more = _signals
            ? data['has_more'] == true
            : (_page * 20 < (int.tryParse('${data['total']}') ?? 0));
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = e is ApiException && e.statusCode == 404
              ? 'Fitur perkembangan santri memerlukan backend terbaru.'
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Santri & perkembangan')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: 'Cari nama santri',
            suffixIcon: IconButton(
              tooltip: 'Cari',
              onPressed: () => _load(),
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (_) => _load(),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Perlu tindak lanjut'),
          subtitle: const Text(
            'Minimal 3 catatan Alpha dalam 30 hari terakhir. Bukan kesimpulan pelanggaran.',
          ),
          value: _signals,
          onChanged: (v) {
            setState(() => _signals = v);
            _load();
          },
        ),
        if (_signals)
          Wrap(
            spacing: 8,
            children: [
              for (final m in ['Formal', 'Diniyyah', 'Halaqoh'])
                if (hasAccess(
                  context.read<AuthController>().user,
                  {
                    'Formal': 'absensi.view',
                    'Diniyyah': 'absensi_diniyyah.view',
                    'Halaqoh': 'halaqoh.view',
                  }[m]!,
                ))
                  ChoiceChip(
                    label: Text(m),
                    selected: _module == m,
                    onSelected: (_) {
                      setState(() => _module = m);
                      _load();
                    },
                  ),
            ],
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          ListTile(
            title: Text(_error!),
            trailing: IconButton(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh),
            ),
          ),
        if (!_loading && _error == null && _rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Tidak ada data yang sesuai.'),
          ),
        for (final s in _rows)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text('${s['nama_lengkap'] ?? s['name']}'),
              subtitle: Text(
                _signals
                    ? '${s['count']} catatan Alpha • $_module'
                    : '${mapValue(s['kelas'])['nama'] ?? '-'}, ${mapValue(s['kelas'])['tingkat'] ?? '-'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentProgressScreen(
                    studentId: s['student_id'] ?? s['id'],
                  ),
                ),
              ),
            ),
          ),
        if (_more)
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    _page++;
                    _load(reset: false);
                  },
            child: const Text('Muat berikutnya'),
          ),
      ],
    ),
  );
}

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
  int _days = 30, _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>(), now = DateTime.now();
    final generation = ++_generation, owner = auth.user?['id'];
    setState(() {
      _loading = true;
      _error = null;
      _data = {};
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
      if (mounted && generation == _generation && auth.user?['id'] == owner) {
        setState(() => _data = data);
      }
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
        counts = listValue(_data['counts']);
    final monthly = <String, Map<String, int>>{};
    int total = 0, hadir = 0, alpha = 0;
    for (final c in counts) {
      final count = int.tryParse('${c['count']}') ?? 0,
          status = '${c['status']}'.toLowerCase(),
          date = '${c['date']}';
      total += count;
      if (status == 'hadir') hadir += count;
      if (['alpa', 'alpha', 'tidak_hadir'].contains(status)) alpha += count;
      if (date.length >= 7) {
        final month = monthly.putIfAbsent(
          date.substring(0, 7),
          () => {'total': 0, 'hadir': 0},
        );
        month['total'] = month['total']! + count;
        if (status == 'hadir') month['hadir'] = month['hadir']! + count;
      }
    }
    final months = monthly.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Profil santri')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
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
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (student.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '${student['nama_lengkap']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text('NISN: ${student['nisn'] ?? '-'}'),
              Text(
                '${mapValue(student['kelas'])['nama'] ?? '-'}, ${mapValue(student['kelas'])['tingkat'] ?? '-'}',
              ),
              if (_data['__from_cache'] == true)
                const Text('Menampilkan salinan offline.'),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    total == 0
                        ? 'Belum ada catatan dalam periode ini.'
                        : 'Kehadiran ${(hadir * 100 / total).toStringAsFixed(1)}% • $hadir hadir / $total catatan',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Modul sesuai akses: ${(_data['modules'] as List? ?? []).join(', ')}',
              ),
              if (alpha >= 3)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '$alpha catatan Alpha dalam periode ini. Periksa alasan dan lakukan tindak lanjut; data ini tidak menghitung sesi yang belum diabsen.',
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                'Tren kehadiran bulanan',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final month in months)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$month • ${monthly[month]!['hadir']}/${monthly[month]!['total']} hadir',
                      ),
                      LinearProgressIndicator(
                        value:
                            monthly[month]!['hadir']! /
                            monthly[month]!['total']!,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                '30 catatan terbaru',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final row in listValue(_data['history']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${row['date']} • ${row['module']} • ${row['status']}',
                  ),
                  subtitle: Text('${row['notes'] ?? ''}'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
