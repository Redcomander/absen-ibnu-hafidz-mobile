import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_controller.dart';

int _id(dynamic value) => int.tryParse('$value') ?? 0;
List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];

bool canRequestHalaqohMembership(Map<String, dynamic>? user, int teacherId) {
  if (teacherId <= 0 || _id(user?['id']) != teacherId) return false;
  final roles = user?['roles'];
  return roles is! List ||
      !roles.any(
        (role) => ['admin', 'super_admin'].contains(
          (role is Map ? role['name'] : role).toString().toLowerCase(),
        ),
      );
}

/// Assignment ownership grants requests, independently of attendance permissions.
/// Helpers/substitutes must never gain membership editing for someone else's group.
class HalaqohMembershipActions extends StatelessWidget {
  const HalaqohMembershipActions({
    super.key,
    required this.user,
    required this.teacherId,
    required this.onOpen,
  });
  final Map<String, dynamic>? user;
  final int teacherId;
  final ValueChanged<bool> onOpen;

  @override
  Widget build(BuildContext context) {
    if (!canRequestHalaqohMembership(user, teacherId)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kelola anggota halaqoh Anda',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ajukan tambah atau hapus anggota. Perubahan menunggu persetujuan admin dan tidak menghapus data santri.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => onOpen(true),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Tambah Santri'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onOpen(false),
                    icon: const Icon(Icons.person_remove_outlined),
                    label: const Text('Hapus Santri'),
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

class HalaqohMembershipScreen extends StatefulWidget {
  final int teacherId;
  final bool focusStudentSearch;
  const HalaqohMembershipScreen({
    super.key,
    required this.teacherId,
    this.focusStudentSearch = false,
  });

  @override
  State<HalaqohMembershipScreen> createState() =>
      _HalaqohMembershipScreenState();
}

class _HalaqohMembershipScreenState extends State<HalaqohMembershipScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _initialFocusHandled = false;
  final _selected = <int, Map<String, dynamic>>{};
  final _original = <int>{};
  List<Map<String, dynamic>> _requests = [], _options = [];
  bool _loading = true, _saving = false, _searching = false, _ready = false;
  bool _hasMore = false;
  int _page = 1, _searchVersion = 0;
  int? _helperId;
  String? _error, _searchError;
  Timer? _debounce;

  bool get _pending => _requests.any((r) => r['status'] == 'pending');
  bool get _changed => _added.isNotEmpty || _removed.isNotEmpty;
  Set<int> get _added => _selected.keys.toSet().difference(_original);
  Set<int> get _removed => _original.difference(_selected.keys.toSet());
  bool get _authorized =>
      mounted &&
      canRequestHalaqohMembership(
        context.read<AuthController>().user,
        widget.teacherId,
      );
  String get _token => context.read<AuthController>().token ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Map<String, dynamic>>> _history() async {
    final response = await ApiClient.get(
      '/halaqoh/assignment-change-requests',
      token: _token,
      useOfflineCache: false,
    );
    if (response['data'] is! List) {
      throw ApiException(
        502,
        'Riwayat pengajuan tidak lengkap. Coba muat ulang.',
      );
    }
    return _rows(
      response['data'],
    ).where((r) => _id(r['teacher_id']) == widget.teacherId).toList();
  }

  Future<void> _load() async {
    if (!_authorized) {
      setState(() {
        _loading = false;
        _error = 'Hanya guru pengampu yang dapat mengajukan perubahan.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _ready = false;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.get(
          '/halaqoh/assignments',
          token: _token,
          useOfflineCache: false,
        ),
        _history(),
      ]);
      if (!_authorized) return;
      final groups = _rows((results[0] as Map)['groups']);
      final own = groups.where((g) => _id(g['teacher_id']) == widget.teacherId);
      if (own.isEmpty) {
        throw ApiException(
          403,
          'Halaqoh Anda tidak ditemukan. Muat ulang halaman utama.',
        );
      }
      final assignments = _rows(own.first['assignments']);
      if (assignments.isEmpty || own.first['assignments'] is! List) {
        throw ApiException(502, 'Data anggota tidak lengkap. Coba muat ulang.');
      }
      _selected.clear();
      _original.clear();
      for (final row in assignments) {
        final id = _id(row['student_id']);
        if (id <= 0) {
          throw ApiException(
            502,
            'Data anggota tidak lengkap. Coba muat ulang.',
          );
        }
        _original.add(id);
        _selected[id] = {
          'id': id,
          'nama_lengkap': row['student'] is Map
              ? row['student']['nama_lengkap'] ?? '#$id'
              : '#$id',
        };
      }
      _helperId = assignments.isEmpty
          ? null
          : int.tryParse('${assignments.first['helper_teacher_id']}');
      setState(() {
        _requests = results[1] as List<Map<String, dynamic>>;
        _ready = true;
      });
      if (widget.focusStudentSearch && !_initialFocusHandled && !_pending) {
        _initialFocusHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || !_ready || _pending) return;
          final searchContext = _searchFocus.context;
          if (searchContext != null) {
            await Scrollable.ensureVisible(searchContext, alignment: .2);
            if (mounted) _searchFocus.requestFocus();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object e) => e is ApiException
      ? e.message
      : 'Tidak dapat terhubung ke server. Periksa internet lalu coba lagi.';

  Future<void> _findStudents({int page = 1}) async {
    final query = _search.text.trim();
    final version = ++_searchVersion;
    if (query.length < 2) {
      setState(() {
        _options = [];
        _searching = false;
        _hasMore = false;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final res = await ApiClient.get(
        '/halaqoh/student-options',
        token: _token,
        useOfflineCache: false,
        query: {'search': query, 'page': '$page', 'per_page': '20'},
      );
      if (!_authorized || version != _searchVersion) return;
      final rows = _rows(res['data']);
      setState(() {
        _options = rows;
        _page = page;
        _hasMore = rows.length == 20;
      });
    } catch (e) {
      if (mounted && version == _searchVersion) {
        setState(() => _searchError = _message(e));
      }
    } finally {
      if (mounted && version == _searchVersion) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_authorized || !_ready || !_changed || _pending || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kirim pengajuan perubahan?'),
        content: Text(
          'Tambah ${_added.length} santri, keluarkan ${_removed.length} santri. '
          'Perubahan berlaku setelah disetujui admin. Mengeluarkan santri tidak menghapus data santri.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_authorized) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Recheck pending requests before sending. Never queue membership writes offline.
      final history = await _history();
      if (!_authorized) return;
      if (history.any((r) => r['status'] == 'pending')) {
        setState(() => _requests = history);
        throw ApiException(
          409,
          'Masih ada pengajuan menunggu persetujuan admin.',
        );
      }
      final latest = await ApiClient.get(
        '/halaqoh/assignments',
        token: _token,
        useOfflineCache: false,
      );
      if (!_authorized) return;
      final own = _rows(
        latest['groups'],
      ).where((g) => _id(g['teacher_id']) == widget.teacherId);
      final latestRows = own.isEmpty
          ? <Map<String, dynamic>>[]
          : _rows(own.first['assignments']);
      final latestIds = latestRows.map((r) => _id(r['student_id'])).toSet();
      final latestHelper = latestRows.isEmpty
          ? null
          : int.tryParse('${latestRows.first['helper_teacher_id']}');
      if (latestIds.length != _original.length ||
          !latestIds.containsAll(_original) ||
          latestHelper != _helperId) {
        throw ApiException(
          409,
          'Anggota atau pendamping telah berubah di server. Muat ulang sebelum mengajukan.',
        );
      }
      final res = await ApiClient.put(
        '/halaqoh/assignments/${widget.teacherId}',
        token: _token,
        body: {
          'user_id': widget.teacherId,
          'student_ids': _selected.keys.toList(),
          'helper_teacher_id': _helperId,
        },
      );
      if (!_authorized) return;
      if (res['request_id'] == null) {
        throw ApiException(
          502,
          'Respons pengajuan tidak lengkap. Muat ulang status sebelum mencoba lagi.',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengajuan dikirim. Menunggu persetujuan admin.'),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchVersion++;
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final allowed = canRequestHalaqohMembership(user, widget.teacherId);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Perubahan anggota'),
          actions: [
            IconButton(
              tooltip: 'Muat ulang status dan anggota',
              onPressed: _saving || _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !allowed
            ? const Center(
                child: Text('Anda tidak berhak mengubah halaqoh ini.'),
              )
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Pengajuan perubahan halaqoh',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tambahkan atau keluarkan santri dari halaqoh Anda. Anggota tetap seperti semula sampai admin menyetujui. Memerlukan internet.',
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (!_ready)
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Coba muat ulang'),
                    ),
                  if (_requests.isNotEmpty)
                    Card(
                      child: ExpansionTile(
                        title: const Text('Riwayat pengajuan'),
                        subtitle: Text(
                          _pending
                              ? 'Menunggu persetujuan admin'
                              : 'Lihat status dan tanggapan admin',
                        ),
                        children: _requests
                            .map(
                              (r) => ListTile(
                                title: Text(
                                  'Pengajuan #${r['id']} - ${switch (r['status']) {
                                    'approved' => 'Disetujui',
                                    'rejected' => 'Ditolak',
                                    _ => 'Menunggu',
                                  }}',
                                ),
                                subtitle: Text(
                                  [r['created_at'], r['reason']]
                                      .where(
                                        (v) => v != null && '$v'.isNotEmpty,
                                      )
                                      .join('\n'),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (_pending)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Tunggu tanggapan admin sebelum membuat pengajuan berikutnya.',
                      ),
                    ),
                  if (_ready && !_pending) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Anggota dalam pengajuan (${_selected.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ..._selected.entries.toList().map(
                      (entry) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${entry.value['nama_lengkap']}'),
                        subtitle: _added.contains(entry.key)
                            ? const Text('Akan ditambahkan')
                            : null,
                        trailing: IconButton(
                          tooltip: 'Keluarkan dari pengajuan',
                          onPressed: _saving
                              ? null
                              : () =>
                                    setState(() => _selected.remove(entry.key)),
                          icon: const Icon(Icons.person_remove_outlined),
                        ),
                      ),
                    ),
                    if (_removed.isNotEmpty)
                      Text(
                        '${_removed.length} santri akan dikeluarkan setelah disetujui.',
                      ),
                    if (_changed)
                      TextButton(
                        onPressed: _saving ? null : _load,
                        child: const Text('Batalkan perubahan dan muat ulang'),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Cari santri untuk ditambahkan',
                        hintText: 'Minimal 2 karakter',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) {
                        _debounce?.cancel();
                        _searchVersion++;
                        setState(() {
                          _options = [];
                          _page = 1;
                          _searchError = null;
                          _hasMore = false;
                        });
                        _debounce = Timer(
                          const Duration(milliseconds: 400),
                          _findStudents,
                        );
                      },
                    ),
                    if (_searching) const LinearProgressIndicator(),
                    if (_searchError != null) Text(_searchError!),
                    if (!_searching &&
                        _search.text.trim().length >= 2 &&
                        _options.isEmpty &&
                        _searchError == null)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Tidak ada santri ditemukan.'),
                      ),
                    ..._options.map(
                      (s) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${s['nama_lengkap']}'),
                        subtitle: s['current_teacher_name'] == null
                            ? null
                            : Text(
                                'Pengampu saat ini: ${s['current_teacher_name']}',
                              ),
                        value: _selected.containsKey(_id(s['id'])),
                        onChanged: _saving
                            ? null
                            : (checked) => setState(() {
                                final id = _id(s['id']);
                                if (id > 0 && checked == true) {
                                  _selected[id] = s;
                                } else {
                                  _selected.remove(id);
                                }
                              }),
                      ),
                    ),
                    if (_page > 1 || _hasMore)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _page > 1 && !_searching && !_saving
                                ? () => _findStudents(page: _page - 1)
                                : null,
                            child: const Text('Sebelumnya'),
                          ),
                          TextButton(
                            onPressed: _hasMore && !_searching && !_saving
                                ? () => _findStudents(page: _page + 1)
                                : null,
                            child: const Text('Berikutnya'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _changed && !_saving ? _submit : null,
                      icon: const Icon(Icons.send_outlined),
                      label: Text(
                        _saving
                            ? 'Mengirim...'
                            : 'Ajukan perubahan (+${_added.length} / -${_removed.length})',
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
