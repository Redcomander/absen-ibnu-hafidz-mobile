import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../settings/app_settings_controller.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen(
      {super.key,
      required this.onOpenSchedule,
      required this.onOpenSettings,
      this.onOpenStats});

  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenStats;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final sync = context.watch<AppSettingsController>();
    final name = auth.user?['name']?.toString() ?? 'Ustadz / Ustadzah';
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      children: [
        Text(DateFormat('dd.MM.yyyy').format(DateTime.now()),
            style: const TextStyle(color: AppTheme.muted, letterSpacing: 2)),
        const SizedBox(height: 16),
        const Text('Assalamualaikum,', style: TextStyle(fontSize: 19)),
        Text(name,
            style: const TextStyle(
                fontSize: 30, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 10),
        const Text(
            'Mulai hari dengan niat baik.\nDampingi setiap langkah belajar santri.',
            style: TextStyle(color: AppTheme.muted, height: 1.6)),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: AppTheme.brand, borderRadius: BorderRadius.circular(28)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.auto_stories_rounded,
                color: AppTheme.accent, size: 32),
            const SizedBox(height: 24),
            const Text('RUANG MENGAJAR',
                style: TextStyle(
                    color: AppTheme.accent,
                    letterSpacing: 2,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Hadir untuk\nsetiap proses.',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.2,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text('Jadwal, absensi, dan Halaqoh\ndalam satu tempat.',
                style: TextStyle(color: Color(0xFFD1DFD7), height: 1.6)),
            const SizedBox(height: 24),
            FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.brand,
                    minimumSize: const Size(0, 48)),
                onPressed: onOpenSchedule,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Buka jadwal & absensi')),
          ]),
        ),
        const SizedBox(height: 20),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                            sync.isOnline
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            color: AppTheme.brand),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                sync.isLoading
                                    ? 'Memeriksa koneksi…'
                                    : sync.connectionLabel,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                          sync.pendingSyncCount > 0
                              ? '${sync.pendingSyncCount} perubahan menunggu sinkronisasi.'
                              : 'Tidak ada perubahan dalam antrean lokal.',
                          style: const TextStyle(color: AppTheme.muted)),
                      const SizedBox(height: 6),
                      TextButton.icon(
                          onPressed:
                              sync.isLoading || sync.isSyncing || !sync.isOnline
                                  ? null
                                  : () => sync.syncPendingActions(),
                          icon: const Icon(Icons.sync_rounded),
                          label: Text(sync.isSyncing
                              ? 'Menyinkronkan…'
                              : 'Sinkronkan sekarang')),
                    ]))),
        const SizedBox(height: 28),
        const Text('Akses cepat',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (onOpenStats != null)
          _shortcut(Icons.insights_rounded, 'Rekapan kehadiran',
              'Tinjau data sesuai hak akses Anda', onOpenStats!),
        _shortcut(Icons.tune_rounded, 'Pengaturan sinkronisasi',
            'Atur Wi-Fi dan penggunaan data', onOpenSettings),
      ],
    );
  }

  Widget _shortcut(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
            child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                leading: Icon(icon, color: AppTheme.brand),
                title: Text(title),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onTap)));
  }
}
