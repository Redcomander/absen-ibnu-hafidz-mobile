import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/offline_cache_store.dart';
import '../../core/theme/section_header.dart';
import '../auth/auth_controller.dart';
import 'saved_report_filters.dart';
import '../students/attendance_insights.dart';
import '../students/students_screen.dart';
import '../../core/access/access.dart';
import '../halaqoh/halaqoh_reports_screen.dart';
import '../settings/app_settings_controller.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String _module = 'absensi';
  String _type = 'formal';
  String _scope = 'all';
  String _teacherFilter = '', _kelasFilter = '', _genderFilter = '';
  List<Map<String, dynamic>> _filterTeachers = [], _filterClasses = [];
  bool _loadingFilters = false;
  bool _loading = true;
  int _loadGeneration = 0;
  String? _loadError, _statsQueryKey;
  bool _showingOfflineData = false;
  bool? _wasOnline;
  bool _historyLoadingMore = false;
  bool _teacherExporting = false;

  Map<String, dynamic> _studentStats = {};
  Map<String, dynamic> _teacherStats = {};
  List<Map<String, dynamic>> _history = [];

  int _historyPage = 1;
  int _historyPerPage = 50;
  int _historyTotal = 0;

  late DateTime _startDate;
  late DateTime _endDate;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = now;
    if (_canViewFormalAbsensi() || _canViewDiniyyahAbsensi()) {
      if (!_canViewFormalAbsensi()) _type = 'diniyyah';
      _load(resetHistory: true);
    } else {
      _module = 'halaqoh';
      _loading = false;
    }
  }

  void _observeConnectivity() {
    final isOnline = context.select<AppSettingsController, bool>(
      (s) => s.isOnline,
    );
    if (_wasOnline == false &&
        isOnline &&
        !_loading &&
        (_showingOfflineData || _loadError != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _load(resetHistory: true);
        }
      });
    }
    _wasOnline = isOnline;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _fmtApiDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
  String _fmtUiDate(DateTime value) => DateFormat('dd MMM yyyy').format(value);

  Future<void> _load({required bool resetHistory}) async {
    final settings = context.read<AppSettingsController>();
    final auth = context.read<AuthController>();
    final generation = ++_loadGeneration;
    final account = OfflineCacheStore.scope;
    final query = {
      'type': _type,
      if (_teacherFilter.isNotEmpty) 'teacher_id': _teacherFilter,
      if (_kelasFilter.isNotEmpty) 'kelas_id': _kelasFilter,
      if (_genderFilter.isNotEmpty) 'gender': _genderFilter,
      'start_date': _fmtApiDate(_startDate),
      'end_date': _fmtApiDate(_endDate),
    };
    final historyQuery = {
      ...query,
      'page': '1',
      'per_page': '$_historyPerPage',
      if (_search.trim().isNotEmpty) 'search': _search.trim(),
    };
    final key = '$account|$historyQuery';
    bool current() =>
        mounted &&
        generation == _loadGeneration &&
        OfflineCacheStore.scope == account;
    setState(() {
      _loading = true;
      _loadError = null;
      if (_statsQueryKey != key) {
        _studentStats = {};
        _teacherStats = {};
        _history = [];
        _historyTotal = 0;
        _showingOfflineData = false;
      }
      _statsQueryKey = key;
      if (resetHistory) _historyPage = 1;
    });
    void apply(List<Map<String, dynamic>> results) {
      final history = results[2];
      _studentStats = results[0];
      _teacherStats = results[1];
      _history = _asMapList(history['data']);
      _historyTotal = _asInt(history['total']);
      _historyPage = _asInt(history['page'], fallback: 1);
      _historyPerPage = _asInt(history['per_page'], fallback: 50);
      _showingOfflineData = results.any((r) => r['__from_cache'] == true);
    }

    try {
      final cached = await Future.wait([
        OfflineCacheStore.read(
          '/attendance/statistics',
          query: query,
          account: account,
        ),
        OfflineCacheStore.read(
          '/attendance/teacher-statistics',
          query: query,
          account: account,
        ),
        OfflineCacheStore.read(
          '/attendance/history',
          query: historyQuery,
          account: account,
        ),
      ]);
      if (!current()) return;
      if (cached.every((r) => r != null)) {
        setState(() => apply(cached.cast<Map<String, dynamic>>()));
      }
      if (!await settings.canSyncNow()) {
        if (current() && _studentStats.isEmpty && _teacherStats.isEmpty) {
          _loadError =
              'Belum ada rekapan tersimpan untuk periode ini. Buka periode ini saat online untuk menyimpannya.';
        }
        return;
      }
      if (!current()) return;
      final token = auth.token;
      final results = await Future.wait([
        ApiClient.get('/attendance/statistics', token: token, query: query),
        ApiClient.get(
          '/attendance/teacher-statistics',
          token: token,
          query: query,
        ),
        ApiClient.get('/attendance/history', token: token, query: historyQuery),
      ]).timeout(const Duration(seconds: 8));
      if (current()) apply(results);
    } catch (error) {
      if (!current()) return;
      _loadError =
          'Belum dapat memperbarui rekapan. Data tersimpan tetap tersedia.';
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_historyLoadingMore || _history.length >= _historyTotal) return;

    setState(() => _historyLoadingMore = true);
    try {
      final token = context.read<AuthController>().token;
      final nextPage = _historyPage + 1;
      final res = await ApiClient.get(
        '/attendance/history',
        token: token,
        query: {
          'type': _type,
          if (_teacherFilter.isNotEmpty) 'teacher_id': _teacherFilter,
          if (_kelasFilter.isNotEmpty) 'kelas_id': _kelasFilter,
          if (_genderFilter.isNotEmpty) 'gender': _genderFilter,
          'start_date': _fmtApiDate(_startDate),
          'end_date': _fmtApiDate(_endDate),
          'page': '$nextPage',
          'per_page': '$_historyPerPage',
          if (_search.trim().isNotEmpty) 'search': _search.trim(),
        },
      );

      final historyRes = _asMap(res);
      final moreRows = _asMapList(historyRes['data']);
      _history.addAll(moreRows);
      _historyPage = _asInt(historyRes['page'], fallback: nextPage);
      _historyTotal = _asInt(historyRes['total'], fallback: _historyTotal);
    } catch (_) {
      // Keep current data if loading more fails.
    } finally {
      if (mounted) setState(() => _historyLoadingMore = false);
    }
  }

  List<String> _roleNames() {
    final user = context.read<AuthController>().user;
    return ((user?['roles'] as List?) ?? [])
        .map((role) => (role['name'] ?? '').toString().toLowerCase())
        .toList();
  }

  List<String> _permissionNames() {
    final user = context.read<AuthController>().user;
    final roles = (user?['roles'] as List?) ?? [];
    final permissions = <String>[];

    for (final role in roles) {
      final items = (role['permissions'] as List?) ?? [];
      for (final permission in items) {
        final name = (permission['name'] ?? '').toString().toLowerCase();
        if (name.isNotEmpty) permissions.add(name);
      }
    }

    return permissions;
  }

  bool _isManager() {
    final roles = _roleNames();
    return roles.any(
      (role) =>
          ['super_admin', 'admin', 'staff', 'tim_presensi'].contains(role),
    );
  }

  bool _canViewFormalAbsensi() {
    if (_isManager()) return true;
    return _permissionNames().contains('absensi.view');
  }

  bool _canViewDiniyyahAbsensi() {
    if (_isManager()) return true;
    return _permissionNames().contains('absensi_diniyyah.view');
  }

  bool _canViewHalaqohStats() {
    if (_isManager()) return true;
    return _permissionNames().contains('halaqoh.view');
  }

  List<ButtonSegment<String>> _typeSegments(bool showRamadhan) {
    return [
      if (_canViewFormalAbsensi())
        const ButtonSegment(value: 'formal', label: Text('Formal')),
      if (showRamadhan && _canViewFormalAbsensi())
        const ButtonSegment(value: 'ramadhan', label: Text('Ramadhan')),
      if (_canViewDiniyyahAbsensi())
        const ButtonSegment(value: 'diniyyah', label: Text('Diniyyah')),
    ];
  }

  List<ButtonSegment<String>> get _scopeSegments => const [
    ButtonSegment(value: 'all', label: Text('Semua')),
    ButtonSegment(value: 'student', label: Text('Santri')),
    ButtonSegment(value: 'teacher', label: Text('Guru')),
  ];

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map(_asMap).toList();
  }

  int _asInt(dynamic raw, {int fallback = 0}) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  String _asString(dynamic raw, {String fallback = '-'}) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  int _countValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key)) return _asInt(map[key]);
    }
    return 0;
  }

  String _formatRowDate(dynamic raw) {
    final text = raw?.toString() ?? '';
    if (text.isEmpty) return '-';
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(text));
    } catch (_) {
      return text;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'hadir':
        return const Color(0xFF16A34A);
      case 'izin':
        return const Color(0xFF2563EB);
      case 'sakit':
        return const Color(0xFFEA580C);
      case 'dinas':
      case 'dinas luar':
        return const Color(0xFFB7791F);
      case 'substitute':
        return const Color(0xFF9333EA);
      default:
        return const Color(0xFFDC2626);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_startDate.isAfter(_endDate)) _endDate = picked;
      } else {
        _endDate = picked;
        if (_endDate.isBefore(_startDate)) _startDate = picked;
      }
    });

    await _load(resetHistory: true);
  }

  void _onSearchChanged(String value) {
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _load(resetHistory: true);
    });
  }

  Future<void> _exportTeacherStatsPdf() async {
    if (_teacherExporting) return;

    final messenger = ScaffoldMessenger.of(context);
    final token = context.read<AuthController>().token;

    setState(() => _teacherExporting = true);
    try {
      final file = await ApiClient.download(
        '/attendance/export/teacher/pdf',
        token: token,
        query: {
          'type': _type,
          if (_teacherFilter.isNotEmpty) 'teacher_id': _teacherFilter,
          if (_kelasFilter.isNotEmpty) 'kelas_id': _kelasFilter,
          if (_genderFilter.isNotEmpty) 'gender': _genderFilter,
          'start_date': _fmtApiDate(_startDate),
          'end_date': _fmtApiDate(_endDate),
        },
      );

      final fallbackName =
          'rekap_guru_${_type}_${_fmtApiDate(_startDate)}_${_fmtApiDate(_endDate)}.pdf';
      final fileName = (file.fileName == null || file.fileName!.trim().isEmpty)
          ? fallbackName
          : file.fileName!.trim();

      final baseDir = Platform.isAndroid
          ? (await getExternalStorageDirectory() ??
                await getApplicationDocumentsDirectory())
          : await getApplicationDocumentsDirectory();
      final exportDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}exports',
      );
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      final savedFile = File(
        '${exportDir.path}${Platform.pathSeparator}$fileName',
      );
      await savedFile.writeAsBytes(file.bytes, flush: true);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export berhasil'),
          content: Text('PDF guru disimpan ke:\n\n${savedFile.path}'),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: savedFile.path));
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lokasi file disalin.')),
                  );
                }
              },
              child: const Text('Salin lokasi'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal export PDF guru: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Gagal menyiapkan file export guru.')),
      );
    } finally {
      if (mounted) {
        setState(() => _teacherExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _observeConnectivity();
    final showRamadhan = context.select<AppSettingsController, bool>(
      (s) => s.isRamadhanTabEnabled,
    );
    final canViewAbsensi = _canViewFormalAbsensi() || _canViewDiniyyahAbsensi();
    final canViewHalaqoh = _canViewHalaqohStats();
    final typeSegments = _typeSegments(showRamadhan);

    if (!canViewAbsensi && canViewHalaqoh && _module != 'halaqoh') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _module = 'halaqoh');
      });
    }

    if (!canViewHalaqoh && _module == 'halaqoh') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _module = 'absensi');
      });
    }

    if (typeSegments.isNotEmpty &&
        !typeSegments.any((segment) => segment.value == _type)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _type = typeSegments.first.value);
      });
    }

    if (!showRamadhan && _type == 'ramadhan') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _type != 'ramadhan') return;
        setState(() => _type = 'formal');
        _load(resetHistory: true);
      });
    }

    final studentCounts = _asMap(_studentStats['student_counts']);
    final teacherCounts = _asMap(_teacherStats['teacher_counts']);
    final teacherSummary = _asMapList(_teacherStats['teacher_summary']);
    final substituteHistory = _asMapList(_teacherStats['substitute_history']);
    final searchText = _search.trim().toLowerCase();

    final filteredTeacherSummary = teacherSummary.where((item) {
      if (searchText.isEmpty) return true;
      return _asString(
        item['name'],
        fallback: '',
      ).toLowerCase().contains(searchText);
    }).toList();

    final filteredSubstituteHistory = substituteHistory.where((item) {
      if (searchText.isEmpty) return true;
      final bag = [
        _asString(item['lesson'], fallback: ''),
        _asString(item['kelas'], fallback: ''),
        _asString(item['original_teacher'], fallback: ''),
        _asString(item['substitute_teacher'], fallback: ''),
      ].join(' ').toLowerCase();
      return bag.contains(searchText);
    }).toList();

    final moduleSelector = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canViewAbsensi)
          ChoiceChip(
            label: const Text('Absensi'),
            selected: _module == 'absensi',
            onSelected: (_) => setState(() => _module = 'absensi'),
          ),
        if (canViewHalaqoh)
          ChoiceChip(
            label: const Text('Halaqoh'),
            selected: _module == 'halaqoh',
            onSelected: (_) => setState(() => _module = 'halaqoh'),
          ),
      ],
    );

    if (!canViewAbsensi && !canViewHalaqoh) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Akun ini belum memiliki akses ke halaman statistik.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_module == 'halaqoh') {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: moduleSelector,
          ),
          const Expanded(child: HalaqohReportsScreen()),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(resetHistory: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          SectionHeader(
            eyebrow: 'CATATAN PENDIDIKAN',
            title: 'Rekapan Kehadiran',
            subtitle: '${_fmtUiDate(_startDate)} – ${_fmtUiDate(_endDate)}',
            icon: Icons.insights_rounded,
          ),
          const SizedBox(height: 20),
          moduleSelector,
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final segment in typeSegments)
                ChoiceChip(
                  label: segment.label!,
                  selected: _type == segment.value,
                  onSelected: (_) {
                    setState(() => _type = segment.value);
                    _load(resetHistory: true);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final segment in _scopeSegments)
                ChoiceChip(
                  label: segment.label!,
                  selected: _scope == segment.value,
                  onSelected: (_) => setState(() => _scope = segment.value),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SavedReportFilters(
            report: 'attendance',
            capture: () => {
              'type': _type,
              'scope': _scope,
              'teacher': _teacherFilter,
              'kelas': _kelasFilter,
              'gender': _genderFilter,
              'start': _fmtApiDate(_startDate),
              'end': _fmtApiDate(_endDate),
              'search': _search,
            },
            apply: (filters) {
              final type = filters['type']?.toString();
              if (!typeSegments.any((segment) => segment.value == type)) return;
              final start = DateTime.tryParse('${filters['start']}');
              final end = DateTime.tryParse('${filters['end']}');
              if (start == null || end == null || end.isBefore(start)) return;
              _searchDebounce?.cancel();
              setState(() {
                _type = type!;
                _scope =
                    ['all', 'student', 'teacher'].contains(filters['scope'])
                    ? filters['scope'] as String
                    : 'all';
                _teacherFilter = '${filters['teacher'] ?? ''}';
                _kelasFilter = '${filters['kelas'] ?? ''}';
                _genderFilter = '${filters['gender'] ?? ''}';
                _startDate = start;
                _endDate = end;
                _search = '${filters['search'] ?? ''}';
                _searchController.text = _search;
              });
              _load(resetHistory: true);
            },
          ),
          _buildFilterCard(),
          const SizedBox(height: 12),
          if (_showingOfflineData)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 18,
                    color: Color(0xFFB45309),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline • menampilkan statistik tersimpan',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _loadError!,
                style: const TextStyle(color: Color(0xFF855D20)),
              ),
            ),
          if (_loading &&
              (_studentStats.isNotEmpty || _teacherStats.isNotEmpty))
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(),
            ),
          if (!_loading && _studentStats.isEmpty && _teacherStats.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Rekapan belum tersedia untuk periode ini.',
                textAlign: TextAlign.center,
              ),
            )
          else if (_loading && _studentStats.isEmpty && _teacherStats.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            if (studentCounts.isNotEmpty &&
                (_scope == 'all' || _scope == 'student')) ...[
              _attendanceOverview(studentCounts),
              const SizedBox(height: 20),
            ],
            if (_scope == 'all' || _scope == 'student') ...[
              _buildSectionTitle(
                'Statistik Santri',
                'Riwayat absensi santri lengkap',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _countCard(
                    'Hadir',
                    _countValue(studentCounts, ['hadir', 'Hadir']),
                    const Color(0xFF16A34A),
                  ),
                  _countCard(
                    'Izin',
                    _countValue(studentCounts, ['izin', 'Izin']),
                    const Color(0xFF2563EB),
                  ),
                  _countCard(
                    'Sakit',
                    _countValue(studentCounts, ['sakit', 'Sakit']),
                    const Color(0xFFEA580C),
                  ),
                  _countCard(
                    'Alpa',
                    _countValue(studentCounts, [
                      'alpa',
                      'alpha',
                      'Alpa',
                      'Alpha',
                    ]),
                    const Color(0xFFDC2626),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final entry in {
                'Sakit': 'sakit_students',
                'Izin': 'izin_students',
                'Alpha': 'alpa_students',
              }.entries)
                StudentStatusCard(
                  key: ValueKey('$_type-$_statsQueryKey-${entry.key}'),
                  status: entry.key,
                  records: _studentStats[entry.value] as List? ?? const [],
                  onStudent:
                      hasAccess(
                        context.read<AuthController>().user,
                        'students.view',
                      )
                      ? (id) => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                StudentProgressScreen(studentId: id),
                          ),
                        )
                      : null,
                ),
              _buildHistoryCard(),
              const SizedBox(height: 16),
            ],
            if (_scope == 'all' || _scope == 'teacher') ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildSectionTitle(
                      'Statistik Guru',
                      'Ringkasan guru dan guru pengganti',
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: _teacherExporting
                        ? null
                        : _exportTeacherStatsPdf,
                    icon: _teacherExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: Text(_teacherExporting ? 'Proses...' : 'Export PDF'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _countCard(
                    'Hadir',
                    _countValue(teacherCounts, ['Hadir', 'hadir']),
                    const Color(0xFF16A34A),
                  ),
                  _countCard(
                    'Izin',
                    _countValue(teacherCounts, ['Izin', 'izin']),
                    const Color(0xFF2563EB),
                  ),
                  _countCard(
                    'Sakit',
                    _countValue(teacherCounts, ['Sakit', 'sakit']),
                    const Color(0xFFEA580C),
                  ),
                  _countCard(
                    'Alpha',
                    _countValue(teacherCounts, ['Alpha', 'alpha']),
                    const Color(0xFFDC2626),
                  ),
                  _countCard(
                    'Dinas',
                    _countValue(teacherCounts, ['Dinas', 'dinas']),
                    const Color(0xFFB7791F),
                  ),
                  _countCard(
                    'Subst.',
                    _countValue(teacherCounts, ['Substitute', 'substitute']),
                    const Color(0xFF9333EA),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTeacherSummaryCard(filteredTeacherSummary),
              const SizedBox(height: 12),
              _buildSubstituteHistoryCard(filteredSubstituteHistory),
              const SizedBox(height: 14),
              ReportDataTable(
                title: 'Riwayat Ketidakhadiran Guru',
                search: _search,
                columns: const [
                  'Tanggal',
                  'Guru',
                  'Pelajaran',
                  'Kelas',
                  'Status',
                  'Catatan',
                ],
                rows: _asMapList(_teacherStats['absence_history'])
                    .map(
                      (r) => [
                        _asString(r['date']),
                        _asString(r['teacher']),
                        _asString(r['lesson']),
                        _asString(r['kelas']),
                        _asString(
                          r['status'],
                        ).replaceAll('Dinas Luar', 'Dinas'),
                        _asString(r['notes']),
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

  Widget _attendanceOverview(Map<String, dynamic> counts) {
    final present = _countValue(counts, ['hadir', 'Hadir']);
    final total =
        present +
        _countValue(counts, ['izin', 'Izin']) +
        _countValue(counts, ['sakit', 'Sakit']) +
        _countValue(counts, ['alpa', 'alpha', 'Alpa', 'Alpha']);
    final ratio = total == 0 ? 0.0 : present / total;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFE7EEE6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'KEHADIRAN SANTRI',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${(ratio * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 40,
              color: Color(0xFF143E35),
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '$present hadir dari $total catatan absensi',
            style: const TextStyle(color: Color(0xFF3E584D)),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: const Color(0xFF143E35),
              backgroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadFilterOptions() async {
    if (_loadingFilters || _filterTeachers.isNotEmpty) return;
    _loadingFilters = true;
    final token = context.read<AuthController>().token;
    Future<List<Map<String, dynamic>>> options(String path) async {
      final rows = <Map<String, dynamic>>[];
      try {
        for (var page = 1; mounted; page++) {
          final response = await ApiClient.get(
            path,
            token: token,
            query: {'page': '$page', 'per_page': '100'},
            useOfflineCache: false,
          );
          final batch = _asMapList(response['data']);
          rows.addAll(batch);
          if (batch.isEmpty ||
              page >= _asInt(response['total_pages'], fallback: 1)) {
            break;
          }
        }
      } catch (_) {
        /* One unavailable picker must not block the other. */
      }
      return rows;
    }

    try {
      final results = await Future.wait([
        options('/attendance/assignable-teachers'),
        options('/kelas'),
      ]);
      if (mounted) {
        setState(() {
          _filterTeachers = results[0];
          _filterClasses = results[1];
        });
      }
    } finally {
      _loadingFilters = false;
    }
  }

  Widget _buildFilterCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ExpansionTile(
        onExpansionChanged: (expanded) {
          if (expanded) _loadFilterOptions();
        },
        tilePadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text(
          'Periode & pencarian',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: const Icon(Icons.tune_rounded),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(_fmtUiDate(_startDate)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: false),
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: Text(_fmtUiDate(_endDate)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'report-teacher-$_teacherFilter-${_filterTeachers.length}',
            ),
            initialValue:
                _filterTeachers.any((r) => '${r['id']}' == _teacherFilter)
                ? _teacherFilter
                : '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Guru'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Semua Guru')),
              ..._filterTeachers.map(
                (r) => DropdownMenuItem(
                  value: '${r['id']}',
                  child: Text(_asString(r['name'])),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => _teacherFilter = value ?? '');
              _load(resetHistory: true);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'report-class-$_kelasFilter-${_filterClasses.length}',
            ),
            initialValue:
                _filterClasses.any((r) => '${r['id']}' == _kelasFilter)
                ? _kelasFilter
                : '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Kelas'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Semua Kelas')),
              ..._filterClasses.map(
                (r) => DropdownMenuItem(
                  value: '${r['id']}',
                  child: Text('${r['nama']} ${r['tingkat'] ?? ''}'),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => _kelasFilter = value ?? '');
              _load(resetHistory: true);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _genderFilter,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Jenis Kelamin'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Semua (Banin & Banat)')),
              DropdownMenuItem(value: 'banin', child: Text('Banin')),
              DropdownMenuItem(value: 'banat', child: Text('Banat')),
            ],
            onChanged: (value) {
              setState(() => _genderFilter = value ?? '');
              _load(resetHistory: true);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Cari santri, guru, kelas, mapel...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                        setState(() => _search = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280))),
      ],
    );
  }

  Widget _buildHistoryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Riwayat Absensi Santri',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${_history.length} / $_historyTotal',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Belum ada riwayat absensi santri pada periode ini.'),
            )
          else
            ..._history.map((row) {
              final status = _asString(
                row['original_status'] ?? row['status'],
              ).replaceAll('Dinas Luar', 'Dinas');
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _statusColor(status).withValues(alpha: 0.12),
                  child: Icon(
                    Icons.person_outline,
                    color: _statusColor(status),
                    size: 18,
                  ),
                ),
                title: Text(
                  _asString(row['name']),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${_asString(row['kelas_nama'])} • ${_formatRowDate(row['tanggal'])}',
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: _statusColor(status),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            }),
          if (_historyTotal > _history.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _historyLoadingMore ? null : _loadMoreHistory,
                  child: _historyLoadingMore
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Muat lebih banyak'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTeacherSummaryCard(List<Map<String, dynamic>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Text(
              'Ringkasan Kehadiran Guru',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Belum ada data kehadiran guru pada periode ini.'),
            )
          else
            ...rows.map((row) {
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.school_outlined, size: 18),
                ),
                title: Text(
                  _asString(row['name']),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _miniStat(
                      'H',
                      _asInt(row['hadir']),
                      const Color(0xFF16A34A),
                    ),
                    _miniStat(
                      'I',
                      _asInt(row['izin']),
                      const Color(0xFF2563EB),
                    ),
                    _miniStat(
                      'S',
                      _asInt(row['sakit']),
                      const Color(0xFFEA580C),
                    ),
                    _miniStat(
                      'A',
                      _asInt(row['alpha']),
                      const Color(0xFFDC2626),
                    ),
                    _miniStat(
                      'Dinas',
                      _asInt(row['dinas']),
                      const Color(0xFFB7791F),
                    ),
                    _miniStat(
                      'Sub',
                      _asInt(row['substitute']),
                      const Color(0xFF9333EA),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSubstituteHistoryCard(List<Map<String, dynamic>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Text(
              'Riwayat Guru Pengganti',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Belum ada riwayat guru pengganti pada periode ini.'),
            )
          else
            ...rows.map((row) {
              final status = _asString(row['original_status']);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _statusColor(status).withValues(alpha: 0.12),
                  child: Icon(
                    Icons.swap_horiz,
                    color: _statusColor(status),
                    size: 18,
                  ),
                ),
                title: Text(
                  _asString(row['lesson']),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${_asString(row['kelas'])} • ${_formatRowDate(row['date'])}\n${_asString(row['original_teacher'])} → ${_asString(row['substitute_teacher'])}',
                ),
                isThreeLine: true,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: _statusColor(status),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _countCard(String label, int value, Color color) {
    return Container(
      width: (MediaQuery.sizeOf(context).width - 50) / 2,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            '$value',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
