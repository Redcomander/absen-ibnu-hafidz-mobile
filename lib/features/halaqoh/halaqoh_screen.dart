import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_controller.dart';
import '../settings/app_settings_controller.dart';

const List<String> _halaqohSessions = ['Shubuh', 'Ashar', 'Isya'];

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return [];
  return value.map(_asMap).toList();
}

String _asString(dynamic value, {String fallback = '-'}) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'hadir':
      return const Color(0xFF16A34A);
    case 'izin':
      return const Color(0xFF2563EB);
    case 'sakit':
      return const Color(0xFFEA580C);
    case 'alpha':
    case 'alpa':
      return const Color(0xFFDC2626);
    default:
      return const Color(0xFF6B7280);
  }
}

String _formatDisplayDate(dynamic raw) {
  final text = raw?.toString() ?? '';
  if (text.isEmpty) return '-';
  try {
    return DateFormat('dd MMM yyyy').format(DateTime.parse(text));
  } catch (_) {
    return text;
  }
}

class HalaqohScreen extends StatefulWidget {
  final String initialTab;
  final bool showHeader;
  final Set<String> allowedTabs;

  const HalaqohScreen({
    super.key,
    this.initialTab = 'groups',
    this.showHeader = true,
    this.allowedTabs = const {'groups', 'stats', 'history'},
  });

  @override
  State<HalaqohScreen> createState() => _HalaqohScreenState();
}

class _HalaqohScreenState extends State<HalaqohScreen> {
  late String _mainTab;
  String _historyTab = 'students';

  bool _loadingGroups = true;
  bool _loadingStats = true;
  bool _loadingHistory = true;
  bool _showingOfflineData = false;
  bool? _wasOnline;
  bool _exportingStudentReport = false;
  bool _exportingTeacherReport = false;

  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _selectedGender = '';
  String _teacherFilter = '';
  String _groupSearch = '';
  String _historySession = '';
  String _historyStatus = '';

  late DateTime _rangeStartDate;
  late DateTime _rangeEndDate;

  bool _canFilterByDate = false;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _badges = [];
  List<Map<String, dynamic>> _substituteInfos = [];
  List<Map<String, dynamic>> _accessInfos = [];
  List<Map<String, dynamic>> _sessionTimes = [];
  List<Map<String, dynamic>> _teachers = [];

  Map<String, dynamic> _studentStats = {};
  Map<String, dynamic> _teacherStats = {};

  List<Map<String, dynamic>> _studentHistory = [];
  List<Map<String, dynamic>> _teacherHistory = [];
  int _studentPage = 1;
  int _studentTotalPages = 1;
  int _teacherPage = 1;
  int _teacherTotalPages = 1;

  @override
  void initState() {
    super.initState();
    _mainTab = widget.allowedTabs.contains(widget.initialTab)
        ? widget.initialTab
        : widget.allowedTabs.first;
    final now = DateTime.now();
    _rangeStartDate = DateTime(now.year, now.month, 1);
    _rangeEndDate = now;
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isOnline = context.watch<AppSettingsController>().isOnline;
    final isBusy = _loadingGroups || _loadingStats || _loadingHistory;
    if (_wasOnline == false && isOnline && !isBusy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshCurrentTab();
        }
      });
    }
    _wasOnline = isOnline;
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadAssignments(),
      _loadStats(),
      _loadHistory(),
    ]);
  }

  Future<void> _loadAssignments() async {
    if (mounted) setState(() => _loadingGroups = true);
    try {
      final token = context.read<AuthController>().token;
      final res = await ApiClient.get(
        '/halaqoh/assignments',
        token: token,
        query: {'date': _selectedDate},
      );

      _showingOfflineData = res['__from_cache'] == true;
      _groups = _asMapList(res['groups']);
      _badges = _asMapList(res['badges']);
      _substituteInfos = _asMapList(res['substitute_infos']);
      _accessInfos = _asMapList(res['access_infos']);
      _sessionTimes = _asMapList(res['session_times']);
      _canFilterByDate = res['can_filter_by_date'] == true;
      _selectedDate = _asString(res['selected_date'], fallback: _selectedDate);
    } catch (e) {
      _showingOfflineData = _groups.isNotEmpty;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat halaqoh: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  Future<void> _loadStats() async {
    if (mounted) setState(() => _loadingStats = true);
    try {
      final token = context.read<AuthController>().token;
      final query = {
        'start_date': DateFormat('yyyy-MM-dd').format(_rangeStartDate),
        'end_date': DateFormat('yyyy-MM-dd').format(_rangeEndDate),
        if (_teacherFilter.isNotEmpty) 'teacher_id': _teacherFilter,
        if (_selectedGender.isNotEmpty) 'gender': _selectedGender,
      };

      final results = await Future.wait([
        ApiClient.get('/halaqoh/statistics/students',
            token: token, query: query),
        ApiClient.get('/halaqoh/statistics/teachers',
            token: token, query: query),
      ]);

      _showingOfflineData = results.any(
        (result) => _asMap(result)['__from_cache'] == true,
      );
      _studentStats = _asMap(results[0]);
      _teacherStats = _asMap(results[1]);

      final teachersFromApi = _asMapList(_studentStats['teachers']);
      if (teachersFromApi.isNotEmpty) {
        _teachers = teachersFromApi;
      } else if (_teachers.isEmpty) {
        final seen = <int>{};
        _teachers = _groups
            .where((group) => seen.add(_asInt(group['teacher_id'])))
            .map((group) => {
                  'id': group['teacher_id'],
                  'name': group['teacher_name'],
                })
            .toList();
      }
    } catch (e) {
      _showingOfflineData =
          _studentStats.isNotEmpty || _teacherStats.isNotEmpty;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat statistik halaqoh: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _loadHistory() async {
    if (mounted) setState(() => _loadingHistory = true);
    try {
      final token = context.read<AuthController>().token;
      final query = {
        'page': _historyTab == 'students' ? '$_studentPage' : '$_teacherPage',
        'per_page': '15',
        'start_date': DateFormat('yyyy-MM-dd').format(_rangeStartDate),
        'end_date': DateFormat('yyyy-MM-dd').format(_rangeEndDate),
        if (_historySession.isNotEmpty) 'session': _historySession,
        if (_historyStatus.isNotEmpty) 'status': _historyStatus,
        if (_teacherFilter.isNotEmpty && _historyTab == 'teachers')
          'teacher_id': _teacherFilter,
      };

      if (_historyTab == 'students') {
        final res = await ApiClient.get(
          '/halaqoh/history/students',
          token: token,
          query: query,
        );
        _showingOfflineData = res['__from_cache'] == true;
        _studentHistory = _asMapList(res['data']);
        _studentTotalPages = _asInt(res['total_pages'], fallback: 1);
      } else {
        final res = await ApiClient.get(
          '/halaqoh/history/teachers',
          token: token,
          query: query,
        );
        _showingOfflineData = res['__from_cache'] == true;
        _teacherHistory = _asMapList(res['data']);
        _teacherTotalPages = _asInt(res['total_pages'], fallback: 1);
      }
    } catch (e) {
      _showingOfflineData =
          _studentHistory.isNotEmpty || _teacherHistory.isNotEmpty;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat riwayat halaqoh: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _pickSingleDate() async {
    final initial = DateTime.tryParse(_selectedDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;

    setState(() {
      _selectedDate = DateFormat('yyyy-MM-dd').format(picked);
    });
    await _loadAssignments();
  }

  Future<void> _pickRangeDate({required bool start}) async {
    final initial = start ? _rangeStartDate : _rangeEndDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;

    setState(() {
      if (start) {
        _rangeStartDate = picked;
        if (_rangeStartDate.isAfter(_rangeEndDate)) {
          _rangeEndDate = picked;
        }
      } else {
        _rangeEndDate = picked;
        if (_rangeEndDate.isBefore(_rangeStartDate)) {
          _rangeStartDate = picked;
        }
      }
    });

    await Future.wait([_loadStats(), _loadHistory()]);
  }

  Future<void> _refreshCurrentTab() async {
    switch (_mainTab) {
      case 'groups':
        await _loadAssignments();
        break;
      case 'stats':
        await _loadStats();
        break;
      case 'history':
        await _loadHistory();
        break;
    }
  }

  Future<void> _exportHalaqohReport({
    required String scope,
    required String format,
  }) async {
    final isStudent = scope == 'student';
    if (isStudent ? _exportingStudentReport : _exportingTeacherReport) return;

    final messenger = ScaffoldMessenger.of(context);
    final token = context.read<AuthController>().token;

    setState(() {
      if (isStudent) {
        _exportingStudentReport = true;
      } else {
        _exportingTeacherReport = true;
      }
    });

    try {
      final file = await ApiClient.download(
        '/halaqoh/export/$scope/$format',
        token: token,
        query: {
          'start_date': DateFormat('yyyy-MM-dd').format(_rangeStartDate),
          'end_date': DateFormat('yyyy-MM-dd').format(_rangeEndDate),
          if (_teacherFilter.isNotEmpty) 'teacher_id': _teacherFilter,
          if (_selectedGender.isNotEmpty) 'gender': _selectedGender,
        },
      );

      final fileExt = format == 'excel' ? 'xlsx' : 'pdf';
      final fallbackName =
          'rekapan_halaqoh_${scope}_${DateFormat('yyyy-MM-dd').format(_rangeStartDate)}_${DateFormat('yyyy-MM-dd').format(_rangeEndDate)}.$fileExt';
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

      final savedFile =
          File('${exportDir.path}${Platform.pathSeparator}$fileName');
      await savedFile.writeAsBytes(file.bytes, flush: true);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export berhasil'),
          content: Text(
            '${isStudent ? 'Rekap santri' : 'Rekap guru'} tersimpan di:\n\n${savedFile.path}',
          ),
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
        SnackBar(content: Text('Gagal export: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyiapkan export: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (isStudent) {
            _exportingStudentReport = false;
          } else {
            _exportingTeacherReport = false;
          }
        });
      }
    }
  }

  Map<String, dynamic> _badgeForTeacher(int teacherId) {
    return _badges.firstWhere(
      (item) => _asInt(item['teacher_id']) == teacherId,
      orElse: () => <String, dynamic>{},
    );
  }

  Map<String, dynamic> _accessForTeacher(int teacherId) {
    return _accessInfos.firstWhere(
      (item) => _asInt(item['teacher_id']) == teacherId,
      orElse: () => <String, dynamic>{},
    );
  }

  List<Map<String, dynamic>> _substitutesForTeacher(int teacherId) {
    return _substituteInfos
        .where((item) => _asInt(item['teacher_id']) == teacherId)
        .toList();
  }

  List<Map<String, dynamic>> get _filteredGroups {
    final query = _groupSearch.trim().toLowerCase();

    return _groups
        .map((group) {
          final assignments =
              _asMapList(group['assignments']).where((assignment) {
            final student = _asMap(assignment['student']);
            final teacher = _asMap(assignment['teacher']);
            final gender = _asString(student['jenis_kelamin'], fallback: '');

            final genderOk = _selectedGender.isEmpty ||
                (_selectedGender == 'banin' &&
                    gender.toLowerCase().contains('laki')) ||
                (_selectedGender == 'banat' &&
                    gender.toLowerCase().contains('perempuan'));

            if (!genderOk) return false;
            if (query.isEmpty) return true;

            final bag = [
              _asString(student['nama_lengkap'], fallback: ''),
              _asString(teacher['name'], fallback: ''),
              _asString(group['teacher_name'], fallback: ''),
            ].join(' ').toLowerCase();

            return bag.contains(query);
          }).toList();

          return {
            ...group,
            'assignments': assignments,
          };
        })
        .where((group) => _asMapList(group['assignments']).isNotEmpty)
        .toList();
  }

  List<String> get _historyStatusOptions => _historyTab == 'students'
      ? const ['hadir', 'izin', 'sakit', 'alpa']
      : const ['Hadir', 'Izin', 'Sakit', 'Alpha'];

  List<ButtonSegment<String>> _mainSegments() {
    final segments = <ButtonSegment<String>>[];
    if (widget.allowedTabs.contains('groups')) {
      segments
          .add(const ButtonSegment(value: 'groups', label: Text('Kelompok')));
    }
    if (widget.allowedTabs.contains('stats')) {
      segments
          .add(const ButtonSegment(value: 'stats', label: Text('Statistik')));
    }
    if (widget.allowedTabs.contains('history')) {
      segments
          .add(const ButtonSegment(value: 'history', label: Text('Riwayat')));
    }
    return segments;
  }

  Future<void> _openStudentAttendance(Map<String, dynamic> group) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HalaqohStudentAttendanceSheet(
        group: group,
        date: _selectedDate,
      ),
    );

    if (updated == true) {
      await Future.wait([_loadAssignments(), _loadHistory(), _loadStats()]);
    }
  }

  Future<void> _openTeacherAttendance(Map<String, dynamic> group) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HalaqohTeacherAttendanceSheet(
        group: group,
        date: _selectedDate,
      ),
    );

    if (updated == true) {
      await Future.wait([_loadAssignments(), _loadHistory(), _loadStats()]);
    }
  }

  Future<void> _openSubstitute(Map<String, dynamic> group) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HalaqohSubstituteSheet(
        group: group,
        date: _selectedDate,
        teachers: _teachers,
      ),
    );

    if (updated == true) {
      await Future.wait([_loadAssignments(), _loadHistory()]);
    }
  }

  Future<void> _cancelSubstituteSession(
    Map<String, dynamic> group,
    String session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan guru pengganti?'),
        content: Text('Guru pengganti untuk sesi $session akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tutup'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final token = context.read<AuthController>().token;
      final assignments = _asMapList(group['assignments']);
      final firstAssignment =
          assignments.isEmpty ? <String, dynamic>{} : assignments.first;
      final assignmentId = _asInt(firstAssignment['id']);
      if (assignmentId == 0) return;

      await ApiClient.delete(
        '/halaqoh/assignments/$assignmentId/substitute',
        token: token,
        body: {
          'date': _selectedDate,
          'sessions': [session],
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Pengganti sesi $session berhasil dibatalkan')),
        );
      }
      await Future.wait([_loadAssignments(), _loadHistory()]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentChart = _asMap(_studentStats['chart_data']);
    final teacherChart = _asMap(_teacherStats['chart_data']);

    final bottomPadding = MediaQuery.of(context).padding.bottom + 32;

    return RefreshIndicator(
      onRefresh: _refreshCurrentTab,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
        children: [
          if (widget.showHeader) ...[
            const Text(
              'Halaqoh',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Kelompok, absensi, statistik, dan riwayat halaqoh.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
          ],
          if (_mainSegments().length > 1) ...[
            SegmentedButton<String>(
              segments: _mainSegments(),
              selected: {_mainTab},
              onSelectionChanged: (value) {
                setState(() => _mainTab = value.first);
              },
            ),
            const SizedBox(height: 12),
          ],
          if (_showingOfflineData) ...[
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
                  Icon(Icons.cloud_off_rounded,
                      size: 18, color: Color(0xFFB45309)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline • menampilkan data halaqoh tersimpan',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_mainTab == 'groups') ...[
            _buildGroupFilterCard(),
            const SizedBox(height: 12),
            _buildSessionTimes(),
            const SizedBox(height: 12),
            if (_loadingGroups)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_filteredGroups.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Belum ada data halaqoh yang cocok.'),
                ),
              )
            else
              ..._filteredGroups.map(_buildGroupCard),
          ] else if (_mainTab == 'stats') ...[
            _buildStatsFilterCard(),
            const SizedBox(height: 12),
            if (_loadingStats)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Statistik Santri'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _exportingStudentReport
                            ? null
                            : () => _exportHalaqohReport(
                                  scope: 'student',
                                  format: 'pdf',
                                ),
                        icon: _exportingStudentReport
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined,
                                size: 18),
                        label: const Text('Export PDF'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _exportingStudentReport
                            ? null
                            : () => _exportHalaqohReport(
                                  scope: 'student',
                                  format: 'excel',
                                ),
                        icon: const Icon(Icons.grid_on_rounded, size: 18),
                        label: const Text('Export Excel'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metricCard('Hadir', _asInt(studentChart['hadir']),
                      const Color(0xFF16A34A)),
                  _metricCard('Izin', _asInt(studentChart['izin']),
                      const Color(0xFF2563EB)),
                  _metricCard('Sakit', _asInt(studentChart['sakit']),
                      const Color(0xFFEA580C)),
                  _metricCard('Alpa', _asInt(studentChart['alpa']),
                      const Color(0xFFDC2626)),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Statistik Guru'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _exportingTeacherReport
                            ? null
                            : () => _exportHalaqohReport(
                                  scope: 'teacher',
                                  format: 'pdf',
                                ),
                        icon: _exportingTeacherReport
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined,
                                size: 18),
                        label: const Text('Export PDF'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _exportingTeacherReport
                            ? null
                            : () => _exportHalaqohReport(
                                  scope: 'teacher',
                                  format: 'excel',
                                ),
                        icon: const Icon(Icons.grid_on_rounded, size: 18),
                        label: const Text('Export Excel'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metricCard('Hadir', _asInt(teacherChart['Hadir']),
                      const Color(0xFF16A34A)),
                  _metricCard('Izin', _asInt(teacherChart['Izin']),
                      const Color(0xFF2563EB)),
                  _metricCard('Sakit', _asInt(teacherChart['Sakit']),
                      const Color(0xFFEA580C)),
                  _metricCard('Alpha', _asInt(teacherChart['Alpha']),
                      const Color(0xFFDC2626)),
                ],
              ),
            ],
          ] else ...[
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'students', label: Text('Santri')),
                ButtonSegment(value: 'teachers', label: Text('Guru')),
              ],
              selected: {_historyTab},
              onSelectionChanged: (value) async {
                setState(() {
                  _historyTab = value.first;
                  _historyStatus = '';
                });
                await _loadHistory();
              },
            ),
            const SizedBox(height: 12),
            _buildHistoryFilterCard(),
            const SizedBox(height: 12),
            if (_loadingHistory)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_historyTab == 'students')
              _buildStudentHistoryCard()
            else
              _buildTeacherHistoryCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupFilterCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filter Kelompok',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (_canFilterByDate)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickSingleDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Tanggal: ${_formatDisplayDate(_selectedDate)}'),
                ),
              ),
            ),
          TextField(
            onChanged: (value) => setState(() => _groupSearch = value),
            decoration: const InputDecoration(
              hintText: 'Cari guru atau santri...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedGender,
            decoration: const InputDecoration(labelText: 'Gender santri'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Semua')),
              DropdownMenuItem(value: 'banin', child: Text('Banin')),
              DropdownMenuItem(value: 'banat', child: Text('Banat')),
            ],
            onChanged: (value) {
              setState(() => _selectedGender = value ?? '');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatsFilterCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickRangeDate(start: true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                      _formatDisplayDate(_rangeStartDate.toIso8601String())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickRangeDate(start: false),
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label:
                      Text(_formatDisplayDate(_rangeEndDate.toIso8601String())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _teacherFilter,
            decoration: const InputDecoration(labelText: 'Guru halaqoh'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Semua guru')),
              ..._teachers.map(
                (teacher) => DropdownMenuItem(
                  value: teacher['id']?.toString() ?? '',
                  child: Text(_asString(teacher['name'])),
                ),
              )
            ],
            onChanged: (value) {
              setState(() => _teacherFilter = value ?? '');
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedGender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Semua')),
              DropdownMenuItem(value: 'banin', child: Text('Banin')),
              DropdownMenuItem(value: 'banat', child: Text('Banat')),
            ],
            onChanged: (value) {
              setState(() => _selectedGender = value ?? '');
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _loadStats,
              icon: const Icon(Icons.filter_alt_outlined),
              label: const Text('Tampilkan data'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryFilterCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickRangeDate(start: true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                      _formatDisplayDate(_rangeStartDate.toIso8601String())),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickRangeDate(start: false),
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label:
                      Text(_formatDisplayDate(_rangeEndDate.toIso8601String())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _historySession,
            decoration: const InputDecoration(labelText: 'Sesi'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Semua sesi')),
              DropdownMenuItem(value: 'Shubuh', child: Text('Shubuh')),
              DropdownMenuItem(value: 'Ashar', child: Text('Ashar')),
              DropdownMenuItem(value: 'Isya', child: Text('Isya')),
            ],
            onChanged: (value) async {
              setState(() => _historySession = value ?? '');
              await _loadHistory();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _historyStatus,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Semua status')),
              ..._historyStatusOptions.map(
                (status) =>
                    DropdownMenuItem(value: status, child: Text(status)),
              ),
            ],
            onChanged: (value) async {
              setState(() => _historyStatus = value ?? '');
              await _loadHistory();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTimes() {
    if (_sessionTimes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Jam Sesi Halaqoh',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sessionTimes.map((item) {
              final active = item['is_active'] == true;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: (active
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF6B7280))
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_asString(item['session'])} • ${_asString(item['start'])}-${_asString(item['end'])}',
                  style: TextStyle(
                    color: active
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final teacherId = _asInt(group['teacher_id']);
    final currentUserId = _asInt(context.read<AuthController>().user?['id']);
    final assignments = _asMapList(group['assignments']);
    final access = _accessForTeacher(teacherId);
    final badgeInfo = _badgeForTeacher(teacherId);
    final studentBadges = _asMapList(badgeInfo['student_attendance']);
    final teacherAttendance = _asMap(badgeInfo['teacher_attendance']);
    final subs = _substitutesForTeacher(teacherId);
    final canOpenStudentAttendance = access['can_access_attendance'] == true;
    final canOpenTeacherAttendance = access['can_manage'] == true ||
        access['is_substitute'] == true ||
        currentUserId == teacherId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _asString(group['teacher_name']),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${assignments.length} santri',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                if (access['is_substitute'] == true)
                  _labelChip('Pengganti', const Color(0xFF2563EB)),
                if (access['is_helper'] == true) ...[
                  const SizedBox(width: 6),
                  _labelChip('Pendamping', const Color(0xFF9333EA)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (studentBadges.isNotEmpty) ...[
              const Text(
                'Status Absen Santri',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: studentBadges.map((item) {
                  final completed = item['completed'] == true;
                  final partial = item['partial'] == true;
                  final color = completed
                      ? const Color(0xFF16A34A)
                      : partial
                          ? const Color(0xFFD97706)
                          : const Color(0xFF9CA3AF);
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_asString(item['session'])} ${_asInt(item['count'])}/${_asInt(item['total'])}',
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.w800),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],
            const Text(
              'Status Absen Guru',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _halaqohSessions.map((session) {
                final status =
                    _asString(teacherAttendance[session], fallback: 'Belum');
                final color = status == 'Belum'
                    ? const Color(0xFF6B7280)
                    : _statusColor(status);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$session • $status',
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                );
              }).toList(),
            ),
            if (subs.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Guru Pengganti',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              ...subs.map(
                (item) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_asString(item['session'])}: ${_asString(item['substitute_name'])} • ${_asString(item['status'])}',
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ),
                      if (access['can_manage'] == true)
                        IconButton(
                          tooltip: 'Batalkan pengganti',
                          onPressed: () => _cancelSubstituteSession(
                            group,
                            _asString(item['session'], fallback: ''),
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canOpenStudentAttendance)
                  FilledButton.tonalIcon(
                    onPressed: () => _openStudentAttendance(group),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Absen santri'),
                  ),
                if (canOpenTeacherAttendance)
                  FilledButton.tonalIcon(
                    onPressed: () => _openTeacherAttendance(group),
                    icon: const Icon(Icons.person_pin_circle_outlined),
                    label: const Text('Absen guru'),
                  ),
                if (access['can_manage'] == true)
                  FilledButton.tonalIcon(
                    onPressed: () => _openSubstitute(group),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Pengganti'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: (assignments.length * 92.0).clamp(140.0, 260.0),
              child: ListView.separated(
                itemCount: assignments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final assignment = assignments[index];
                  final student = _asMap(assignment['student']);
                  final helper = _asMap(assignment['helper_teacher']);
                  final sessions = _asMap(assignment['has_attendance_today']);
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _asString(student['nama_lengkap']),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'NIS: ${_asString(student['nis'] ?? student['nisn'])}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        if (helper.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Pendamping: ${_asString(helper['name'])}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _halaqohSessions.map((session) {
                            final done = sessions[session] == true;
                            return _smallSessionChip(session, done);
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentHistoryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          if (_studentHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Belum ada riwayat absensi santri halaqoh.'),
            )
          else
            ..._studentHistory.map((row) {
              final assignment = _asMap(row['halaqoh_assignment']);
              final student = _asMap(assignment['student']);
              final teacher = _asMap(assignment['teacher']);
              final status = _asString(row['status']);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _statusColor(status).withValues(alpha: 0.12),
                  child: Icon(Icons.person_outline,
                      color: _statusColor(status), size: 18),
                ),
                title: Text(
                  _asString(student['nama_lengkap']),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${_formatDisplayDate(row['date'])} • ${_asString(row['session'])}\n${_asString(teacher['name'])}',
                ),
                isThreeLine: true,
                trailing: _labelChip(status, _statusColor(status)),
              );
            }),
          _historyPagination(
            page: _studentPage,
            totalPages: _studentTotalPages,
            onPrev: _studentPage > 1
                ? () async {
                    setState(() => _studentPage--);
                    await _loadHistory();
                  }
                : null,
            onNext: _studentPage < _studentTotalPages
                ? () async {
                    setState(() => _studentPage++);
                    await _loadHistory();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherHistoryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          if (_teacherHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Belum ada riwayat absensi guru halaqoh.'),
            )
          else
            ..._teacherHistory.map((row) {
              final teacher = _asMap(row['teacher']);
              final status = _asString(row['status']);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _statusColor(status).withValues(alpha: 0.12),
                  child: Icon(Icons.badge_outlined,
                      color: _statusColor(status), size: 18),
                ),
                title: Text(
                  _asString(teacher['name']),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${_formatDisplayDate(row['date'])} • ${_asString(row['session'])}\n${_asString(row['notes'])}',
                ),
                isThreeLine: true,
                trailing: _labelChip(status, _statusColor(status)),
              );
            }),
          _historyPagination(
            page: _teacherPage,
            totalPages: _teacherTotalPages,
            onPrev: _teacherPage > 1
                ? () async {
                    setState(() => _teacherPage--);
                    await _loadHistory();
                  }
                : null,
            onNext: _teacherPage < _teacherTotalPages
                ? () async {
                    setState(() => _teacherPage++);
                    await _loadHistory();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _historyPagination({
    required int page,
    required int totalPages,
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onPrev,
              child: const Text('Sebelumnya'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('$page / $totalPages'),
          ),
          Expanded(
            child: OutlinedButton(
              onPressed: onNext,
              child: const Text('Selanjutnya'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String label) {
    return Text(
      label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
    );
  }

  Widget _metricCard(String label, int value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('$value',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _smallSessionChip(String label, bool done) {
    final color = done ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  Widget _labelChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _HalaqohStudentAttendanceSheet extends StatefulWidget {
  final Map<String, dynamic> group;
  final String date;

  const _HalaqohStudentAttendanceSheet({
    required this.group,
    required this.date,
  });

  @override
  State<_HalaqohStudentAttendanceSheet> createState() =>
      _HalaqohStudentAttendanceSheetState();
}

class _HalaqohStudentAttendanceSheetState
    extends State<_HalaqohStudentAttendanceSheet> {
  bool _loading = true;
  bool _saving = false;
  String _activeSession = _halaqohSessions.first;
  final Map<String, List<Map<String, dynamic>>> _recordsBySession = {
    for (final session in _halaqohSessions) session: <Map<String, dynamic>>[],
  };
  final Set<String> _submittedSessions = <String>{};
  Map<String, dynamic> _substituteMap = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = context.read<AuthController>().token;
      final assignments = _asMapList(widget.group['assignments']);
      final firstAssignment =
          assignments.isEmpty ? <String, dynamic>{} : assignments.first;
      final assignmentId = _asInt(firstAssignment['id']);
      if (assignmentId == 0) return;

      final res = await ApiClient.get(
        '/halaqoh/attendance/$assignmentId',
        token: token,
        query: {'date': widget.date},
      );

      final allAssignments = _asMapList(res['assignments']);
      final attendanceMap = _asMap(res['attendance_map']);
      _substituteMap = _asMap(res['substitute_map']);

      for (final session in _halaqohSessions) {
        final rows = allAssignments.map((assignment) {
          final studentId = _asInt(assignment['student_id']);
          final key = '${_asInt(assignment['id'])}_${session}_$studentId';
          final existing = _asMap(attendanceMap[key]);
          if (existing.isNotEmpty) {
            _submittedSessions.add(session);
          }
          return {
            'halaqoh_assignment_id': _asInt(assignment['id']),
            'student_id': studentId,
            'student_name':
                _asString(_asMap(assignment['student'])['nama_lengkap']),
            'status': _asString(existing['status'], fallback: 'hadir'),
            'notes': _asString(existing['notes'], fallback: ''),
          };
        }).toList();
        _recordsBySession[session] = rows;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat absensi santri: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = context.read<AuthController>().token;
      final currentRecords = _recordsBySession[_activeSession] ?? [];
      final res = await ApiClient.post(
        '/halaqoh/attendance/session/$_activeSession',
        token: token,
        body: {
          'date': widget.date,
          'records': currentRecords,
        },
      );

      _submittedSessions.add(_activeSession);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  _asString(res['message'], fallback: 'Berhasil disimpan'))),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRecords = _recordsBySession[_activeSession] ?? [];
    final substituteInfo = _asMap(_substituteMap[_activeSession]);
    final media = MediaQuery.of(context);

    return SafeArea(
      child: Container(
        height: media.size.height * 0.84,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            const Icon(Icons.drag_handle_rounded, color: Colors.grey),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Absensi Santri Halaqoh',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_asString(widget.group['teacher_name'])} • ${_formatDisplayDate(widget.date)}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: _halaqohSessions
                    .map(
                      (session) => ButtonSegment(
                        value: session,
                        label: Text(
                          _submittedSessions.contains(session)
                              ? '$session ✓'
                              : session,
                        ),
                      ),
                    )
                    .toList(),
                selected: {_activeSession},
                onSelectionChanged: (value) {
                  setState(() => _activeSession = value.first);
                },
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (substituteInfo.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                        ),
                        child: Text(
                          'Guru pengganti: ${_asString(_asMap(substituteInfo['substitute_teacher'])['name'], fallback: _asString(substituteInfo['substitute_name']))}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ...currentRecords.map((record) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _asString(record['student_name']),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: const ['hadir', 'izin', 'sakit', 'alpa']
                                  .map(
                                (status) => status,
                              )
                                  .map((status) {
                                final selected = record['status'] == status;
                                final color = _statusColor(status);
                                return ChoiceChip(
                                  label: Text(status.toUpperCase()),
                                  selected: selected,
                                  onSelected: (_) {
                                    setState(() => record['status'] = status);
                                  },
                                  selectedColor: color.withValues(alpha: 0.15),
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? color
                                        : const Color(0xFF6B7280),
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue:
                                  _asString(record['notes'], fallback: ''),
                              onChanged: (value) => record['notes'] = value,
                              decoration:
                                  const InputDecoration(labelText: 'Catatan'),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Tutup'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Simpan $_activeSession'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HalaqohTeacherAttendanceSheet extends StatefulWidget {
  final Map<String, dynamic> group;
  final String date;

  const _HalaqohTeacherAttendanceSheet({
    required this.group,
    required this.date,
  });

  @override
  State<_HalaqohTeacherAttendanceSheet> createState() =>
      _HalaqohTeacherAttendanceSheetState();
}

class _HalaqohTeacherAttendanceSheetState
    extends State<_HalaqohTeacherAttendanceSheet> {
  bool _loading = true;
  bool _saving = false;
  String _activeSession = _halaqohSessions.first;
  List<Map<String, dynamic>> _sessionInfos = [];
  String _status = 'Hadir';
  String _notes = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = context.read<AuthController>().token;
      final assignments = _asMapList(widget.group['assignments']);
      final firstAssignment =
          assignments.isEmpty ? <String, dynamic>{} : assignments.first;
      final assignmentId = _asInt(firstAssignment['id']);
      if (assignmentId == 0) return;

      final res = await ApiClient.get(
        '/halaqoh/teacher-attendance/$assignmentId',
        token: token,
        query: {'date': widget.date},
      );
      _sessionInfos = _asMapList(res['session_infos']);
      _syncForm();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat absensi guru: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _syncForm() {
    final info = _sessionInfos.firstWhere(
      (item) => _asString(item['session']) == _activeSession,
      orElse: () => <String, dynamic>{},
    );
    _status = _asString(info['status'], fallback: 'Hadir');
    _notes = _asString(info['notes'], fallback: '');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = context.read<AuthController>().token;
      final assignments = _asMapList(widget.group['assignments']);
      final firstAssignment =
          assignments.isEmpty ? <String, dynamic>{} : assignments.first;
      final assignmentId = _asInt(firstAssignment['id']);
      if (assignmentId == 0) return;

      final res = await ApiClient.postMultipart(
        '/halaqoh/teacher-attendance/$assignmentId/session/$_activeSession',
        token: token,
        fields: {
          'status': _status,
          'notes': _notes,
          'date': widget.date,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  _asString(res['message'], fallback: 'Berhasil disimpan'))),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final currentInfo = _sessionInfos.firstWhere(
      (item) => _asString(item['session']) == _activeSession,
      orElse: () => <String, dynamic>{},
    );

    return SafeArea(
      child: Container(
        height: media.size.height * 0.70,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            const Icon(Icons.drag_handle_rounded, color: Colors.grey),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Absensi Guru Halaqoh',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: _halaqohSessions
                    .map((session) =>
                        ButtonSegment(value: session, label: Text(session)))
                    .toList(),
                selected: {_activeSession},
                onSelectionChanged: (value) {
                  setState(() {
                    _activeSession = value.first;
                    _syncForm();
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (currentInfo['is_substitute'] == true)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                        ),
                        child: Text(
                          'Mengisi sebagai pengganti • ${_asString(currentInfo['substitute_reason'])}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    Text(
                      'Guru: ${_asString(_asMap(currentInfo['effective_teacher'])['name'], fallback: _asString(widget.group['teacher_name']))}',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'Hadir', child: Text('Hadir')),
                        DropdownMenuItem(value: 'Izin', child: Text('Izin')),
                        DropdownMenuItem(value: 'Sakit', child: Text('Sakit')),
                        DropdownMenuItem(value: 'Alpha', child: Text('Alpha')),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? 'Hadir'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _notes,
                      onChanged: (value) => _notes = value,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Catatan'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Tutup'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Simpan $_activeSession'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HalaqohSubstituteSheet extends StatefulWidget {
  final Map<String, dynamic> group;
  final String date;
  final List<Map<String, dynamic>> teachers;

  const _HalaqohSubstituteSheet({
    required this.group,
    required this.date,
    required this.teachers,
  });

  @override
  State<_HalaqohSubstituteSheet> createState() =>
      _HalaqohSubstituteSheetState();
}

class _HalaqohSubstituteSheetState extends State<_HalaqohSubstituteSheet> {
  bool _saving = false;
  bool _loadingUsers = false;
  String _selectedTeacherId = '';
  String _selectedDate = '';
  String _status = 'Izin';
  String _reason = '';
  String _search = '';
  final Set<String> _sessions = <String>{};
  List<Map<String, dynamic>> _allUsers = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.date;
    _allUsers = List<Map<String, dynamic>>.from(widget.teachers);
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final token = context.read<AuthController>().token;
      final res = await ApiClient.get(
        '/users',
        token: token,
        query: const {'per_page': '1000'},
      );
      final users = _asMapList(res['data']);
      if (users.isNotEmpty) {
        _allUsers = users;
      }
    } catch (_) {
      // Keep fallback list if the endpoint fails.
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = context.read<AuthController>().token;
      final assignments = _asMapList(widget.group['assignments']);
      final firstAssignment =
          assignments.isEmpty ? <String, dynamic>{} : assignments.first;
      final assignmentId = _asInt(firstAssignment['id']);
      if (assignmentId == 0) return;

      final res = await ApiClient.post(
        '/halaqoh/assignments/$assignmentId/substitute',
        token: token,
        body: {
          'substitute_teacher_id': int.tryParse(_selectedTeacherId),
          'substitute_date': _selectedDate,
          'sessions': _sessions.toList(),
          'substitute_status': _status,
          'substitute_reason': _reason,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _asString(
                res['message'],
                fallback: 'Guru pengganti berhasil disimpan',
              ),
            ),
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final options = _allUsers.where((teacher) {
      if (_asInt(teacher['id']) == _asInt(widget.group['teacher_id'])) {
        return false;
      }
      if (_search.trim().isEmpty) return true;
      final bag = [
        _asString(teacher['name'], fallback: ''),
        _asString(teacher['email'], fallback: ''),
        _asString(teacher['username'], fallback: ''),
      ].join(' ').toLowerCase();
      return bag.contains(_search.trim().toLowerCase());
    }).toList();

    return SafeArea(
      child: Container(
        height: media.size.height * 0.82,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Center(
              child: Icon(Icons.drag_handle_rounded, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Guru Pengganti Halaqoh',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              _asString(widget.group['teacher_name']),
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(
                labelText: 'Cari user / guru',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: _loadingUsers
                  ? const Center(child: CircularProgressIndicator())
                  : options.isEmpty
                      ? const Center(child: Text('User tidak ditemukan'))
                      : ListView.builder(
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final teacher = options[index];
                            final selected =
                                _selectedTeacherId == teacher['id']?.toString();
                            return ListTile(
                              onTap: () => setState(() {
                                _selectedTeacherId =
                                    teacher['id']?.toString() ?? '';
                              }),
                              leading: Icon(
                                selected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                              ),
                              title: Text(_asString(teacher['name'])),
                              subtitle: Text(
                                _asString(
                                  teacher['email'] ?? teacher['username'],
                                  fallback: '-',
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(_selectedDate) ?? DateTime.now(),
                  firstDate: DateTime(2023),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() {
                    _selectedDate = DateFormat('yyyy-MM-dd').format(picked);
                  });
                }
              },
              icon: const Icon(Icons.event_outlined),
              label: Text('Tanggal: ${_formatDisplayDate(_selectedDate)}'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _halaqohSessions.map((session) {
                final selected = _sessions.contains(session);
                return FilterChip(
                  label: Text(session),
                  selected: selected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        _sessions.add(session);
                      } else {
                        _sessions.remove(session);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status guru asli'),
              items: const [
                DropdownMenuItem(value: 'Izin', child: Text('Izin')),
                DropdownMenuItem(value: 'Sakit', child: Text('Sakit')),
                DropdownMenuItem(value: 'Alpha', child: Text('Alpha')),
              ],
              onChanged: (value) => setState(() => _status = value ?? 'Izin'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _reason,
              onChanged: (value) => _reason = value,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Alasan'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ||
                            _selectedTeacherId.isEmpty ||
                            _sessions.isEmpty
                        ? null
                        : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Simpan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
