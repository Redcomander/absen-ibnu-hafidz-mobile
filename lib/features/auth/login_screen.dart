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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 18),
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
              const Text('Selamat Datang',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text(
                'Masuk ke sistem absensi Ibnu Hafidz',
                style: TextStyle(color: AppTheme.muted),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _usernameCtrl,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
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
                title: const Text('Remember me'),
                subtitle: const Text(
                  'Tetap bisa masuk dengan sesi tersimpan saat koneksi sedang buruk.',
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Masuk'),
              ),
            ],
          ),
        ),
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
