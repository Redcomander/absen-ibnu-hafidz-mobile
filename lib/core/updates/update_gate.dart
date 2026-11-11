import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_update_controller.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;
  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppUpdateController>().check();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppUpdateController>().resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppUpdateController>(), u = c.update;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: c.visible,
          child: ExcludeSemantics(
            excluding: c.visible,
            child: IgnorePointer(ignoring: c.visible, child: widget.child),
          ),
        ),
        if (c.visible && u != null)
          Positioned.fill(
            child: Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.system_update, size: 48),
                          const SizedBox(height: 18),
                          Text(
                            c.mandatory
                                ? 'Pembaruan diperlukan'
                                : 'Pembaruan tersedia',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Versi saat ini: ${c.installed?.version} (${c.installed?.code})\nVersi terbaru: ${u.version} (${u.code})\nUkuran APK: ${(u.size / 1048576).toStringAsFixed(1)} MB',
                          ),
                          const SizedBox(height: 16),
                          Text(
                            u.notes.isEmpty
                                ? 'Pembaruan aplikasi Ibnu Hafidz.'
                                : u.notes,
                          ),
                          if (c.mandatory)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Versi ini tidak lagi didukung. Perbarui aplikasi untuk melanjutkan. Data lokal tetap disimpan.',
                              ),
                            ),
                          if (c.downloading) ...[
                            const SizedBox(height: 18),
                            LinearProgressIndicator(value: c.progress),
                            Text('${(c.progress * 100).round()}%'),
                            TextButton(
                              onPressed: c.cancel,
                              child: const Text('Batalkan unduhan'),
                            ),
                          ],
                          if (c.error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                c.error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          if (c.message != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(c.message!),
                            ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed:
                                c.downloading || c.installing || c.checking
                                ? null
                                : c.apk != null
                                ? c.install
                                : c.download,
                            child: Text(
                              c.apk != null
                                  ? 'Pasang pembaruan'
                                  : c.error != null
                                  ? 'Coba unduh lagi'
                                  : 'Unduh pembaruan',
                            ),
                          ),
                          TextButton(
                            onPressed: c.checking || c.downloading
                                ? null
                                : () => c.check(manual: true),
                            child: Text(
                              c.checking ? 'Memeriksa...' : 'Periksa ulang',
                            ),
                          ),
                          if (!c.mandatory)
                            TextButton(
                              onPressed: c.dismiss,
                              child: const Text('Nanti Saja'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CheckUpdatesTile extends StatelessWidget {
  const CheckUpdatesTile({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppUpdateController?>();
    if (c == null || !c.service.supported) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.system_update_alt),
      title: const Text('Periksa Pembaruan'),
      subtitle: Text(
        c.checking
            ? 'Memeriksa...'
            : c.error ?? c.message ?? 'Periksa versi aplikasi terbaru',
      ),
      onTap: c.checking ? null : () => c.check(manual: true),
    );
  }
}
