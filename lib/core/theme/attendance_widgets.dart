import 'package:flutter/material.dart';
import 'app_theme.dart';

class AttendanceHeading extends StatelessWidget {
  const AttendanceHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.fact_check_outlined,
  });
  final String title, subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.brand,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppTheme.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFFDFEAE3), height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Color attendanceColor(String status) => switch (status.toLowerCase()) {
  'hadir' => AppTheme.brand,
  'izin' => const Color(0xFF986300),
  'sakit' => const Color(0xFF2563A6),
  'dinas' => const Color(0xFF6950A1),
  _ => const Color(0xFFB23B35),
};

class AttendanceStatusPicker extends StatelessWidget {
  const AttendanceStatusPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.teacher = false,
    this.enabled = true,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final bool teacher, enabled;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final status
          in teacher
              ? ['Hadir', 'Izin', 'Sakit', 'Alpha', 'Dinas']
              : ['hadir', 'izin', 'sakit', 'alpa'])
        ChoiceChip(
          selected: value == status,
          onSelected: enabled ? (_) => onChanged(status) : null,
          avatar: Icon(
            switch (status.toLowerCase()) {
              'hadir' => Icons.check_circle_outline,
              'izin' => Icons.event_note_outlined,
              'sakit' => Icons.healing_outlined,
              'dinas' => Icons.work_outline_rounded,
              _ => Icons.person_off_outlined,
            },
            size: 17,
            color: attendanceColor(status),
          ),
          label: Text('${status[0].toUpperCase()}${status.substring(1)}'),
          showCheckmark: false,
          selectedColor: attendanceColor(status).withValues(alpha: .12),
          side: BorderSide(
            color: value == status
                ? attendanceColor(status)
                : const Color(0xFFE0E5DF),
          ),
          labelStyle: TextStyle(
            color: value == status ? attendanceColor(status) : AppTheme.muted,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        ),
    ],
  );
}

class AttendanceSummary extends StatelessWidget {
  const AttendanceSummary({super.key, required this.records});
  final List<Map<String, dynamic>> records;
  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final row in records) {
      final status = '${row['status'] ?? ''}'.toLowerCase();
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          Text(
            '${records.length} santri',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          for (final entry in const {
            'hadir': 'Hadir',
            'izin': 'Izin',
            'sakit': 'Sakit',
            'alpa': 'Alpa',
          }.entries)
            Text(
              '${entry.value} ${counts[entry.key] ?? 0}',
              style: TextStyle(
                color: attendanceColor(entry.key),
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
