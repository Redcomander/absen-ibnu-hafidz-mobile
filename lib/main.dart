import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/updates/app_update_controller.dart';
import 'core/updates/update_gate.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'features/settings/app_settings_controller.dart';
import 'features/settings/user_preferences.dart';
import 'features/settings/app_lock_gate.dart';

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
        ChangeNotifierProvider(create: (_) => AppUpdateController()),
        ChangeNotifierProvider(create: (_) => AuthController()..init()),
        ChangeNotifierProxyProvider<AuthController, UserPreferences>(
          create: (_) => UserPreferences(),
          update: (_, auth, preferences) {
            preferences!.bind(auth.user?['id']);
            return preferences;
          },
        ),

        ChangeNotifierProxyProvider<AuthController, AppSettingsController>(
          create: (_) => AppSettingsController()..init(),
          update: (_, auth, settings) {
            settings!.bindAccount(auth);
            return settings;
          },
        ),
      ],
      child: Consumer<UserPreferences>(
        builder: (context, preferences, _) => MaterialApp(
          key: ValueKey(preferences.account),
          title: 'Ibnu Hafidz',
          debugShowCheckedModeBanner: false,
          theme: preferences.highContrast
              ? AppTheme.light.copyWith(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: AppTheme.brand,
                    contrastLevel: 1,
                  ),
                  textTheme: AppTheme.light.textTheme.apply(
                    bodyColor: Colors.black,
                    displayColor: Colors.black,
                  ),
                  dividerColor: Colors.black,
                )
              : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.textScalerOf(context).scale(1) *
                    preferences.textScale,
              ),
            ),
            child: AppLockGate(child: AppUpdateGate(child: child!)),
          ),
          home: const RootGate(),
        ),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!auth.isAuthenticated) {
      return const LoginScreen();
    }

    final preferences = context.watch<UserPreferences>();
    if (!preferences.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return HomeShell(key: ValueKey(auth.user?['id']));
  }
}
