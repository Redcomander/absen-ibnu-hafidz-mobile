import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/access/access.dart';
import '../auth/auth_controller.dart';
import '../halaqoh/review_screen.dart';
import '../jadwal/schedule_target.dart';
import '../settings/app_settings_controller.dart';
import '../students/students_screen.dart';
import 'user_dashboard.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenSchedule,
    required this.onOpenSettings,
    this.onOpenStats,
    this.onOpenScheduleCard,
  });
  final VoidCallback onOpenSchedule, onOpenSettings;
  final VoidCallback? onOpenStats;
  final ValueChanged<ScheduleTarget>? onOpenScheduleCard;
  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthController, Map<String, dynamic>?>(
      (a) => a.user,
    );
    final name = user?['name']?.toString() ?? 'Ustadz / Ustadzah';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        _WelcomeHeader(name: name, onSchedule: onOpenSchedule),
        const SizedBox(height: 20),
        RepaintBoundary(
          child: UserDashboard(
            onOpenSchedule: onOpenSchedule,
            onOpenScheduleCard: onOpenScheduleCard,
          ),
        ),
        const SizedBox(height: 18),
        const _SyncSummary(),
        const SizedBox(height: 26),
        const Text(
          'Ruang pendampingan',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Semua kebutuhan hari ini, lebih dekat.',
          style: TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 16),
        if (hasAccess(user, 'students.view'))
          _shortcut(
            Icons.school_outlined,
            'Profil & perkembangan santri',
            'Grafik kehadiran dan statistik tindak lanjut',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StudentsScreen()),
            ),
          ),
        if (canReviewHalaqoh(user))
          _shortcut(
            Icons.fact_check_outlined,
            'Persetujuan Halaqoh',
            'Tinjau perubahan anggota dan tanggapan',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HalaqohReviewScreen()),
            ),
          ),
        if (onOpenStats != null)
          _shortcut(
            Icons.insights_rounded,
            'Rekapan kehadiran',
            'Cari santri per status dan telusuri catatannya',
            onOpenStats!,
          ),
        _shortcut(
          Icons.tune_rounded,
          'Pengaturan sinkronisasi',
          'Atur Wi-Fi dan penggunaan data',
          onOpenSettings,
        ),
      ],
    );
  }

  Widget _shortcut(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.brand.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppTheme.brand),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            subtitle,
            style: const TextStyle(color: AppTheme.muted, height: 1.4),
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
        onTap: onTap,
      ),
    ),
  );
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.name, required this.onSchedule});
  final String name;
  final VoidCallback onSchedule;
  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [AppTheme.brand, Color(0xFF286653)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(
                  'assets/branding/favicon.png',
                  width: 28,
                  height: 28,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'IBNU HAFIDZ',
                  style: TextStyle(
                    color: AppTheme.accent,
                    letterSpacing: 2,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.wb_sunny_outlined,
                color: AppTheme.accent,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 26),
          const Text(
            'Assalamualaikum,',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Dampingi langkah kecil hari ini,\ntumbuhkan masa depan santri.',
            style: TextStyle(color: Colors.white70, height: 1.6),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                DateFormat('dd MMM yyyy').format(DateTime.now()),
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onSchedule,
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('Buka jadwal'),
              ),
            ],
          ),
        ],
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 360,
      ),
      child: content,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

/// Queue changes rebuild this small card, not the dashboard or schedule list.
class _SyncSummary extends StatelessWidget {
  const _SyncSummary();
  @override
  Widget build(BuildContext context) => Consumer<AppSettingsController>(
    builder: (context, sync, _) => Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  sync.isOnline
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: AppTheme.brand,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sync.isLoading
                        ? 'Memeriksa koneksi…'
                        : sync.connectionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              sync.pendingSyncCount > 0
                  ? '${sync.pendingSyncCount} perubahan menunggu sinkronisasi.'
                  : 'Semua perubahan lokal sudah terkirim.',
              style: const TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: sync.isLoading || sync.isSyncing || !sync.isOnline
                  ? null
                  : () => sync.syncPendingActions(),
              icon: const Icon(Icons.sync_rounded),
              label: Text(
                sync.isSyncing ? 'Menyinkronkan…' : 'Sinkronkan sekarang',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
