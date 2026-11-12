import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/access/access.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import 'attendance_insights.dart';
import 'student_rankings.dart';
import 'student_progress_screen.dart';
export 'student_progress_screen.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});
  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  int _page = 1, _generation = 0, _days = 30, _total = 0;
  bool _loading = false, _more = false, _rankings = false;
  String _module = 'Formal';
  String? _error;
  Timer? _debounce;
  List<String> get _modules => ['Formal', 'Diniyyah', 'Halaqoh']
      .where(
        (m) => hasAccess(
          context.read<AuthController>().user,
          {
            'Formal': 'absensi.view',
            'Diniyyah': 'absensi_diniyyah.view',
            'Halaqoh': 'halaqoh.view',
          }[m]!,
        ),
      )
      .toList();
  @override
  void initState() {
    super.initState();
    if (_modules.isNotEmpty) _module = _modules.first;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final auth = context.read<AuthController>();
    if (!hasAccess(auth.user, 'students.view')) return;
    final generation = ++_generation, owner = auth.user?['id'];
    final page = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _rows = [];
        _more = false;
      }
    });
    try {
      final data = await ApiClient.get(
        '/students',
        token: auth.token,
        useOfflineCache: false,
        query: {
          'search': _search.text.trim(),
          'page': '$page',
          'per_page': '20',
        },
      );
      if (!mounted || generation != _generation || auth.user?['id'] != owner) {
        return;
      }
      setState(() {
        final rows = listValue(data['data']);
        _rows = more ? [..._rows, ...rows] : rows;
        _page = page;
        _total = int.tryParse('${data['total']}') ?? 0;
        _more = page * 20 < _total;
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

  void _open(dynamic id) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => StudentProgressScreen(studentId: id)),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Santri & perkembangan')),
    body: CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          sliver: SliverList.list(
            children: [
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
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_graph_rounded,
                      color: AppTheme.accent,
                      size: 32,
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Setiap santri,\nsetiap perkembangan.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Kenali pola kehadiran untuk pendampingan yang lebih tepat.',
                      style: TextStyle(color: Colors.white70, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Direktori santri'),
                    selected: !_rankings,
                    onSelected: (_) => setState(() => _rankings = false),
                  ),
                  if (_modules.isNotEmpty)
                    ChoiceChip(
                      label: const Text('Statistik & tindak lanjut'),
                      selected: _rankings,
                      onSelected: (_) => setState(() => _rankings = true),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (_rankings) ...[
                const Text(
                  'Frekuensi tertinggi',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Jumlah catatan, bukan jumlah hari. Alpha tidak termasuk sesi yang belum diabsen.',
                  style: TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in _modules)
                      ChoiceChip(
                        label: Text(m),
                        selected: _module == m,
                        onSelected: (_) => setState(() => _module = m),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final days in [30, 90, 365])
                      ChoiceChip(
                        label: Text('$days hari'),
                        selected: _days == days,
                        onSelected: (_) => setState(() => _days = days),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                StudentRankings(module: _module, days: _days, onStudent: _open),
              ] else ...[
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Cari nama santri',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (_) => _load(),
                  onChanged: (_) {
                    _debounce?.cancel();
                    _generation++;
                    setState(() {
                      _rows = [];
                      _loading = true;
                      _more = false;
                    });
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => _load(),
                    );
                  },
                ),
                const SizedBox(height: 14),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  InsightCard(
                    child: Column(
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: () => _load(),
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                if (!_loading && _error == null)
                  Text(
                    '$_total santri sesuai pencarian',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                if (!_loading && _error == null && _rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Tidak ada data yang sesuai.'),
                  ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        if (!_rankings)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final s = _rows[i],
                    name =
                        '${_rows[i]['nama_lengkap'] ?? _rows[i]['name'] ?? '-'}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.brand.withValues(alpha: .08),
                        foregroundColor: AppTheme.brand,
                        child: Text(
                          name.isEmpty
                              ? '?'
                              : name.characters.first.toUpperCase(),
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${mapValue(s['kelas'])['nama'] ?? '-'}, ${mapValue(s['kelas'])['tingkat'] ?? '-'}',
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 19,
                      ),
                      onTap: () => _open(s['id']),
                    ),
                  ),
                );
              },
            ),
          ),
        if (!_rankings && _more)
          SliverToBoxAdapter(
            child: TextButton(
              onPressed: _loading ? null : () => _load(more: true),
              child: const Text('Muat berikutnya'),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 36)),
      ],
    ),
  );
}
