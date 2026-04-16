import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_controller.dart';
import '../halaqoh/halaqoh_screen.dart';
import '../settings/app_settings_controller.dart';

class JadwalScreen extends StatefulWidget {
  const JadwalScreen({super.key});

  @override
  State<JadwalScreen> createState() => _JadwalScreenState();
}

class _JadwalScreenState extends State<JadwalScreen> {
  String _contentTab = 'jadwal';
  String _type = 'formal';
  String _selectedDate = _todayString();
  String _search = '';
  String _gender = '';
  String _day = '';
  bool _showFilters = true;
  bool _loading = true;
  bool _showingOfflineData = false;
  bool? _wasOnline;
  List<dynamic> _items = [];
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isOnline = context.watch<AppSettingsController>().isOnline;
    if (_wasOnline == false && isOnline && !_loading) {
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = context.read<AuthController>().token;
      final res = await ApiClient.get('/schedules', token: token, query: {
        'type': _type,
        'date': _selectedDate,
        if (_search.trim().isNotEmpty) 'search': _search.trim(),
        if (_gender.isNotEmpty) 'gender': _gender,
        if (_day.isNotEmpty) 'day': _day,
      });
      final data = res['data'];
      _showingOfflineData = res['__from_cache'] == true;
      if (data is List) {
        _items = data;
      } else {
        _items = [];
      }
    } catch (_) {
      _showingOfflineData = _items.isNotEmpty;
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final assignedId = item['assignment']?['teacher']?['id'];
    final substituteId = item['substitute_teacher']?['id'];
    final isAssigned =
        userId != null && (userId == assignedId || userId == substituteId);

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
    final permissions = _permissionNames().map((p) => p.toLowerCase()).toList();

    if (roles.any(
      (r) => ['super_admin', 'admin', 'staff', 'tim_presensi'].contains(r),
    )) {
      return true;
    }

    final userId = user['id'];
    final assignedId = item['assignment']?['teacher']?['id'];
    if (userId != null && userId == assignedId) {
      return true;
    }

    final substituteId = item['substitute_teacher']?['id'];
    final rawDate = item['substitute_date']?.toString();
    final substituteMatchesDate = rawDate == null ||
        rawDate.isEmpty ||
        rawDate.split('T').first == _selectedDate;
    if (userId != null && userId == substituteId && substituteMatchesDate) {
      return true;
    }

    return permissions.any(
      (p) =>
          p.contains('attendance') ||
          p.contains('teacher_attendance') ||
          p.contains('teacher-attendance'),
    );
  }

  bool _canOpenSubstitute(Map<String, dynamic> item) {
    final roles = _roleNames();
    final permissions = _permissionNames().map((p) => p.toLowerCase()).toList();

    if (roles
        .any((r) => ['super_admin', 'admin', 'tim_presensi'].contains(r))) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
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
    _search = nextValue;
    _load();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final nextValue = value.trim();
      if (_search == nextValue) return;
      _search = nextValue;
      _load();
    });
  }

  Map<String, dynamic> _asMap(dynamic value) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
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

  Color _dayAccent(String dayName) {
    switch (dayName) {
      case 'Senin':
        return const Color(0xFF2563EB);
      case 'Selasa':
        return const Color(0xFF059669);
      case 'Rabu':
        return const Color(0xFF7C3AED);
      case 'Kamis':
        return const Color(0xFFD97706);
      case 'Jumat':
        return const Color(0xFF0F766E);
      case 'Sabtu':
        return const Color(0xFFE11D48);
      case 'Ahad':
        return const Color(0xFF475569);
      default:
        return const Color(0xFF166534);
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupedItems() {
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
      grouped.putIfAbsent(dayName, () => []);
      grouped[dayName]!.add(item);
    }

    for (final items in grouped.values) {
      items.sort(
        (a, b) => (a['start_time'] ?? '')
            .toString()
            .compareTo((b['start_time'] ?? '').toString()),
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
    return ordered;
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
          _load();
        },
      ),
    );
  }

  double _groupCardHeight(List<Map<String, dynamic>> items) {
    final estimated = 170.0 + (items.length * 138.0);
    return estimated.clamp(260.0, 560.0);
  }

  Widget _buildDayGroup(
    BuildContext context,
    String dayName,
    List<Map<String, dynamic>> items,
  ) {
    final color = _dayAccent(dayName);
    final isToday = _selectedDate == _todayString() && dayName == _todayName();
    final width = MediaQuery.of(context).size.width - 32;

    return SizedBox(
      width: width < 320 ? 320 : width,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(17)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (isToday)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Hari ini',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    '${items.length} jadwal',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(10),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    _buildScheduleCard(items[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> item) {
    final assignment = _asMap(item['assignment']);
    final lesson =
        _asMap(assignment['lesson'] ?? assignment['diniyyah_lesson']);
    final kelas = _asMap(assignment['kelas']);
    final teacher = _asMap(assignment['teacher']);
    final substituteTeacher = _asMap(item['substitute_teacher']);
    final counts = _asMap(item['attendance_counts']);

    final hasAttendance =
        item['has_attendance'] == true || item['has_attendance_today'] == true;
    final hasTeacherAttendance = item['has_teacher_attendance'] == true ||
        item['has_teacher_attendance_today'] == true;
    final hasSubstitute = _isSubstituteActive(item);

    final canOpenStudent = _canOpenStudentAttendance(item);
    final canOpenTeacher = _canOpenTeacherAttendance(item);
    final canOpenSubstitute = _canOpenSubstitute(item);
    final showTeacherButton = canOpenTeacher;
    final showSubstituteButton = canOpenSubstitute;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.auto_stories_rounded,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _statusBadge(
                            '${item['start_time'] ?? '--:--'} - ${item['end_time'] ?? '--:--'}',
                            const Color(0xFF1D4ED8),
                            icon: Icons.schedule_rounded,
                          ),
                          if (hasAttendance)
                            _statusBadge(
                              'Santri ✓',
                              const Color(0xFF15803D),
                              icon: Icons.task_alt_rounded,
                            ),
                          if (hasTeacherAttendance)
                            _statusBadge(
                              'Guru ✓',
                              const Color(0xFF2563EB),
                              icon: Icons.badge_rounded,
                            ),
                          if (hasSubstitute)
                            _statusBadge(
                              'Pengganti',
                              const Color(0xFFD97706),
                              icon: Icons.swap_horiz_rounded,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        lesson['name']?.toString() ?? 'Pelajaran',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${kelas['nama'] ?? '-'} ${kelas['tingkat'] ?? ''}'
                            .trim(),
                        style: const TextStyle(color: Colors.black87),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Guru: ${teacher['name'] ?? '-'}',
                        style: TextStyle(
                          color: hasSubstitute ? Colors.grey : Colors.black54,
                          decoration:
                              hasSubstitute ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (hasSubstitute)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Pengganti: ${substituteTeacher['name'] ?? '-'}',
                            style: const TextStyle(
                              color: Color(0xFFB45309),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (hasSubstitute && canOpenSubstitute)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _openSubstitute(item),
                                icon: const Icon(Icons.swap_horiz_rounded),
                                label: const Text('Ganti lagi'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _cancelSubstitute(item),
                                icon: const Icon(
                                  Icons.person_remove_alt_1_rounded,
                                  color: Color(0xFFB91C1C),
                                ),
                                label: const Text('Batalkan'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    _actionButton(
                      icon: hasAttendance
                          ? Icons.edit_note_rounded
                          : Icons.fact_check_rounded,
                      color: hasAttendance
                          ? const Color(0xFFD97706)
                          : const Color(0xFF15803D),
                      enabled: canOpenStudent,
                      onTap: () => _openStudentAttendance(item),
                    ),
                    if (showTeacherButton) ...[
                      const SizedBox(height: 8),
                      _actionButton(
                        icon: hasTeacherAttendance
                            ? Icons.assignment_turned_in_rounded
                            : Icons.badge_rounded,
                        color: hasTeacherAttendance
                            ? const Color(0xFF7C3AED)
                            : const Color(0xFF2563EB),
                        enabled: canOpenTeacher,
                        onTap: () => _openTeacherAttendance(item),
                      ),
                    ],
                    if (showSubstituteButton) ...[
                      const SizedBox(height: 8),
                      _actionButton(
                        icon: Icons.swap_horiz_rounded,
                        color: const Color(0xFFD97706),
                        enabled: canOpenSubstitute,
                        onTap: () => _openSubstitute(item),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _countChip(
                    'Hadir', counts['hadir'] ?? 0, const Color(0xFF16A34A)),
                _countChip(
                    'Izin', counts['izin'] ?? 0, const Color(0xFFD97706)),
                _countChip(
                    'Sakit', counts['sakit'] ?? 0, const Color(0xFFEA580C)),
                _countChip(
                    'Alpa', counts['alpa'] ?? 0, const Color(0xFFDC2626)),
              ],
            ),
            if (!canOpenStudent) ...[
              const SizedBox(height: 10),
              const Text(
                'Absensi siswa hanya bisa dibuka sesuai role dan jam pelajaran seperti di web.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showRamadhan =
        context.watch<AppSettingsController>().isRamadhanTabEnabled;
    final groupedItems = _groupedItems();

    if (!showRamadhan && _type == 'ramadhan') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _type != 'ramadhan') return;
        setState(() => _type = 'formal');
        _load();
      });
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'jadwal', label: Text('Jadwal')),
              ButtonSegment(value: 'halaqoh', label: Text('Halaqoh')),
            ],
            selected: {_contentTab},
            onSelectionChanged: (v) {
              setState(() => _contentTab = v.first);
            },
          ),
          const SizedBox(height: 12),
          if (_contentTab == 'halaqoh')
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.78,
              child: const HalaqohScreen(
                initialTab: 'groups',
                showHeader: false,
                allowedTabs: {'groups'},
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Jadwal & Absensi',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDisplayDate(_selectedDate)} · ${_items.length} jadwal $_type',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: _segments(showRamadhan),
                      selected: {_type},
                      onSelectionChanged: (v) {
                        _type = v.first;
                        _load();
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() => _showFilters = !_showFilters);
                        },
                        icon: Icon(
                          _showFilters
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        label: Text(
                          _showFilters
                              ? 'Sembunyikan pencarian & filter'
                              : 'Tampilkan pencarian & filter',
                        ),
                      ),
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 180),
                      crossFadeState: _showFilters
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Column(
                        children: [
                          TextField(
                            controller: _searchCtrl,
                            textInputAction: TextInputAction.search,
                            onChanged: _onSearchChanged,
                            onSubmitted: (_) => _applySearch(),
                            decoration: InputDecoration(
                              hintText: 'Cari pelajaran, kelas, guru...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: IconButton(
                                onPressed: _applySearch,
                                icon: const Icon(Icons.arrow_forward_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: 170,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _gender,
                                  decoration: const InputDecoration(
                                      labelText: 'Gender'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: '', child: Text('Semua')),
                                    DropdownMenuItem(
                                        value: 'banin', child: Text('Banin')),
                                    DropdownMenuItem(
                                        value: 'banat', child: Text('Banat')),
                                  ],
                                  onChanged: (v) {
                                    _gender = v ?? '';
                                    _load();
                                  },
                                ),
                              ),
                              if (_canFilterDate())
                                SizedBox(
                                  width: 190,
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            DateTime.tryParse(_selectedDate) ??
                                                DateTime.now(),
                                        firstDate: DateTime(2024),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        _selectedDate = picked
                                            .toIso8601String()
                                            .split('T')
                                            .first;
                                        _load();
                                      }
                                    },
                                    icon: const Icon(Icons.event_rounded),
                                    label:
                                        Text(_formatDisplayDate(_selectedDate)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Pilih hari',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 44,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _dayFilterChip('Semua', ''),
                                _dayFilterChip('Senin', 'Senin'),
                                _dayFilterChip('Selasa', 'Selasa'),
                                _dayFilterChip('Rabu', 'Rabu'),
                                _dayFilterChip('Kamis', 'Kamis'),
                                _dayFilterChip('Jumat', 'Jumat'),
                                _dayFilterChip('Sabtu', 'Sabtu'),
                                _dayFilterChip('Ahad', 'Ahad'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      secondChild: const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_showingOfflineData)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        'Offline • menampilkan jadwal tersimpan',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (groupedItems.isEmpty)
              const _Empty('Belum ada jadwal')
            else
              ...groupedItems.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    height: _groupCardHeight(entry.value),
                    child: _buildDayGroup(context, entry.key, entry.value),
                  ),
                );
              }),
          ],
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
        style:
            TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              enabled ? color.withValues(alpha: 0.10) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.35)
                : const Color(0xFFD1D5DB),
          ),
        ),
        child: Icon(icon, color: enabled ? color : Colors.grey),
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
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _students = [];
  late String _date;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
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
    setState(() => _loading = true);
    try {
      final token = context.read<AuthController>().token;
      final res = await ApiClient.get('/attendance', token: token, query: {
        'jadwal_id': widget.schedule['id'].toString(),
        'date': _date,
        'type': widget.type,
      });

      final students = (res['students'] as List?) ?? [];
      _students = students.map((s) {
        final row = Map<String, dynamic>.from(s as Map);
        row['status'] = row['status'] ?? 'hadir';
        row['catatan'] = row['catatan'] ?? '';
        return row;
      }).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAttendance() async {
    setState(() => _saving = true);
    try {
      final token = context.read<AuthController>().token;
      final res = await ApiClient.post('/attendance', token: token, body: {
        'jadwal_id': widget.schedule['id'],
        'date': _date,
        'type': widget.type,
        'records': _students
            .map((s) => {
                  'student_id': s['student_id'],
                  'status': s['status'],
                  'catatan': s['catatan'],
                })
            .toList(),
      });

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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final assignment =
        Map<String, dynamic>.from((widget.schedule['assignment'] ?? {}) as Map);
    final lesson = Map<String, dynamic>.from(
        ((assignment['lesson'] ?? assignment['diniyyah_lesson']) ?? {}) as Map);
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
                  borderRadius: BorderRadius.circular(999)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Absensi Siswa',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(lesson['name']?.toString() ?? 'Pelajaran',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${kelas['nama'] ?? '-'} ${kelas['tingkat'] ?? ''}'
                      .trim()),
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
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
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
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _students.isEmpty
                      ? const Center(child: Text('Belum ada data siswa'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _students.length,
                          itemBuilder: (context, index) {
                            final student = _students[index];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      student['student_name']?.toString() ??
                                          'Santri',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 2),
                                    Text('NIS: ${student['nis'] ?? '-'}',
                                        style: const TextStyle(
                                            color: Colors.grey)),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        'hadir',
                                        'izin',
                                        'sakit',
                                        'alpa'
                                      ].map((status) {
                                        final selected =
                                            student['status'] == status;
                                        return ChoiceChip(
                                          label: Text(status),
                                          selected: selected,
                                          onSelected: (_) => setState(
                                              () => student['status'] = status),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      initialValue:
                                          student['catatan']?.toString() ?? '',
                                      decoration: const InputDecoration(
                                          labelText: 'Catatan'),
                                      onChanged: (v) => student['catatan'] = v,
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
                                  strokeWidth: 2, color: Colors.white))
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
      final res =
          await ApiClient.post('/attendance/teacher', token: token, body: {
        'jadwal_id': widget.schedule['id'],
        'date': _date,
        'type': widget.type,
        'status': _status,
        'notes': _notesCtrl.text.trim(),
      });

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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
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
        height: media.size.height * 0.55,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                  child: Icon(Icons.drag_handle_rounded, color: Colors.grey)),
              const SizedBox(height: 8),
              const Text(
                'Absensi Guru',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickDate,
                icon: const Icon(Icons.event_rounded),
                label: Text('Tanggal: $_date'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const ['Hadir', 'Izin', 'Sakit', 'Alpha']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _status = v ?? 'Hadir'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Catatan'),
              ),
              const Spacer(),
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
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
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
      final res = await ApiClient.get('/attendance/assignable-teachers',
          token: token,
          query: {
            'search': _searchCtrl.text.trim(),
            'page': '1',
            'per_page': '50',
          });
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
      final res =
          await ApiClient.post('/attendance/substitute', token: token, body: {
        'jadwal_id': widget.schedule['id'],
        'substitute_teacher_id': _selectedTeacherId,
        'date': _date,
        'status': _status,
        'reason': _reasonCtrl.text.trim(),
        'type': widget.type,
      });

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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
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
                    decoration:
                        const InputDecoration(labelText: 'Status Guru Asli'),
                    items: const ['Izin', 'Sakit', 'Dinas Luar', 'Lainnya']
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
                    decoration:
                        const InputDecoration(labelText: 'Alasan / catatan'),
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
                        final teacher =
                            Map<String, dynamic>.from(_teachers[index] as Map);
                        final selected = _selectedTeacherId == teacher['id'];
                        final teacherId = teacher['id'] as int?;
                        return Card(
                          child: ListTile(
                            onTap: teacherId == null
                                ? null
                                : () => setState(
                                    () => _selectedTeacherId = teacherId),
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
                                  strokeWidth: 2, color: Colors.white),
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
            child: Text(text, style: const TextStyle(color: Colors.grey))),
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
