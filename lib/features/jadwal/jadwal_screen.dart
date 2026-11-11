import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/section_header.dart';
import '../../core/network/offline_cache_store.dart';
import 'schedule_repository.dart';
import 'schedule_target.dart';
import '../../core/theme/attendance_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'attendance_repository.dart';
import '../auth/auth_controller.dart';
import '../halaqoh/halaqoh_screen.dart';
import '../settings/app_settings_controller.dart';

typedef _ScheduleListRow = ({
  String? day,
  int count,
  Map<String, dynamic>? item,
});

class JadwalScreen extends StatefulWidget {
  const JadwalScreen({super.key, this.target});
  final ScheduleTarget? target;

  @override
  State<JadwalScreen> createState() => _JadwalScreenState();
}

class _JadwalScreenState extends State<JadwalScreen> {
  ScheduleTarget? _focusedTarget;
  final _scrollController = ScrollController();
  String _contentTab = 'jadwal';
  String _type = 'formal';
  String _selectedDate = _todayString();
  String _search = '';
  String _gender = '';
  String _day = '';
  bool _showFilters = false;
  bool _loading = true;
  String? _loadError;
  bool _showingOfflineData = false;
  bool? _wasOnline;
  List<dynamic> _items = [];
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  final _repository = ScheduleRepository();
  List<dynamic>? _groupedSource;
  (String, String, String)? _groupedFilters;
  Map<String, List<Map<String, dynamic>>> _groupedCache = {};
  Map<String, List<Map<String, dynamic>>>? _renderGroups;
  List<_ScheduleListRow> _renderRows = [];
  int _loadGeneration = 0;
  String? _savedAt;
  bool _statusDateUnknown = false;
  bool _hasScheduleSnapshot = false;

  @override
  void initState() {
    super.initState();
    _applyTarget();
    _load();
  }

  void _applyTarget() {
    final target = widget.target;
    if (target == null) return;
    _focusedTarget = target;
    _contentTab = 'jadwal';
    _type = target.type;
    _selectedDate = _todayString();
    _search = '';
    _searchCtrl.clear();
    _gender = '';
    _day = '';
    _showFilters = false;
  }

  @override
  void didUpdateWidget(covariant JadwalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != null && !identical(oldWidget.target, widget.target)) {
      _searchDebounce?.cancel();
      _applyTarget();
      _load();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
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
        if (mounted) _load();
      });
    }
    _wasOnline = isOnline;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = context.read<AppSettingsController>();
    final auth = context.read<AuthController>();
    final generation = ++_loadGeneration;
    final type = _type;
    final date = _selectedDate;
    final account = OfflineCacheStore.scope;
    bool current() =>
        mounted &&
        generation == _loadGeneration &&
        OfflineCacheStore.scope == account;
    setState(() {
      _loading = true;
      _loadError = null;
      _items = [];
      _showingOfflineData = false;
      _savedAt = null;
      _statusDateUnknown = false;
      _hasScheduleSnapshot = false;
    });
    try {
      final saved = await _repository.cached(type, date);
      if (!current()) return;
      if (saved != null) {
        setState(() {
          _hasScheduleSnapshot = true;
          _items = saved['data'] as List? ?? [];
          _showingOfflineData = true;
          _savedAt = saved['__cache_saved_at']?.toString();
          _statusDateUnknown =
              saved['__schedule_date'] != null &&
              saved['__schedule_date'] != date;
        });
      }
      if (!await settings.canSyncNow()) return;
      if (!current()) return;
      final token = auth.token;
      final res = await _repository.refresh(type, date, token);
      if (!current()) return;
      final data = res['data'];
      _showingOfflineData = res['__from_cache'] == true;
      _statusDateUnknown = false;
      if (data is List) {
        _hasScheduleSnapshot = true;
        _items = data;
      } else {
        _items = [];
      }
    } catch (error) {
      if (!current()) return;
      _loadError = error is ApiException
          ? error.message
          : 'Jadwal gagal dimuat. Periksa koneksi lalu coba lagi.';
      _showingOfflineData = _hasScheduleSnapshot;
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  List<String> _roleNames() {
    final user = context.read<AuthController>().user;
    return ((user?['roles'] as List?) ?? [])
        .map((r) => (r['name'] ?? '').toString().toLowerCase())
        .toList();
  }

  List<String> _permissionNames() {
    final user = context.read<AuthController>().user;
    final roles = (user?['roles'] as List?) ?? [];
    final permissions = <String>[];

    for (final role in roles) {
      final items = (role['permissions'] as List?) ?? [];
      for (final permission in items) {
        final name = (permission['name'] ?? '').toString();
        if (name.isNotEmpty) permissions.add(name);
      }
    }

    return permissions;
  }

  bool _isManager() {
    final roles = _roleNames();
    return roles.any(
      (r) => ['super_admin', 'admin', 'staff', 'tim_presensi'].contains(r),
    );
  }

  bool _canOpenStudentAttendance(Map<String, dynamic> item) {
    final user = context.read<AuthController>().user;
    if (user == null) return false;

    if (_isManager()) return true;

    final userId = user['id'];
    final assignment = _asMap(item['assignment']);
    final teacher = _asMap(assignment['teacher']);
    final substituteTeacher = _asMap(item['substitute_teacher']);

    final assignedId = _asInt(teacher['id']);
    final substituteId = _asInt(substituteTeacher['id']);
    final currentUserId = _asInt(userId);

    final isAssignedTeacher =
        currentUserId != 0 && assignedId != 0 && currentUserId == assignedId;
    final isActiveSubstitute =
        currentUserId != 0 &&
        substituteId != 0 &&
        currentUserId == substituteId &&
        _isSubstituteActive(item);
    final isAssigned = isAssignedTeacher || isActiveSubstitute;

    if (!isAssigned) return false;
    if (_selectedDate != _todayString()) return false;

    final todayName = _todayName();
    final scheduleDay = (item['day'] ?? item['hari'] ?? '').toString();
    if (scheduleDay != todayName) return false;

    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = _toMinutes(item['start_time']?.toString());
    final endMinutes = _toMinutes(item['end_time']?.toString());

    if (startMinutes == null || endMinutes == null) return false;
    return currentMinutes >= startMinutes - 15 &&
        currentMinutes <= endMinutes + 15;
  }

  bool _canOpenTeacherAttendance(Map<String, dynamic> item) {
    final user = context.read<AuthController>().user;
    if (user == null) return false;

    final roles = _roleNames();
    if (roles.any(
      (r) => ['super_admin', 'admin', 'staff', 'tim_presensi'].contains(r),
    )) {
      return true;
    }

    final userId = user['id'];
    final assignedId = item['assignment']?['teacher']?['id'];
    final isAssigned = userId != null && userId == assignedId;

    final substituteId = item['substitute_teacher']?['id'];
    final isSubstitute =
        userId != null && userId == substituteId && _isSubstituteActive(item);

    return isAssigned || isSubstitute;
  }

  bool _canOpenSubstitute(Map<String, dynamic> item) {
    final roles = _roleNames();
    final permissions = _permissionNames().map((p) => p.toLowerCase()).toList();

    if (roles.any(
      (r) => ['super_admin', 'admin', 'tim_presensi'].contains(r),
    )) {
      return true;
    }

    return permissions.any(
      (p) => p.contains('schedule.substitute') || p.contains('substitute'),
    );
  }

  Future<void> _openStudentAttendance(Map<String, dynamic> item) async {
    if (!_canOpenStudentAttendance(item)) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StudentAttendanceSheet(
        schedule: item,
        type: _type,
        initialDate: _selectedDate,
      ),
    );

    if (saved == true) {
      await _load();
    }
  }

  Future<void> _openTeacherAttendance(Map<String, dynamic> item) async {
    if (!_canOpenTeacherAttendance(item)) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TeacherAttendanceSheet(
        schedule: item,
        type: _type,
        initialDate: _selectedDate,
      ),
    );

    if (saved == true) {
      await _load();
    }
  }

  Future<void> _openSubstitute(Map<String, dynamic> item) async {
    if (!_canOpenSubstitute(item)) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubstituteSheet(
        schedule: item,
        type: _type,
        initialDate: _selectedDate,
      ),
    );

    if (saved == true) {
      await _load();
    }
  }

  Future<void> _cancelSubstitute(Map<String, dynamic> item) async {
    if (!_canOpenSubstitute(item) || !_isSubstituteActive(item)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan guru pengganti?'),
        content: const Text(
          'Penugasan guru pengganti pada jadwal ini akan dihapus.',
        ),
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
      final rawDate = item['substitute_date']?.toString();
      final effectiveDate = rawDate != null && rawDate.isNotEmpty
          ? rawDate.split('T').first
          : _selectedDate;

      await ApiClient.post(
        '/attendance/substitute',
        token: token,
        queueOnOffline: false,
        body: {
          'jadwal_id': item['id'],
          'substitute_teacher_id': null,
          'date': effectiveDate,
          'status': 'Izin',
          'reason': 'Pembatalan guru pengganti',
          'type': _type,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guru pengganti berhasil dibatalkan')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  List<ButtonSegment<String>> _segments(bool showRamadhan) {
    return [
      const ButtonSegment(value: 'formal', label: Text('Formal')),
      if (showRamadhan)
        const ButtonSegment(value: 'ramadhan', label: Text('Ramadhan')),
      const ButtonSegment(value: 'diniyyah', label: Text('Diniyyah')),
    ];
  }

  bool _canFilterDate() => _isManager();

  void _applySearch() {
    FocusScope.of(context).unfocus();
    final nextValue = _searchCtrl.text.trim();
    if (_search == nextValue) return;
    setState(() => _search = nextValue);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final nextValue = value.trim();
      if (_search == nextValue) return;
      setState(() => _search = nextValue);
    });
  }

  Map<String, dynamic> _asMap(dynamic value) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isSubstituteActive(Map<String, dynamic> item) {
    if (item['substitute_teacher'] == null) return false;
    final rawDate = item['substitute_date']?.toString();
    if (rawDate == null || rawDate.isEmpty) return true;
    return rawDate.split('T').first == _selectedDate;
  }

  String _formatDisplayDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  Map<String, List<Map<String, dynamic>>> _groupedItems() {
    final filters = (_day, _gender, _search);
    if (identical(_groupedSource, _items) && _groupedFilters == filters) {
      return _groupedCache;
    }
    final search = _search.toLowerCase();
    const orderedDays = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Ahad',
    ];

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final raw in _items) {
      final item = _asMap(raw);
      final dayName = (item['day'] ?? item['hari'] ?? 'Lainnya').toString();
      if (_day.isNotEmpty && dayName != _day) continue;
      final assignment = _asMap(item['assignment']);
      final kelas = _asMap(assignment['kelas']);
      if (_gender.isNotEmpty &&
          kelas['gender']?.toString().toLowerCase() != _gender) {
        continue;
      }
      final bag = [
        _asMap(assignment['lesson'])['name'],
        _asMap(assignment['diniyyah_lesson'])['name'],
        kelas['nama'],
        kelas['tingkat'],
        _asMap(assignment['teacher'])['name'],
        _asMap(item['substitute_teacher'])['name'],
      ].join(' ').toLowerCase();
      if (search.isNotEmpty && !bag.contains(search)) continue;
      grouped.putIfAbsent(dayName, () => []);
      grouped[dayName]!.add(item);
    }

    for (final items in grouped.values) {
      items.sort(
        (a, b) => (a['start_time'] ?? '').toString().compareTo(
          (b['start_time'] ?? '').toString(),
        ),
      );
    }

    final ordered = <String, List<Map<String, dynamic>>>{};
    for (final dayName in orderedDays) {
      final items = grouped.remove(dayName);
      if (items != null && items.isNotEmpty) {
        ordered[dayName] = items;
      }
    }
    grouped.forEach((key, value) {
      if (value.isNotEmpty) ordered[key] = value;
    });
    _groupedSource = _items;
    _groupedFilters = filters;
    return _groupedCache = ordered;
  }

  Widget _dayFilterChip(String label, String value) {
    final selected = _day == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        showCheckmark: false,
        label: Text(label),
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF374151),
          fontWeight: FontWeight.w700,
        ),
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF166534),
        side: BorderSide(
          color: selected ? const Color(0xFF166534) : const Color(0xFFD1D5DB),
        ),
        onSelected: (_) {
          setState(() => _day = value);
        },
      ),
    );
  }

  Widget _buildDayHeader(String dayName, int count) {
    final today = dayName == _todayName();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: today ? const Color(0xFFD8B56A) : const Color(0xFF143E35),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              dayName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '$count pelajaran',
            style: const TextStyle(color: Color(0xFF60756A)),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> item) {
    final assignment = _asMap(item['assignment']);
    final lesson = _asMap(
      assignment['lesson'] ?? assignment['diniyyah_lesson'],
    );
    final kelas = _asMap(assignment['kelas']);
    final teacher = _asMap(assignment['teacher']);
    final substitute = _asMap(item['substitute_teacher']);
    final counts = _asMap(item['attendance_counts']);
    final hasAttendance =
        item['has_attendance'] == true || item['has_attendance_today'] == true;
    final hasTeacher =
        item['has_teacher_attendance'] == true ||
        item['has_teacher_attendance_today'] == true;
    final hasSubstitute = _isSubstituteActive(item);
    final canStudent = _canOpenStudentAttendance(item);
    final canTeacher = _canOpenTeacherAttendance(item);
    final canSubstitute = _canOpenSubstitute(item);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusBadge(
                  '${item['start_time'] ?? '--:--'} – ${item['end_time'] ?? '--:--'}',
                  const Color(0xFF143E35),
                  icon: Icons.schedule_rounded,
                ),
                if (hasAttendance)
                  _statusBadge('Santri tercatat', const Color(0xFF236047)),
                if (hasTeacher)
                  _statusBadge('Guru tercatat', const Color(0xFF236047)),
                if (hasSubstitute)
                  _statusBadge('Guru pengganti', const Color(0xFF855D20)),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              lesson['name']?.toString() ?? 'Pelajaran',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF143E35),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${kelas['nama'] ?? '-'} ${kelas['tingkat'] ?? ''}'.trim(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Guru: ${teacher['name'] ?? '-'}',
              style: const TextStyle(color: Color(0xFF60756A)),
            ),
            if (hasSubstitute)
              Text(
                'Pengganti: ${substitute['name'] ?? '-'}',
                style: const TextStyle(color: Color(0xFF855D20)),
              ),
            const SizedBox(height: 16),
            if (_statusDateUnknown)
              const Text(
                'Status absensi tanggal ini perlu diperbarui saat online.',
                style: TextStyle(color: Color(0xFF60756A)),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 8,
                children: [
                  _countChip(
                    'Hadir',
                    counts['hadir'] ?? 0,
                    const Color(0xFF236047),
                  ),
                  _countChip(
                    'Izin',
                    counts['izin'] ?? 0,
                    const Color(0xFF855D20),
                  ),
                  _countChip(
                    'Sakit',
                    counts['sakit'] ?? 0,
                    const Color(0xFF9A581C),
                  ),
                  _countChip(
                    'Alpa',
                    counts['alpa'] ?? 0,
                    const Color(0xFFA53732),
                  ),
                ],
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: canStudent
                      ? () => _openStudentAttendance(item)
                      : null,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Absensi santri'),
                ),
                if (canTeacher)
                  OutlinedButton.icon(
                    onPressed: () => _openTeacherAttendance(item),
                    icon: const Icon(Icons.badge_outlined, size: 18),
                    label: const Text('Absensi guru'),
                  ),
                if (canSubstitute)
                  TextButton.icon(
                    onPressed: () => _openSubstitute(item),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Guru pengganti'),
                  ),
                if (hasSubstitute && canSubstitute)
                  TextButton(
                    onPressed: () => _cancelSubstitute(item),
                    child: const Text('Batalkan pengganti'),
                  ),
              ],
            ),
            if (!canStudent)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Absensi santri dibuka sesuai penugasan dan jam pelajaran.',
                  style: TextStyle(color: Color(0xFF60756A), fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _observeConnectivity();
    final showRamadhan = context.select<AppSettingsController, bool>(
      (s) => s.isRamadhanTabEnabled,
    );
    final focused = _focusedTarget?.type == _type
        ? _items
              .whereType<Map>()
              .where((item) => '${item['id']}' == '${_focusedTarget!.id}')
              .firstOrNull
        : null;
    final groups = _groupedItems();
    if (!identical(_renderGroups, groups)) {
      _renderGroups = groups;
      _renderRows = [
        for (final group in groups.entries) ...[
          (day: group.key, count: group.value.length, item: null),
          for (final item in group.value) (day: null, count: 0, item: item),
        ],
      ];
    }
    if (!showRamadhan && _type == 'ramadhan') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _type != 'ramadhan') return;
        setState(() => _type = 'formal');
        _load();
      });
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_contentTab == 'jadwal' && focused != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.my_location_rounded,
                          color: AppTheme.brand,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Jadwal yang dipilih - Hari ini',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.brand,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tutup sorotan jadwal',
                          onPressed: () =>
                              setState(() => _focusedTarget = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    _buildScheduleCard(Map<String, dynamic>.from(focused)),
                  ],
                ),
              ),
            ),
          if (_focusedTarget?.type == _type && focused == null && !_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Jadwal yang dipilih belum tersedia. Muat ulang atau periksa daftar jadwal di bawah.',
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    eyebrow: 'RUANG BELAJAR',
                    title: 'Jadwal Belajar',
                    subtitle:
                        '${_formatDisplayDate(_selectedDate)}\nPelajaran, halaqoh, dan absensi dalam satu tempat.',
                    icon: Icons.menu_book_rounded,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tab in ['jadwal', 'halaqoh'])
                        ChoiceChip(
                          label: Text(
                            tab == 'jadwal' ? 'Pelajaran' : 'Halaqoh',
                          ),
                          selected: _contentTab == tab,
                          onSelected: (_) => setState(() => _contentTab = tab),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_contentTab == 'halaqoh')
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * .78,
                      child: const HalaqohScreen(
                        initialTab: 'groups',
                        showHeader: false,
                        allowedTabs: {'groups'},
                      ),
                    )
                  else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final segment in _segments(showRamadhan))
                          ChoiceChip(
                            label: segment.label!,
                            selected: _type == segment.value,
                            onSelected: (_) {
                              setState(() => _type = segment.value);
                              _load();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _applySearch(),
                      decoration: InputDecoration(
                        hintText: 'Cari pelajaran, kelas, atau guru',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'Pencarian dan filter',
                          onPressed: () =>
                              setState(() => _showFilters = !_showFilters),
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ),
                    ),
                    if (_showFilters)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: 160,
                              child: DropdownButtonFormField<String>(
                                initialValue: _gender,
                                decoration: const InputDecoration(
                                  labelText: 'Kelas',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: '',
                                    child: Text('Semua kelas'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'banin',
                                    child: Text('Banin'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'banat',
                                    child: Text('Banat'),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _gender = v ?? ''),
                              ),
                            ),
                            if (_canFilterDate())
                              OutlinedButton.icon(
                                icon: const Icon(Icons.event_rounded),
                                label: Text(_formatDisplayDate(_selectedDate)),
                                onPressed: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.parse(_selectedDate),
                                    firstDate: DateTime(2024),
                                    lastDate: DateTime(2100),
                                  );
                                  if (date != null && mounted) {
                                    setState(
                                      () => _selectedDate = DateFormat(
                                        'yyyy-MM-dd',
                                      ).format(date),
                                    );
                                    _load();
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _dayFilterChip('Semua hari', ''),
                          for (final day in [
                            'Senin',
                            'Selasa',
                            'Rabu',
                            'Kamis',
                            'Jumat',
                            'Sabtu',
                            'Ahad',
                          ])
                            _dayFilterChip(day, day),
                        ],
                      ),
                    ),
                    if (_showingOfflineData)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6EEE7),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.offline_pin_rounded,
                              color: Color(0xFF143E35),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Jadwal tersimpan di perangkat${_savedAt == null ? '' : '\nDiperbarui ${DateFormat('dd MMM, HH:mm').format(DateTime.parse(_savedAt!).toLocal())}'}',
                                style: const TextStyle(
                                  color: Color(0xFF143E35),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_loadError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _items.isEmpty
                                  ? _loadError!
                                  : 'Belum dapat memperbarui. Jadwal tersimpan tetap dapat dibuka.',
                            ),
                            TextButton.icon(
                              onPressed: _loading ? null : _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Coba lagi'),
                            ),
                          ],
                        ),
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (!_loading && groups.isEmpty)
                      _Empty(
                        !_hasScheduleSnapshot
                            ? 'Belum ada jadwal tersimpan. Hubungkan internet untuk mengunduh jadwal pertama kali.'
                            : 'Tidak ada jadwal yang cocok dengan filter.',
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (_contentTab == 'jadwal')
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverList.builder(
                itemCount: _renderRows.length,
                itemBuilder: (context, index) {
                  final row = _renderRows[index];
                  if (row.day != null) {
                    return _buildDayHeader(row.day!, row.count);
                  }
                  if (focused != null &&
                      '${row.item!['id']}' == '${focused['id']}') {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildScheduleCard(row.item!),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _countChip(String label, dynamic value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label ${value ?? 0}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StudentAttendanceSheet extends StatefulWidget {
  final Map<String, dynamic> schedule;
  final String type;
  final String initialDate;

  const _StudentAttendanceSheet({
    required this.schedule,
    required this.type,
    required this.initialDate,
  });

  @override
  State<_StudentAttendanceSheet> createState() =>
      _StudentAttendanceSheetState();
}

class _StudentAttendanceSheetState extends State<_StudentAttendanceSheet> {
  final _materi = TextEditingController();
  final _rangkuman = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _students = [];
  late String _date;
  final _attendanceRepository = AttendanceRepository();
  int _loadGeneration = 0, _editVersion = 0, _formRevision = 0;
  bool _savedForm = false, _pendingForm = false, _refreshingForm = false;
  String? _formError;
  void _markEdited() => _editVersion++;

  @override
  void dispose() {
    _materi.dispose();
    _rangkuman.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _materi.addListener(_markEdited);
    _rangkuman.addListener(_markEdited);
    _loadAttendance();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked.toIso8601String().split('T').first);
      await _loadAttendance();
    }
  }

  Future<void> _loadAttendance() async {
    final generation = ++_loadGeneration;
    final date = _date;
    final account = OfflineCacheStore.scope;
    final settings = context.read<AppSettingsController>();
    final auth = context.read<AuthController>();
    final id = widget.schedule['id'].toString();
    bool current() =>
        mounted &&
        generation == _loadGeneration &&
        OfflineCacheStore.scope == account;
    void apply(Map<String, dynamic> res) {
      _formRevision++;
      _materi.text = res['materi']?.toString() ?? '';
      _rangkuman.text = res['rangkuman']?.toString() ?? '';
      _students = (res['students'] as List)
          .whereType<Map>()
          .map(
            (s) => {
              ...Map<String, dynamic>.from(s),
              'status': s['status'] ?? '',
              'catatan': s['catatan'] ?? '',
            },
          )
          .toList();
      _savedForm = res['__from_cache'] == true;
      _pendingForm = res['__has_pending_changes'] == true;
    }

    setState(() {
      _loading = true;
      _refreshingForm = true;
      _formError = null;
      _savedForm = false;
      _pendingForm = false;
      _students = [];
      _materi.clear();
      _rangkuman.clear();
    });
    try {
      final cached = await _attendanceRepository.cached(widget.type, id, date);
      if (!current()) return;
      if (cached != null) {
        setState(() {
          apply(cached);
          _loading = false;
        });
      }
      if (!await settings.canSyncNow() || !current()) return;
      final version = _editVersion;
      final fresh = await _attendanceRepository.refresh(
        widget.type,
        id,
        date,
        auth.token,
      );
      // A background refresh must never replace a user's in-progress form edits.
      if (current() && version == _editVersion) setState(() => apply(fresh));
    } catch (error) {
      if (current()) {
        _formError = _students.isEmpty
            ? 'Daftar santri belum tersedia. Unduh formulir saat online.'
            : 'Belum dapat memperbarui. Formulir tersimpan tetap dapat digunakan.';
      }
    } finally {
      if (current()) {
        setState(() {
          _loading = false;
          _refreshingForm = false;
        });
      }
    }
  }

  Future<void> _saveAttendance() async {
    if (_students.any(
      (s) => !['hadir', 'izin', 'sakit', 'alpa'].contains(s['status']),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pilih status absensi untuk setiap santri sebelum menyimpan.',
          ),
        ),
      );
      return;
    }
    if (_students.isEmpty ||
        (widget.type != 'diniyyah' && _materi.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data santri dan materi jurnal mengajar wajib diisi.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final token = context.read<AuthController>().token;
      final res = await ApiClient.post(
        '/attendance',
        token: token,
        body: {
          'jadwal_id': widget.schedule['id'],
          'date': _date,
          'type': widget.type,
          'materi': _materi.text.trim(),
          'rangkuman': _rangkuman.text.trim(),
          'records': _students
              .map(
                (s) => {
                  'student_id': s['student_id'],
                  'status': s['status'],
                  'catatan': s['catatan'],
                },
              )
              .toList(),
        },
      );

      if (mounted) {
        final queued = res['queued'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              queued
                  ? 'Absensi siswa disimpan offline dan akan sinkron otomatis'
                  : 'Absensi siswa berhasil disimpan',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final assignment = Map<String, dynamic>.from(
      (widget.schedule['assignment'] ?? {}) as Map,
    );
    final lesson = Map<String, dynamic>.from(
      ((assignment['lesson'] ?? assignment['diniyyah_lesson']) ?? {}) as Map,
    );
    final kelas = Map<String, dynamic>.from((assignment['kelas'] ?? {}) as Map);

    return SafeArea(
      child: Container(
        height: media.size.height * 0.88,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AttendanceHeading(
                    title: 'Absensi Santri',
                    subtitle:
                        '${lesson['name'] ?? 'Pelajaran'}\n${kelas['nama'] ?? '-'}, ${kelas['tingkat'] ?? '-'}',
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tanggal: $_date',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _pickDate,
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: const Text('Ganti tanggal'),
                      ),
                    ],
                  ),
                  AttendanceSummary(records: _students),
                  OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _editVersion++;
                              for (final s in _students) {
                                s['status'] = 'hadir';
                              }
                            });
                          },
                    icon: const Icon(Icons.done_all_rounded),
                    label: const Text('Set semua hadir'),
                  ),
                ],
              ),
            ),
            if (_savedForm || _pendingForm)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  _pendingForm
                      ? 'Perubahan tersimpan di perangkat dan menunggu konfirmasi server.'
                      : 'Formulir tersimpan dan dapat diisi saat offline.',
                  style: const TextStyle(color: Color(0xFF143E35)),
                ),
              ),
            if (_formError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_formError!),
                    TextButton(
                      onPressed: _refreshingForm ? null : _loadAttendance,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            if (_refreshingForm && !_loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _students.isEmpty
                  ? const Center(child: Text('Belum ada data siswa'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount:
                          _students.length +
                          (widget.type != 'diniyyah' ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (widget.type != 'diniyyah' && index == 0) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _materi,
                                    maxLines: 2,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Materi jurnal mengajar (wajib)',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _rangkuman,
                                    maxLines: 2,
                                    decoration: const InputDecoration(
                                      labelText: 'Rangkuman (opsional)',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        final student =
                            _students[index -
                                (widget.type != 'diniyyah' ? 1 : 0)];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  student['student_name']?.toString() ??
                                      'Santri',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'NIS: ${student['nis'] ?? '-'}',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 10),
                                AttendanceStatusPicker(
                                  value: '${student['status'] ?? ''}',
                                  enabled: !_saving,
                                  onChanged: (status) => setState(() {
                                    _editVersion++;
                                    student['status'] = status;
                                  }),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  key: ValueKey(
                                    '$_formRevision:${student['student_id']}',
                                  ),
                                  initialValue:
                                      student['catatan']?.toString() ?? '',
                                  decoration: const InputDecoration(
                                    labelText: 'Catatan',
                                  ),
                                  onChanged: (v) {
                                    _editVersion++;
                                    student['catatan'] = v;
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
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
                      onPressed: _saving ? null : _saveAttendance,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherAttendanceSheet extends StatefulWidget {
  final Map<String, dynamic> schedule;
  final String type;
  final String initialDate;

  const _TeacherAttendanceSheet({
    required this.schedule,
    required this.type,
    required this.initialDate,
  });

  @override
  State<_TeacherAttendanceSheet> createState() =>
      _TeacherAttendanceSheetState();
}

class _TeacherAttendanceSheetState extends State<_TeacherAttendanceSheet> {
  final _notesCtrl = TextEditingController();
  String _status = 'Hadir';
  bool _saving = false;
  late String _date;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked.toIso8601String().split('T').first);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = context.read<AuthController>().token;
      final res = await ApiClient.post(
        '/attendance/teacher',
        token: token,
        body: {
          'jadwal_id': widget.schedule['id'],
          'date': _date,
          'type': widget.type,
          'status': _status,
          'notes': _notesCtrl.text.trim(),
        },
      );

      if (mounted) {
        final queued = res['queued'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              queued
                  ? 'Absensi guru disimpan offline dan akan sinkron otomatis'
                  : 'Absensi guru berhasil disimpan',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return SafeArea(
      child: Container(
        height: media.size.height * 0.78,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Icon(Icons.drag_handle_rounded, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                AttendanceHeading(
                  title: 'Absensi Guru',
                  subtitle:
                      '${(widget.schedule['assignment'] as Map?)?['teacher']?['name'] ?? 'Guru pengampu'}\n${(widget.schedule['assignment'] as Map?)?['lesson']?['name'] ?? (widget.schedule['assignment'] as Map?)?['diniyyah_lesson']?['name'] ?? 'Pelajaran'}',
                  icon: Icons.badge_outlined,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.event_rounded),
                  label: Text('Tanggal: $_date'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Status kehadiran',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                AttendanceStatusPicker(
                  value: _status,
                  teacher: true,
                  enabled: !_saving,
                  onChanged: (status) => setState(() => _status = status),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    hintText: 'Tambahkan keterangan bila diperlukan',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Batal'),
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
        ),
      ),
    );
  }
}

class _SubstituteSheet extends StatefulWidget {
  final Map<String, dynamic> schedule;
  final String type;
  final String initialDate;

  const _SubstituteSheet({
    required this.schedule,
    required this.type,
    required this.initialDate,
  });

  @override
  State<_SubstituteSheet> createState() => _SubstituteSheetState();
}

class _SubstituteSheetState extends State<_SubstituteSheet> {
  final _searchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String _status = 'Izin';
  late String _date;
  int? _selectedTeacherId;
  List<dynamic> _teachers = [];

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    final oldStatus = widget.schedule['substitute_status']?.toString();
    _status = oldStatus == 'Dinas Luar'
        ? 'Dinas'
        : ['Izin', 'Sakit', 'Dinas', 'Lainnya'].contains(oldStatus)
        ? oldStatus!
        : 'Izin';
    _selectedTeacherId = widget.schedule['substitute_teacher']?['id'] as int?;
    final rawDate = widget.schedule['substitute_date']?.toString();
    if (rawDate != null && rawDate.isNotEmpty) {
      _date = rawDate.split('T').first;
    }
    _loadTeachers();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked.toIso8601String().split('T').first);
    }
  }

  Future<void> _loadTeachers() async {
    setState(() => _loading = true);
    try {
      final token = context.read<AuthController>().token;
      final res = await ApiClient.get(
        '/attendance/assignable-teachers',
        token: token,
        query: {
          'search': _searchCtrl.text.trim(),
          'page': '1',
          'per_page': '50',
        },
      );
      _teachers = (res['data'] as List?) ?? [];
    } catch (_) {
      _teachers = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = context.read<AuthController>().token;
      final res = await ApiClient.post(
        '/attendance/substitute',
        token: token,
        body: {
          'jadwal_id': widget.schedule['id'],
          'substitute_teacher_id': _selectedTeacherId,
          'date': _date,
          'status': _status,
          'reason': _reasonCtrl.text.trim(),
          'type': widget.type,
        },
      );

      if (mounted) {
        final queued = res['queued'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              queued
                  ? 'Guru pengganti disimpan offline dan akan sinkron otomatis'
                  : 'Guru pengganti berhasil disimpan',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeSubstitute() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan guru pengganti?'),
        content: const Text('Pengganti pada jadwal ini akan dihapus.'),
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

    setState(() => _saving = true);
    try {
      final token = context.read<AuthController>().token;
      await ApiClient.post(
        '/attendance/substitute',
        token: token,
        queueOnOffline: false,
        body: {
          'jadwal_id': widget.schedule['id'],
          'substitute_teacher_id': null,
          'date': _date,
          'status': _status,
          'reason': 'Pembatalan guru pengganti',
          'type': widget.type,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guru pengganti berhasil dibatalkan')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return SafeArea(
      child: Container(
        height: media.size.height * 0.78,
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
                  'Guru Pengganti',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      labelText: 'Cari guru / staff',
                      suffixIcon: IconButton(
                        onPressed: _loadTeachers,
                        icon: const Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status Guru Asli',
                    ),
                    items: const ['Izin', 'Sakit', 'Dinas', 'Lainnya']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => _status = v ?? 'Izin'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickDate,
                    icon: const Icon(Icons.event_rounded),
                    label: Text('Tanggal pengganti: $_date'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Alasan / catatan',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _selectedTeacherId = null),
                      icon: const Icon(Icons.clear_rounded),
                      label: const Text('Kosongkan pilihan'),
                    ),
                  ),
                  if (widget.schedule['substitute_teacher'] != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _removeSubstitute,
                        icon: const Icon(
                          Icons.person_remove_alt_1_rounded,
                          color: Color(0xFFB91C1C),
                        ),
                        label: const Text('Batalkan pengganti sekarang'),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _teachers.length,
                      itemBuilder: (context, index) {
                        final teacher = Map<String, dynamic>.from(
                          _teachers[index] as Map,
                        );
                        final selected = _selectedTeacherId == teacher['id'];
                        final teacherId = teacher['id'] as int?;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            onTap: teacherId == null
                                ? null
                                : () => setState(
                                    () => _selectedTeacherId = teacherId,
                                  ),
                            leading: Icon(
                              selected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                            ),
                            title: Text(
                              teacher['name']?.toString() ?? '-',
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(teacher['email']?.toString() ?? '-'),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
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
                      onPressed: _saving ? null : _save,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(text, style: const TextStyle(color: Colors.grey)),
        ),
      ),
    );
  }
}

String _todayString() => DateTime.now().toIso8601String().split('T').first;

String _todayName() {
  const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Ahad'];
  final weekday = DateTime.now().weekday;
  return days[(weekday - 1).clamp(0, 6)];
}

int? _toMinutes(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return hour * 60 + minute;
}
