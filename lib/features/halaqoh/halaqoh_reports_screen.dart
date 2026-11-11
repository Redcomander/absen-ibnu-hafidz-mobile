import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/offline_cache_store.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> _rows(dynamic value) =>
    value is List ? value.whereType<Map>().map(_map).toList() : [];
String _text(dynamic value) =>
    value == null ? '-' : value.toString().replaceAll('Dinas Luar', 'Dinas');

/// Uses the same report schemas and export routes as the Vue application.
class HalaqohReportsScreen extends StatefulWidget {
  const HalaqohReportsScreen({super.key});
  @override
  State<HalaqohReportsScreen> createState() => _HalaqohReportsScreenState();
}

class _HalaqohReportsScreenState extends State<HalaqohReportsScreen> {
  String _scope = 'students', _teacher = '', _gender = '', _search = '';
  late DateTime _start, _end;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _teachers = [];
  bool _loading = true, _exporting = false;
  String? _error;
  int _generation = 0;

  String _date(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
  Map<String, String> get _query => {
    'start_date': _date(_start),
    'end_date': _date(_end),
    if (_teacher.isNotEmpty) 'teacher_id': _teacher,
    if (_gender.isNotEmpty) 'gender': _gender,
  };

  @override
  void initState() {
    super.initState();
    _end = DateTime.now();
    _start = DateTime(_end.year, _end.month);
    _load();
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    try {
      final response = await ApiClient.get(
        '/halaqoh/teacher-options',
        token: context.read<AuthController>().token,
        useOfflineCache: false,
      );
      if (mounted) setState(() => _teachers = _rows(response['data']));
    } catch (_) {
      /* Report access does not depend on picker permission. */
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final account = OfflineCacheStore.scope;
    final scope = _scope;
    final query = _query;
    final token = context.read<AuthController>().token;
    setState(() {
      _loading = true;
      _error = null;
      _data = {};
    });
    bool current() =>
        mounted &&
        generation == _generation &&
        OfflineCacheStore.scope == account;
    try {
      final cached = await OfflineCacheStore.read(
        '/halaqoh/statistics/$scope',
        query: query,
        account: account,
      );
      if (!current()) return;
      if (cached != null) setState(() => _data = cached);
      final response = await ApiClient.get(
        '/halaqoh/statistics/$scope',
        token: token,
        query: query,
      );
      if (!current()) return;
      if (scope == 'students' && response['chartData'] is! List ||
          scope == 'teachers' && response['stats'] is! Map) {
        throw ApiException(
          502,
          'Format rekapan tidak sesuai API web. Periksa versi backend.',
        );
      }
      setState(() {
        _data = response;
        if (_teachers.isEmpty && scope == 'teachers') {
          _teachers = _rows(response['teachers']);
        }
      });
    } catch (e) {
      if (current()) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Rekapan belum dapat dimuat. Periksa koneksi lalu coba lagi.',
        );
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _pickDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (range == null || !mounted) return;
    setState(() {
      _start = range.start;
      _end = range.end;
    });
    await _load();
  }

  Future<void> _export(String format) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file = await ApiClient.download(
        '/halaqoh/export/${_scope == 'students' ? 'student' : 'teacher'}/$format',
        token: context.read<AuthController>().token,
        query: _query,
      );
      final directory = await getApplicationDocumentsDirectory();
      final path =
          '${directory.path}/rekapan_halaqoh_${_scope}_${_date(_start)}_${_date(_end)}.${format == 'excel' ? 'xlsx' : 'pdf'}';
      await File(path).writeAsBytes(file.bytes);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rekapan disimpan'),
          content: SelectableText(path),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Gagal menyimpan rekapan.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _table(String title, List<String> columns, List<List<String>> rows) =>
      ReportDataTable(
        title: title,
        columns: columns,
        rows: rows,
        search: _search,
      );

  Widget _summary(Map<String, dynamic> counts) {
    final values = counts.values.map((v) => int.tryParse('$v') ?? 0).toList();
    final total = values.fold<int>(0, (a, b) => a + b);
    final colors = counts.keys
        .map(
          (label) => switch (label.toLowerCase()) {
            'hadir' => const Color(0xFF23815C),
            'izin' => const Color(0xFFBD902F),
            'sakit' => const Color(0xFF3E83B9),
            'dinas' => const Color(0xFF9261A8),
            _ => const Color(0xFFC35A52),
          },
        )
        .toList();
    final entries = counts.entries.toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ringkasan Kehadiran',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _AttendanceRing(values, colors),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.brand,
                          ),
                        ),
                        const Text('Total catatan'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: List.generate(
                entries.length,
                (i) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 10, color: colors[i]),
                    const SizedBox(width: 6),
                    Text('${entries[i].key}: ${entries[i].value}'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final student = _scope == 'students';
    final counts = student
        ? {
            for (final item in _rows(_data['chartData']))
              _text(item['name']): item['value'],
          }
        : _map(_data['stats']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(
            'Rekapan Halaqoh ${student ? 'Santri' : 'Guru'}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'students',
                label: Text('Santri'),
                icon: Icon(Icons.groups_outlined),
              ),
              ButtonSegment(
                value: 'teachers',
                label: Text('Guru'),
                icon: Icon(Icons.school_outlined),
              ),
            ],
            selected: {_scope},
            onSelectionChanged: (value) {
              setState(() {
                _scope = value.first;
                _search = '';
              });
              _load();
            },
          ),
          const SizedBox(height: 14),
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDates,
                    icon: const Icon(Icons.date_range),
                    label: Text('${_date(_start)} - ${_date(_end)}'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('teacher-$_teacher-${_teachers.length}'),
                    initialValue: _teachers.any((t) => '${t['id']}' == _teacher)
                        ? _teacher
                        : '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Guru Halaqoh',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Semua Guru'),
                      ),
                      ..._teachers.map(
                        (t) => DropdownMenuItem(
                          value: '${t['id']}',
                          child: Text(
                            _text(t['name']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _teacher = value ?? '');
                      _load();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Jenis Kelamin',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: '',
                        child: Text('Semua (Banin & Banat)'),
                      ),
                      DropdownMenuItem(value: 'banin', child: Text('Banin')),
                      DropdownMenuItem(value: 'banat', child: Text('Banat')),
                    ],
                    onChanged: (value) {
                      setState(() => _gender = value ?? '');
                      _load();
                    },
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(onPressed: _load, child: const Text('Coba lagi')),
          ],
          if (_loading) const LinearProgressIndicator(),
          if (_data['__from_cache'] == true)
            const Text('Offline - menampilkan rekapan tersimpan'),
          if (_data.isNotEmpty) ...[
            _summary(counts),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _export('pdf'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Export PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _export('excel'),
                  icon: const Icon(Icons.grid_on_outlined),
                  label: const Text('Export Excel'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey('report-search-$_scope'),
              decoration: const InputDecoration(
                labelText: 'Cari pada hasil rekapan',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _search = value.toLowerCase().trim()),
            ),
            const SizedBox(height: 14),
            if (student) ...[
              for (final entry in {
                'izinStudents': 'Santri Izin',
                'sakitStudents': 'Santri Sakit',
                'alpaStudents': 'Santri Alpa',
              }.entries)
                _table(
                  entry.value,
                  ['Nama Santri'],
                  (_data[entry.key] as List? ?? [])
                      .map((name) => [_text(name)])
                      .toList(),
                ),
            ] else ...[
              Text('Total penggantian: ${_data['substitutionCount'] ?? 0}'),
              const SizedBox(height: 12),
              _table(
                'Rekapan per Sesi',
                ['Sesi', 'Hadir', 'Izin', 'Sakit', 'Alpha', 'Dinas'],
                _map(_data['sessionStats']).entries
                    .map(
                      (e) => [
                        e.key,
                        ...[
                          'Hadir',
                          'Izin',
                          'Sakit',
                          'Alpha',
                          'Dinas',
                        ].map((s) => '${_map(e.value)[s] ?? 0}'),
                      ],
                    )
                    .toList(),
              ),
              _table(
                'Ringkasan Guru',
                [
                  'Guru',
                  'Hadir',
                  'Izin',
                  'Sakit',
                  'Alpha',
                  'Dinas',
                  'Pengganti',
                ],
                _rows(_data['teachers'])
                    .map(
                      (r) => [
                        _text(r['name']),
                        ...[
                          'hadir',
                          'izin',
                          'sakit',
                          'alpha',
                          'dinas',
                          'substitute',
                        ].map((s) => '${r[s] ?? 0}'),
                      ],
                    )
                    .toList(),
              ),
              _table(
                'Riwayat Ketidakhadiran',
                ['Tanggal', 'Guru', 'Sesi', 'Status', 'Catatan'],
                _rows(_data['absence_history'])
                    .map(
                      (r) => [
                        _text(r['date']),
                        _text(r['teacher']),
                        _text(r['session']),
                        _text(r['status']),
                        _text(r['notes']),
                      ],
                    )
                    .toList(),
              ),
              _table(
                'Riwayat Guru Pengganti',
                [
                  'Tanggal',
                  'Sesi',
                  'Guru Asli',
                  'Status',
                  'Pengganti',
                  'Alasan',
                ],
                _rows(_data['history'])
                    .map(
                      (r) => [
                        _text(r['tanggal']),
                        _text(r['sesi']),
                        _text(r['guru_asli']),
                        _text(r['status']),
                        _text(r['pengganti']),
                        _text(r['reason']),
                      ],
                    )
                    .toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class ReportDataTable extends StatefulWidget {
  const ReportDataTable({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.search = '',
  });
  final String title, search;
  final List<String> columns;
  final List<List<String>> rows;
  @override
  State<ReportDataTable> createState() => _ReportDataTableState();
}

class _ReportDataTableState extends State<ReportDataTable> {
  int _page = 0;
  @override
  void didUpdateWidget(ReportDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.search != oldWidget.search || widget.rows != oldWidget.rows) {
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.rows
        .where(
          (row) =>
              row.join(' ').toLowerCase().contains(widget.search.toLowerCase()),
        )
        .toList();
    final start = _page * 10;
    final visible = filtered.skip(start).take(10).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                widget.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Belum ada data pada periode dan filter ini.'),
              )
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  horizontalMargin: 12,
                  columnSpacing: 20,
                  columns: widget.columns
                      .map((label) => DataColumn(label: Text(label)))
                      .toList(),
                  rows: visible
                      .map(
                        (values) => DataRow(
                          cells: values
                              .map((value) => DataCell(Text(value)))
                              .toList(),
                        ),
                      )
                      .toList(),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Halaman sebelumnya',
                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${start + 1}-${start + visible.length} / ${filtered.length}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Halaman berikutnya',
                    onPressed: start + 10 < filtered.length
                        ? () => setState(() => _page++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttendanceRing extends CustomPainter {
  _AttendanceRing(this.values, this.colors);
  final List<int> values;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(8);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawOval(rect, paint..color = AppTheme.brand.withValues(alpha: .08));
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return;
    var angle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = 2 * math.pi * values[i] / total;
      canvas.drawArc(
        rect,
        angle,
        math.max(0, sweep - .025),
        false,
        paint..color = colors[i],
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_AttendanceRing oldDelegate) =>
      values != oldDelegate.values || colors != oldDelegate.colors;
}
