import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/sync_store.dart';

class UserPreferences extends ChangeNotifier {
  static const device = MethodChannel('ibnu_hafidz/device_security');
  String? account;
  bool ready = false,
      highContrast = false,
      lockEnabled = false,
      locked = false,
      authenticating = false;
  double textScale = 1;
  int _generation = 0;
  void bind(Object? userId) {
    final next = userId == null ? null : SyncStore.account(userId);
    if (next == account && ready) return;
    if (next == account && _generation > 0) return;
    account = next;
    ready = false;
    highContrast = false;
    lockEnabled = false;
    locked = false;
    textScale = 1;
    final generation = ++_generation;
    unawaited(_load(generation));
  }

  Future<void> _load(int generation) async {
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation) return;
    if (account != null) {
      highContrast = prefs.getBool('ui::$account::contrast') ?? false;
      textScale = (prefs.getDouble('ui::$account::scale') ?? 1).clamp(1, 1.5);
      lockEnabled = prefs.getBool('ui::$account::lock') ?? false;
    }
    locked = lockEnabled;
    ready = true;
    notifyListeners();
  }

  Future<void> setScale(double value) async {
    final owner = account;
    if (owner == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ui::$owner::scale', value.clamp(1, 1.5));
    if (account == owner) {
      textScale = value.clamp(1, 1.5);
      notifyListeners();
    }
  }

  Future<void> setContrast(bool value) async {
    final owner = account;
    if (owner == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ui::$owner::contrast', value);
    if (account == owner) {
      highContrast = value;
      notifyListeners();
    }
  }

  Future<bool> authenticate() async {
    if (authenticating) return false;
    authenticating = true;
    try {
      return await device.invokeMethod<bool>('authenticate') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } finally {
      authenticating = false;
    }
  }

  Future<bool> setLock(bool value) async {
    final owner = account;
    if (owner == null || !await authenticate() || owner != account) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ui::$owner::lock', value);
    if (account != owner) return false;
    lockEnabled = value;
    locked = false;
    notifyListeners();
    return true;
  }

  void lock() {
    if (lockEnabled && !authenticating && !locked) {
      locked = true;
      notifyListeners();
    }
  }

  Future<void> unlock() async {
    final owner = account;
    if (await authenticate() && owner == account) {
      locked = false;
      notifyListeners();
    }
  }
}
