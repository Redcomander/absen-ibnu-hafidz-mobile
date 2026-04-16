import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'features/settings/app_settings_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IbnuHafidzApp());
}

class IbnuHafidzApp extends StatelessWidget {
  const IbnuHafidzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthController()..init()),
        ChangeNotifierProvider(
          create: (_) => AppSettingsController()..init(),
        ),
      ],
      child: MaterialApp(
        title: 'Ibnu Hafidz',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const RootGate(),
      ),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (auth.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isAuthenticated) {
      return const LoginScreen();
    }

    return const HomeShell();
  }
}
