import 'package:flutter/material.dart';
import '../../core/access/access.dart';
import '../../core/theme/app_theme.dart';

/// Match the server's roster semantics: create adds, update replaces, delete removes.
({
  Set<String> added,
  Set<String> removed,
  Set<String> before,
  Set<String> after,
})
halaqohRosterChange(Map<String, dynamic> request) {
  Set<String> ids(String key, String details) {
    final raw = request[key];
    return raw is List
        ? raw.map((id) => '$id').toSet()
        : listValue(request[details]).map((s) => '${s['id']}').toSet();
  }

  final before = ids('previous_student_ids', 'previous_student_details');
  final proposed = ids('student_ids', 'student_details');
  final after = switch (request['request_type']) {
    'create' => before.union(proposed),
    'delete_single' => before.difference(proposed),
    'delete_all' => <String>{},
    _ => proposed,
  };
  return (
    added: after.difference(before),
    removed: before.difference(after),
    before: before,
    after: after,
  );
}

class HalaqohRequestCard extends StatelessWidget {
  const HalaqohRequestCard({
    super.key,
    required this.request,
    required this.busy,
    required this.onReview,
  });
  final Map<String, dynamic> request;
  final bool busy;
  final ValueChanged<bool> onReview;

  @override
  Widget build(BuildContext context) {
    final change = halaqohRosterChange(request);
    final status = '${request['status']}';
    final color = status == 'approved'
        ? AppTheme.brand
        : status == 'rejected'
        ? const Color(0xFFAF3838)
        : const Color(0xFF946000);
    final label = switch (status) {
      'approved' => 'Disetujui',
      'rejected' => 'Ditolak',
      'pending' => 'Menunggu tinjauan',
      _ => status,
    };
    final type = switch (request['request_type']) {
      'create' => 'Tambah anggota',
      'update' => 'Ubah susunan anggota',
      'delete_single' => 'Keluarkan santri',
      'delete_all' => 'Kosongkan anggota',
      _ => 'Perubahan anggota',
    };
    final names = {
      for (final s in [
        ...listValue(request['previous_student_details']),
        ...listValue(request['student_details']),
      ])
        '${s['id']}':
            '${s['nama_lengkap'] ?? s['name'] ?? 'Santri #${s['id']}'}',
    };
    final owners = mapValue(request['student_owner_snapshot']);
    final target = '${request['target_teacher_id'] ?? request['teacher_id']}';
    final transfers = change.added
        .where(
          (id) =>
              owners[id] != null &&
              '${owners[id]}' != '0' &&
              '${owners[id]}' != target,
        )
        .toSet();
    Widget members(
      String heading,
      Set<String> ids,
      Color color,
      IconData icon,
    ) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$heading (${ids.length})',
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in ids)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    names[id] ?? 'Santri #$id',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  'PENGAJUAN #${request['id']}',
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${mapValue(request['teacher'])['name'] ?? 'Guru #${request['teacher_id']}'}',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(type, style: const TextStyle(color: AppTheme.muted)),
            if (request['requested_by_name'] != null ||
                mapValue(request['requested_by'])['name'] != null)
              Text(
                'Diajukan oleh ${request['requested_by_name'] ?? mapValue(request['requested_by'])['name']}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${change.before.length} anggota sebelumnya → ${change.after.length} anggota setelah disetujui',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
            ),
            if (change.added.isNotEmpty)
              members(
                'Ditambahkan',
                change.added,
                AppTheme.brand,
                Icons.person_add_alt_1_outlined,
              ),
            if (change.removed.isNotEmpty)
              members(
                'Dikeluarkan dari halaqoh',
                change.removed,
                const Color(0xFFAF3838),
                Icons.person_remove_outlined,
              ),
            if (transfers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${transfers.length} santri berasal dari halaqoh guru lain. Persetujuan akan memindahkan keanggotaan mereka.',
                  style: const TextStyle(color: Color(0xFF946000), height: 1.5),
                ),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Lihat rincian anggota',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: members(
                    'Anggota sebelumnya',
                    change.before,
                    AppTheme.muted,
                    Icons.groups_outlined,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: members(
                    'Anggota setelah disetujui',
                    change.after,
                    AppTheme.brand,
                    Icons.groups_rounded,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
            if ('${request['reason'] ?? ''}'.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${status == 'rejected' ? 'Alasan penolakan' : 'Catatan'}: ${request['reason']}',
                  style: const TextStyle(height: 1.5),
                ),
              ),
            if (status == 'pending')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => onReview(false),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Tolak'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => onReview(true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Setujui'),
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
