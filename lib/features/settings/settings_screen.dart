import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import 'app_settings_controller.dart';
import 'user_preferences.dart';
import 'storage_screen.dart';
import '../help/help_screen.dart';
import '../../core/updates/update_gate.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _actionLabel(String path) {
    if (path.contains('substitute')) return 'Penugasan guru pengganti';
    final teacher = path.contains('teacher');
    final halaqoh = path.startsWith('/halaqoh');
    return 'Absensi ${teacher ? 'guru' : 'santri'}${halaqoh ? ' Halaqoh' : ''}';
  }

  String _details(Object? raw) {
    try {
      final body = jsonDecode(raw.toString()) as Map;
      final lines = <String>[];
      const labels = {
        'date': 'Tanggal',
        'status': 'Status',
        'materi': 'Materi',
        'rangkuman': 'Rangkuman',
        'notes': 'Catatan',
        'catatan': 'Catatan',
        'reason': 'Alasan',
      };
      for (final entry in labels.entries) {
        final value = body[entry.key]?.toString() ?? '';
        if (value.isNotEmpty) lines.add('${entry.value}: $value');
      }
      final records = body['records'];
      if (records is List) {
        for (final record in records.whereType<Map>()) {
          lines.add(
            '${record['student_name'] ?? 'Santri #${record['student_id']}'}: ${record['status'] ?? ''}${(record['notes'] ?? record['catatan'] ?? '').toString().isEmpty ? '' : ' · ${record['notes'] ?? record['catatan']}'}',
          );
        }
      }
      return lines.isEmpty
          ? 'Data tersimpan dan menunggu konfirmasi server.'
          : lines.join('\n');
    } catch (_) {
      return 'Detail belum dapat ditampilkan. Data asli tetap tersimpan.';
    }
  }

  bool _isSuperAdmin(Map<String, dynamic>? user) {
    final roles = ((user?['roles'] as List?) ?? [])
        .map((role) => (role['name'] ?? '').toString().toLowerCase())
        .toList();
    return roles.contains('super_admin');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final settings = context.watch<AppSettingsController>();
    final isSuperAdmin = _isSuperAdmin(auth.user);
    final preferences = context.watch<UserPreferences?>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const CheckUpdatesTile(),
        Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Pusat bantuan'),
                subtitle: const Text(
                  'Panduan offline, pengajuan, keamanan dan pelaporan masalah',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HelpScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Penyimpanan offline'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StorageScreen()),
                ),
              ),
              if (preferences != null) ...[
                SwitchListTile(
                  title: const Text('Kunci biometrik / PIN perangkat'),
                  subtitle: const Text(
                    'Kunci ketika aplikasi masuk latar belakang. Aktifkan PIN/pola perangkat terlebih dahulu.',
                  ),
                  value: preferences.lockEnabled,
                  onChanged: (value) async {
                    final success = await preferences.setLock(value);
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Verifikasi belum berhasil. Pastikan PIN/pola perangkat aktif, lalu coba lagi.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                SwitchListTile(
                  title: const Text('Kontras tinggi'),
                  value: preferences.highContrast,
                  onChanged: preferences.setContrast,
                ),
                ListTile(
                  title: const Text('Ukuran teks'),
                  subtitle: Text(
                    'Tambahan ${(preferences.textScale * 100).round()}% dari ukuran sistem',
                  ),
                ),
                Slider(
                  label: '${(preferences.textScale * 100).round()}%',
                  value: preferences.textScale,
                  min: 1,
                  max: 1.5,
                  divisions: 5,
                  onChanged: preferences.setScale,
                ),
              ],
            ],
          ),
        ),
        const Text(
          'Pengaturan Sinkronisasi',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Preferensi akun ini pada perangkat ini. ${settings.connectionLabel} · ${settings.pendingSyncCount} pengiriman menunggu konfirmasi.',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Pengingat jadwal saya'),
                subtitle: const Text(
                  'Jadwal hari ini dan pengingat 30 menit sebelum pelajaran, termasuk tugas pengganti. Tetap bekerja offline setelah jadwal diunduh.',
                ),
                value: settings.scheduleAlerts.enabled,
                onChanged: settings.setScheduleAlerts,
              ),
              if (settings.scheduleAlerts.supported &&
                  settings.scheduleAlerts.enabled) ...[
                ListTile(
                  title: const Text('Notifikasi Android'),
                  subtitle: Text(
                    settings.scheduleAlerts.allowed
                        ? 'Diizinkan'
                        : 'Belum diizinkan',
                  ),
                  trailing: TextButton(
                    onPressed: () => settings.scheduleAlerts.settings(),
                    child: const Text('Atur izin'),
                  ),
                ),
                if (!settings.scheduleAlerts.exact)
                  ListTile(
                    title: const Text('Alarm tepat waktu'),
                    subtitle: const Text(
                      'Izinkan agar pengingat 30 menit tidak ditunda oleh Android.',
                    ),
                    trailing: TextButton(
                      onPressed: () =>
                          settings.scheduleAlerts.settings(exactAlarm: true),
                      child: const Text('Izinkan'),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (settings.lastOfflinePreparation != null)
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: ListTile(
              leading: const Icon(Icons.offline_pin_outlined),
              title: const Text('Persiapan absensi offline'),
              subtitle: Text(
                '${settings.preparedAttendanceForms} formulir diunduh pada persiapan terakhir hari ini. Formulir lainnya akan disimpan saat dibuka online.',
              ),
            ),
          ),
        if (settings.lastSyncError != null)
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(settings.lastSyncError!),
            ),
          ),
        if (settings.lastSuccess != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Konfirmasi server terakhir: ${settings.lastSuccess}'),
          ),
        if (settings.legacyCount > 0)
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: ListTile(
              title: const Text('Antrean versi lama ditemukan'),
              subtitle: const Text(
                'Data tetap disimpan. Pulihkan hanya saat masuk dengan akun asal.',
              ),
              trailing: TextButton(
                onPressed: () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Pulihkan antrean akun ini?'),
                      content: const Text(
                        'Hanya data dengan ID akun asal yang cocok akan dipulihkan. Salinan lama tetap disimpan.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Batal'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Pulihkan'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true) {
                    await settings.importLegacyForCurrentUser();
                  }
                },
                child: const Text('Pulihkan'),
              ),
            ),
          ),
        Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mode sinkronisasi',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'wifi_only',
                      label: Text('Wi-Fi'),
                      icon: Icon(Icons.wifi_rounded),
                    ),
                    ButtonSegment<String>(
                      value: 'any_network',
                      label: Text('Wi-Fi/Data'),
                      icon: Icon(Icons.network_cell_rounded),
                    ),
                  ],
                  selected: {settings.syncMode},
                  onSelectionChanged: settings.isLoading
                      ? null
                      : (value) => settings.setSyncMode(value.first),
                ),
                const SizedBox(height: 8),
                Text(
                  settings.syncMode == 'wifi_only'
                      ? 'Data disimpan dalam antrean sampai Wi-Fi tersedia.'
                      : 'Sinkronisasi diizinkan memakai Wi-Fi atau data seluler.',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Text(
                  auth.rememberMe
                      ? 'Sinkronisasi otomatis saat terhubung. Android mengatur waktu pengiriman saat aplikasi ditutup.'
                      : 'Aktifkan Ingat perangkat ini saat masuk agar sinkronisasi dapat berjalan ketika aplikasi ditutup.',
                  style: const TextStyle(color: Colors.grey),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: settings.isSyncing
                        ? null
                        : settings.syncPendingActions,
                    icon: settings.isSyncing
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(
                      settings.isSyncing
                          ? 'Menyinkronkan...'
                          : 'Sinkronkan sekarang',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (settings.blockedSyncCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '${settings.blockedSyncCount} pengiriman perlu ditinjau. Server belum menerima data ini; data tidak dihapus.',
            ),
          ),
        for (final row in settings.queueItems)
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: ListTile(
              leading: Icon(
                row['state'] == 'blocked'
                    ? Icons.error_outline
                    : Icons.schedule,
              ),
              title: Text(_actionLabel((row['path'] ?? '').toString())),
              subtitle: Text(
                row['error']?.toString() ??
                    'Menunggu koneksi dan konfirmasi server',
              ),
              onTap: () async {
                final body = await settings.queueDetails(row['id'] as String);
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Data tersimpan pada akun ini'),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        body == null
                            ? 'Data sudah dikonfirmasi server.'
                            : _details(body),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Tutup'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        if (settings.blockedSyncCount > 0)
          OutlinedButton(
            onPressed: settings.isSyncing ? null : settings.retryBlocked,
            child: const Text('Coba ulang pengiriman yang ditolak'),
          ),
        if (isSuperAdmin) ...[
          const SizedBox(height: 18),
          const Text(
            'Control Center',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pengaturan ini khusus super admin dan dipakai untuk kontrol fitur aplikasi.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: SwitchListTile.adaptive(
              value: settings.isRamadhanTabEnabled,
              onChanged: settings.isLoading
                  ? null
                  : (value) => settings.setRamadhanTabEnabled(value),
              title: const Text(
                'Ramadhan tab aktif',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Jika dimatikan, pilihan Ramadhan akan disembunyikan dari Jadwal dan Stats.',
              ),
            ),
          ),
        ],
      ],
    );
  }
}
