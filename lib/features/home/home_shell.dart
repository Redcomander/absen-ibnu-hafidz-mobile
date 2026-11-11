import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../jadwal/jadwal_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import '../../core/theme/app_theme.dart';
import '../../core/notifications/schedule_alerts.dart';
import 'dashboard_screen.dart';
import 'floating_navigation_bar.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transition;
  double _slideFrom = .025;

  void _selectTab(int index) {
    if (index == _index) return;
    setState(() {
      _slideFrom = index > _index ? .025 : -.025;
      _index = index;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _transition.value = 1;
    } else {
      _transition.forward(from: 0);
    }
  }

  int _index = 0;
  @override
  void initState() {
    super.initState();
    _transition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1,
    );
    if (ScheduleAlerts.openSchedule.value > 0) {
      _index = 1;
      ScheduleAlerts.openSchedule.value = 0;
    }
    ScheduleAlerts.openSchedule.addListener(_openSchedule);
  }

  void _openSchedule() {
    if (ScheduleAlerts.openSchedule.value == 0) return;
    ScheduleAlerts.openSchedule.value = 0;
    if (mounted) _selectTab(1);
  }

  @override
  void dispose() {
    ScheduleAlerts.openSchedule.removeListener(_openSchedule);
    _transition.dispose();
    super.dispose();
  }

  final Set<String> _openedPages = {};
  Object? _pageOwner;

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

  bool _canViewStats(Map<String, dynamic>? user) {
    final roles = _roleNames(user);
    if (roles.any(
      (role) =>
          ['super_admin', 'admin', 'staff', 'tim_presensi'].contains(role),
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
    final canViewStats = _canViewStats(auth.user);
    if (_pageOwner != auth.user?['id']) {
      _openedPages.clear();
      _pageOwner = auth.user?['id'];
    }
    final pageIds = ['home', 'jadwal', if (canViewStats) 'stats', 'settings'];
    final pages = [
      DashboardScreen(
        onOpenSchedule: () => _selectTab(1),
        onOpenSettings: () => _selectTab(canViewStats ? 3 : 2),
        onOpenStats: canViewStats ? () => _selectTab(2) : null,
      ),
      const JadwalScreen(),
      if (canViewStats) const StatsScreen(),
      const SettingsScreen(),
    ];
    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: 'Beranda',
      ),
      const NavigationDestination(
        icon: Icon(Icons.calendar_month_rounded),
        label: 'Jadwal',
      ),
      if (canViewStats)
        const NavigationDestination(
          icon: Icon(Icons.query_stats_rounded),
          label: 'Rekapan',
        ),
      const NavigationDestination(
        icon: Icon(Icons.tune_rounded),
        label: 'Pengaturan',
      ),
    ];
    final safeIndex = _index >= pages.length ? 0 : _index;
    _openedPages.add(pageIds[safeIndex]);

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
                'IBNU HAFIDZ',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 2,
                  color: AppTheme.brand,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Keluar dari akun?'),
                  content: const Text(
                    'Pastikan perubahan offline sudah tersinkron sebelum keluar.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Batal'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Keluar'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await auth.logout();
            },
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Keluar',
          ),
        ],
      ),
      body: Column(
        children: [
          if (auth.isOfflineSession)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFFEF3C7),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 18,
                    color: Color(0xFF92400E),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      auth.sessionWarning ??
                          'Menggunakan sesi tersimpan. Server belum terhubung.',
                      style: const TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: auth.isReconnecting
                        ? null
                        : () => auth.reconnect(),
                    child: Text(
                      auth.isReconnecting ? 'Memeriksa…' : 'Coba lagi',
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: FadeTransition(
              opacity: _transition.drive(
                Tween(
                  begin: .65,
                  end: 1.0,
                ).chain(CurveTween(curve: Curves.easeOutCubic)),
              ),
              child: SlideTransition(
                position: _transition.drive(
                  Tween(
                    begin: Offset(_slideFrom, 0),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOutCubic)),
                ),
                child: IndexedStack(
                  index: safeIndex,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      KeyedSubtree(
                        key: ValueKey('${auth.user?['id']}:${pageIds[i]}'),
                        child: TickerMode(
                          enabled: i == safeIndex,
                          child: _openedPages.contains(pageIds[i])
                              ? pages[i]
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: destinations.length < 2
          ? null
          : FloatingNavigationBar(
              selectedIndex: safeIndex,
              onSelected: _selectTab,
              destinations: destinations,
            ),
    );
  }
}
