import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

String attendanceStatus(dynamic value) {
  final status = '$value'.trim().toLowerCase();
  return ['alpa', 'alpha', 'tidak_hadir'].contains(status)
      ? 'Alpha'
      : {'hadir': 'Hadir', 'izin': 'Izin', 'sakit': 'Sakit'}[status] ??
            '$value';
}

const attendanceColors = {
  'Hadir': AppTheme.brand,
  'Sakit': Color(0xFFBD7319),
  'Izin': Color(0xFF416DA0),
  'Alpha': Color(0xFFBC4E57),
};

class StudentOccurrence {
  const StudentOccurrence(this.id, this.name, this.count, this.detail);
  final dynamic id;
  final String name, detail;
  final int count;
}

/// Group by identity, never by name: different students may have the same name.
List<StudentOccurrence> groupStudentOccurrences(List<dynamic> records) {
  final grouped = <String, StudentOccurrence>{};
  for (final row in records) {
    final map = row is Map ? row : <String, dynamic>{'name': '$row'};
    final id = map['student_id'];
    final name = '${map['name'] ?? map['nama_lengkap'] ?? '-'}';
    final detail = [
      map['kelas'],
      map['tingkat'],
    ].where((v) => v != null && '$v'.isNotEmpty).join(', ');
    final key = id != null ? 'id:$id' : 'legacy:$name:$detail';
    final count = int.tryParse('${map['count'] ?? 1}') ?? 1;
    final previous = grouped[key];
    grouped[key] = StudentOccurrence(
      id,
      name,
      (previous?.count ?? 0) + count,
      detail,
    );
  }
  return grouped.values.toList()..sort((a, b) {
    final count = b.count.compareTo(a.count);
    return count == 0 ? a.name.compareTo(b.name) : count;
  });
}

class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

/// A bounded, searchable list; typing never triggers a rebuild of the report.
class StudentStatusCard extends StatefulWidget {
  const StudentStatusCard({
    super.key,
    required this.status,
    required this.records,
    this.onStudent,
  });
  final String status;
  final List<dynamic> records;
  final ValueChanged<dynamic>? onStudent;
  @override
  State<StudentStatusCard> createState() => _StudentStatusCardState();
}

class _StudentStatusCardState extends State<StudentStatusCard> {
  String _search = '';
  int _limit = 8;
  late List<StudentOccurrence> _rows;
  @override
  void initState() {
    super.initState();
    _rows = groupStudentOccurrences(widget.records);
  }

  @override
  void didUpdateWidget(covariant StudentStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) {
      _rows = groupStudentOccurrences(widget.records);
      _limit = 8;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = attendanceColors[widget.status] ?? AppTheme.brand;
    final matches = _rows
        .where((s) => '${s.name} ${s.detail}'.toLowerCase().contains(_search))
        .toList();
    final total = _rows.fold<int>(0, (sum, s) => sum + s.count);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InsightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .1),
                  foregroundColor: color,
                  child: Icon(
                    widget.status == 'Sakit'
                        ? Icons.healing_rounded
                        : widget.status == 'Izin'
                        ? Icons.event_note_rounded
                        : Icons.person_off_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Santri ${widget.status}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '$total kali',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_rows.length} santri • $total catatan pada periode terpilih',
              style: const TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              key: ValueKey('search-${widget.status}'),
              decoration: InputDecoration(
                labelText: 'Cari santri ${widget.status.toLowerCase()}',
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() {
                _search = v.trim().toLowerCase();
                _limit = 8;
              }),
            ),
            const SizedBox(height: 12),
            if (matches.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Tidak ada santri yang sesuai.'),
              ),
            for (final s in matches.take(_limit))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  s.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: s.detail.isEmpty ? null : Text(s.detail),
                trailing: Text(
                  '${s.count}×',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                onTap: s.id == null || widget.onStudent == null
                    ? null
                    : () => widget.onStudent!(s.id),
              ),
            if (matches.length > _limit)
              TextButton(
                onPressed: () => setState(() => _limit += 20),
                child: Text(
                  'Tampilkan lebih banyak (${matches.length - _limit})',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Interactive charts use Flutter's canvas; no chart runtime or looping ticker.
class AttendanceChart extends StatefulWidget {
  const AttendanceChart({super.key, required this.counts});
  final Map<String, int> counts;
  @override
  State<AttendanceChart> createState() => _AttendanceChartState();
}

class _AttendanceChartState extends State<AttendanceChart> {
  String? _selected;
  @override
  Widget build(BuildContext context) {
    final total = widget.counts.values.fold<int>(0, (a, b) => a + b);
    final selected = widget.counts.containsKey(_selected) ? _selected : null;
    final value = selected == null
        ? widget.counts['Hadir'] ?? 0
        : widget.counts[selected]!;
    return InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Komposisi kehadiran',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          Center(
            child: Semantics(
              label: '${selected ?? 'Hadir'}: $value dari $total catatan',
              child: SizedBox(
                width: 170,
                height: 170,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        size: const Size(170, 170),
                        painter: _RingPainter(widget.counts, selected),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              total == 0
                                  ? '—'
                                  : '${(value * 100 / total).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 29,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(selected ?? 'Hadir'),
                            Text(
                              '$value / $total catatan',
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in widget.counts.entries)
                ChoiceChip(
                  avatar: CircleAvatar(
                    backgroundColor:
                        attendanceColors[entry.key] ?? AppTheme.muted,
                    radius: 5,
                  ),
                  label: Text('${entry.key} ${entry.value}'),
                  selected: selected == entry.key,
                  onSelected: (v) =>
                      setState(() => _selected = v ? entry.key : null),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Sentuh status untuk melihat proporsinya. Sesi yang belum diabsen tidak dihitung.',
            style: TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.counts, this.selected);
  final Map<String, int> counts;
  final String? selected;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    canvas.drawArc(
      rect.deflate(10),
      0,
      math.pi * 2,
      false,
      paint..color = const Color(0xFFEBEEE9),
    );
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return;
    double angle = -math.pi / 2;
    for (final entry in counts.entries) {
      final sweep = entry.value / total * math.pi * 2;
      paint.color = (attendanceColors[entry.key] ?? AppTheme.muted).withValues(
        alpha: selected == null || selected == entry.key ? 1 : .22,
      );
      if (sweep > 0) {
        canvas.drawArc(
          rect.deflate(10),
          angle,
          math.max(0, sweep - .035),
          false,
          paint,
        );
      }
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.counts != counts || old.selected != selected;
}

class AttendanceTrend extends StatefulWidget {
  const AttendanceTrend({super.key, required this.months});
  final Map<String, Map<String, int>> months;
  @override
  State<AttendanceTrend> createState() => _AttendanceTrendState();
}

class _AttendanceTrendState extends State<AttendanceTrend> {
  String? _selected;
  @override
  Widget build(BuildContext context) {
    final months = widget.months.keys.toList()..sort();
    final selected = months.contains(_selected)
        ? _selected
        : (months.isEmpty ? null : months.last);
    return InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tren kehadiran bulanan',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (selected == null)
            const Text('Belum ada catatan pada periode ini.')
          else ...[
            Text(
              '$selected • ${widget.months[selected]!['Hadir'] ?? 0} hadir / ${widget.months[selected]!['total']} catatan',
              key: const ValueKey('trend-detail'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 145,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: months.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final month = months[index], counts = widget.months[month]!;
                  final total = counts['total'] ?? 0,
                      hadir = counts['Hadir'] ?? 0;
                  final percent = total == 0 ? 0.0 : hadir / total;
                  return Semantics(
                    button: true,
                    selected: selected == month,
                    label: '$month, ${(percent * 100).round()} persen hadir',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _selected = month),
                      child: SizedBox(
                        width: 62,
                        child: Column(
                          children: [
                            Text(
                              '${(percent * 100).round()}%',
                              style: const TextStyle(fontSize: 11),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: math.max(.03, percent),
                                  widthFactor: .65,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: selected == month
                                          ? AppTheme.brand
                                          : AppTheme.accent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              month.substring(5),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sentuh batang untuk memeriksa bulan. Tinggi batang menunjukkan persentase hadir.',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ],
        ],
      ),
    );
  }
}
