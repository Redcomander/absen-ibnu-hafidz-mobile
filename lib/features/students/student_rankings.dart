import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/access/access.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import 'attendance_insights.dart';

/// Server-ranked, paginated results. Search and refresh never download every student.
class StudentRankings extends StatefulWidget {
  const StudentRankings({
    super.key,
    required this.module,
    required this.days,
    required this.onStudent,
  });
  final String module;
  final int days;
  final ValueChanged<dynamic> onStudent;
  @override
  State<StudentRankings> createState() => _StudentRankingsState();
}

class _StudentRankingsState extends State<StudentRankings> {
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final status in ['Alpha', 'Izin', 'Sakit'])
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _RankingStatus(
            key: ValueKey('${widget.module}-${widget.days}-$status'),
            module: widget.module,
            days: widget.days,
            status: status,
            onStudent: widget.onStudent,
          ),
        ),
    ],
  );
}

class _RankingStatus extends StatefulWidget {
  const _RankingStatus({
    super.key,
    required this.module,
    required this.days,
    required this.status,
    required this.onStudent,
  });
  final String module, status;
  final int days;
  final ValueChanged<dynamic> onStudent;
  @override
  State<_RankingStatus> createState() => _RankingStatusState();
}

class _RankingStatusState extends State<_RankingStatus> {
  List<Map<String, dynamic>> _rows = [];
  int _page = 1, _generation = 0;
  int? _students, _records;
  String _search = '';
  String? _error;
  bool _loading = true, _more = false, _cached = false;
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final auth = context.read<AuthController>();
    final generation = ++_generation, owner = auth.user?['id'];
    final now = DateTime.now(), page = more ? _page + 1 : 1;
    String date(DateTime value) => value.toIso8601String().substring(0, 10);
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _rows = [];
        _students = null;
        _records = null;
        _more = false;
        _cached = false;
      }
    });
    try {
      final data = await ApiClient.get(
        '/students/attendance-signals',
        token: auth.token,
        query: {
          'module': widget.module,
          'status': widget.status.toLowerCase(),
          'threshold': '1',
          'start_date': date(now.subtract(Duration(days: widget.days - 1))),
          'end_date': date(now),
          'search': _search,
          'page': '$page',
        },
      );
      if (!mounted || generation != _generation || auth.user?['id'] != owner) {
        return;
      }
      if (data['status'] != widget.status.toLowerCase() ||
          data['threshold'] != 1) {
        throw ApiException(
          409,
          'Statistik per status memerlukan backend terbaru.',
        );
      }
      setState(() {
        _rows = more
            ? [..._rows, ...listValue(data['data'])]
            : listValue(data['data']);
        _page = page;
        _more = data['has_more'] == true;
        _students = int.tryParse('${data['total_students']}');
        _records = int.tryParse('${data['total_records']}');
        _cached = data['__from_cache'] == true;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = e is ApiException && [404, 409].contains(e.statusCode)
              ? 'Statistik per status memerlukan backend terbaru.'
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
    final color = attendanceColors[widget.status]!;
    return InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.status} tertinggi',
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Muat ulang ${widget.status}',
                onPressed: _loading ? null : () => _load(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (_students != null)
            Text(
              '$_students santri • $_records catatan ${_search.isEmpty ? 'dalam periode ini' : 'sesuai pencarian'}',
              style: const TextStyle(color: AppTheme.muted),
            ),
          if (_cached)
            const Text(
              'Salinan offline',
              style: TextStyle(color: AppTheme.muted),
            ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              labelText: 'Cari santri ${widget.status.toLowerCase()}',
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: (value) {
              _debounce?.cancel();
              // Invalidate in-flight results immediately, before the debounce expires.
              _generation++;
              _search = value.trim();
              setState(() {
                _rows = [];
                _students = null;
                _records = null;
                _more = false;
                _loading = true;
              });
              _debounce = Timer(
                const Duration(milliseconds: 350),
                () => _load(),
              );
            },
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: () => _load(more: _rows.isNotEmpty),
              child: const Text('Coba lagi'),
            ),
          ],
          if (!_loading && _error == null && _rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Belum ada catatan yang sesuai.'),
            ),
          for (var i = 0; i < _rows.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: .08),
                foregroundColor: color,
                child: Text('${i + 1}'),
              ),
              title: Text(
                '${_rows[i]['name']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: Text(
                '${_rows[i]['count']}×',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onTap: () => widget.onStudent(_rows[i]['student_id']),
            ),
          if (_more)
            TextButton(
              onPressed: _loading ? null : () => _load(more: true),
              child: const Text('Muat berikutnya'),
            ),
        ],
      ),
    );
  }
}
