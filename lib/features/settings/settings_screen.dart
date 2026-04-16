import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import 'app_settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text(
          'Pengaturan Sinkronisasi',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Mode semi online aktif. Status saat ini: ${settings.connectionLabel}. Pending sync: ${settings.pendingSyncCount}.',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Card(
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
                      ? 'Default aman. Data antre jika hanya ada seluler.'
                      : 'Sinkronisasi diizinkan memakai Wi-Fi atau data seluler.',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed:
                        settings.isSyncing ? null : settings.syncPendingActions,
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
