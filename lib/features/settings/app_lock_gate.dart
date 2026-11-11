import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'user_preferences.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      context.read<UserPreferences>().lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<UserPreferences>();
    return PopScope(
      canPop: !settings.locked,
      child: Stack(
        children: [
          Offstage(
            offstage: settings.locked,
            child: TickerMode(enabled: !settings.locked, child: widget.child),
          ),
          if (settings.locked)
            Positioned.fill(
              child: Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Aplikasi terkunci',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Gunakan biometrik atau PIN/pola perangkat untuk melanjutkan.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () async {
                              await settings.unlock();
                              if (context.mounted && settings.locked) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Belum berhasil membuka kunci. Coba lagi.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.fingerprint),
                            label: const Text('Buka kunci'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
