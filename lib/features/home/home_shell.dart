import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../jadwal/jadwal_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  List<String> _roleNames(Map<String, dynamic>? user) {
    return ((user?['roles'] as List?) ?? [])
        .map((role) => (role['name'] ?? '').toString().toLowerCase())
        .toList();
  }

  List<String> _permissionNames(Map<String, dynamic>? user) {
    final roles = (user?['roles'] as List?) ?? [];
    final permissions = <String>[];

    for (final role in roles) {
      final items = (role['permissions'] as List?) ?? [];
      for (final permission in items) {
        final name = (permission['name'] ?? '').toString().toLowerCase();
        if (name.isNotEmpty) permissions.add(name);
      }
    }

    return permissions;
  }

  bool _isSuperAdmin(Map<String, dynamic>? user) {
    return _roleNames(user).contains('super_admin');
  }

  bool _canViewStats(Map<String, dynamic>? user) {
    final roles = _roleNames(user);
    if (roles.any(
      (role) => ['super_admin', 'admin', 'staff', 'tim_presensi'].contains(role),
    )) {
      return true;
    }

    final permissions = _permissionNames(user);
    return permissions.any(
      (permission) => [
        'absensi.view',
        'absensi_diniyyah.view',
        'halaqoh.view',
      ].contains(permission),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final userName = auth.user?['name']?.toString() ?? 'User';
    final isSuperAdmin = _isSuperAdmin(auth.user);
    final canViewStats = _canViewStats(auth.user);
    final pages = [
      const JadwalScreen(),
      if (canViewStats) const StatsScreen(),
      if (isSuperAdmin) const SettingsScreen(),
    ];
    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.calendar_month_rounded),
        label: 'Jadwal',
      ),
      if (canViewStats)
        const NavigationDestination(
          icon: Icon(Icons.query_stats_rounded),
          label: 'Stats',
        ),
      if (isSuperAdmin)
        const NavigationDestination(
          icon: Icon(Icons.tune_rounded),
          label: 'Control',
        ),
    ];
    final safeIndex = _index >= pages.length ? 0 : _index;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Image.asset(
                'assets/branding/favicon.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Hi, $userName',
                style: const TextStyle(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
          )
        ],
      ),
      body: Column(
        children: [
          if (auth.isOfflineSession)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFFEF3C7),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 18, color: Color(0xFF92400E)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mode offline aktif dengan sesi tersimpan.',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: pages[safeIndex],
          ),
        ],
      ),
      bottomNavigationBar: destinations.length < 2
          ? null
          : NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: destinations,
            ),
    );
  }
}
