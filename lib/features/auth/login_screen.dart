import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  bool _rememberMe = true;
  bool _initializedRemember = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!_initializedRemember) {
      _rememberMe = auth.rememberMe;
      if ((auth.lastUsername ?? '').isNotEmpty) {
        _usernameCtrl.text = auth.lastUsername!;
      }
      _initializedRemember = true;
    }
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 64,
                    height: 64,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.brand.withValues(alpha: 0.20),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/branding/favicon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('IBNU HAFIDZ',
                      style: TextStyle(
                          color: AppTheme.brand,
                          letterSpacing: 3,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 36),
                  const Text('Selamat Datang',
                      style: TextStyle(
                          fontSize: 34,
                          height: 1.2,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text(
                    'Satu ruang untuk mendampingi\nperjalanan belajar santri.',
                    style: TextStyle(color: AppTheme.muted, height: 1.7),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _usernameCtrl,
                    enabled: !_loading,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    enabled: !_loading,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_loading) _submit();
                    },
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'Kata sandi',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? 'Sembunyikan kata sandi'
                            : 'Tampilkan kata sandi',
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(_showPassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: _rememberMe,
                    onChanged: (value) {
                      setState(() => _rememberMe = value ?? true);
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Ingat perangkat ini'),
                    subtitle: const Text(
                      'Tetap bisa masuk dengan sesi tersimpan saat koneksi sedang buruk.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Masuk'),
                      )),
                  const SizedBox(height: 28),
                  const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_user_outlined,
                            size: 18, color: AppTheme.muted),
                        SizedBox(width: 10),
                        Expanded(
                            child: Text(
                                'Gunakan akun yang diberikan oleh pengelola pesantren.',
                                style: TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 12,
                                    height: 1.6))),
                      ]),
                ],
              ),
            ))),
      ),
    );
  }

  Future<void> _submit() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      _toast('Username dan password wajib diisi');
      return;
    }

    setState(() => _loading = true);
    try {
      final auth = context.read<AuthController>();
      await auth.login(
        username,
        password,
        rememberMe: _rememberMe,
      );
    } catch (e) {
      if (!mounted) return;

      final auth = context.read<AuthController>();
      if (_rememberMe && auth.shouldUseOfflineFallback(e)) {
        final restored = await auth.restoreCachedSession(username: username);
        if (!mounted) return;

        if (restored) {
          _toast(
            'Masuk dengan sesi tersimpan karena koneksi sedang bermasalah',
          );
          return;
        }
      }

      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
